#!/usr/bin/env bash
# Módulo route_reconcile — reconciliador root das rotas /32 dos clientes.
#
# Lê o arquivo `status` do OpenVPN (lista de clientes conectados e seus IPs
# virtuais) e mantém uma rota /32 de kernel (proto static) por cliente
# conectado — que o FRR redistribui no OSPF (ver lib/frr.sh). É idempotente e
# auto-corretivo: o estado real vem do `status`, não dos hooks (que só
# sinalizam). Roda como ROOT, fora do priv-drop do OpenVPN (que roda como
# nobody). Depende do comando `ip` (seam, substituível por stub nos testes).

: "${OVPN_TUN_IFACE:=tun0}"
: "${OVPN_RECONCILE_BIN:=/usr/local/lib/openvpn-installer/route-reconcile.sh}"
: "${OVPN_SYSTEMD_DIR:=/etc/systemd/system}"
: "${OVPN_RECONCILE_SPOOL:=/run/openvpn-installer/reconcile.trigger}"
: "${OVPN_STATUS_FILE:=/run/openvpn-server/status-server.log}"
: "${OVPN_LIB_DIR:=/root/OpenVPN-Installer/lib}"

# Extrai os IPs virtuais IPv4 dos clientes conectados. No status-version 2 as
# linhas CLIENT_LIST têm o IP virtual no 4º campo (CSV).
ovpn_reconcile_parse_status() {
    local f="$1"
    [[ -f "${f}" ]] || return 0
    awk -F',' '$1 == "CLIENT_LIST" && $4 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print $4 }' "${f}"
}

# Reconcilia as rotas /32: instala/atualiza as dos clientes conectados e remove
# as `proto static` órfãs (clientes que já saíram). Idempotente; só toca rotas
# `proto static` no tun, nunca a rota conectada do espaço nem rotas de terceiros.
ovpn_reconcile_apply() {
    local status="$1" tun="${OVPN_TUN_IFACE}"
    local connected c existing e ip_only
    connected=" $(ovpn_reconcile_parse_status "${status}" | tr '\n' ' ') "

    for c in ${connected}; do
        ip route replace "${c}/32" dev "${tun}" proto static metric 50 || true
    done

    existing="$(ip route show proto static dev "${tun}" 2>/dev/null | awk '{print $1}')"
    for e in ${existing}; do
        [[ "${e}" == */32 ]] || continue
        ip_only="${e%/32}"
        case "${connected}" in
            *" ${ip_only} "*) ;;   # ainda conectado — mantém
            *) ip route del "${e}" 2>/dev/null || true ;;
        esac
    done
}

# Instala o entrypoint root + as units systemd e as habilita: service oneshot
# (chama o reconciliador), path (observa o spool dos hooks) e timer (rede de
# segurança a cada 30s, caso o path perca um evento).
ovpn_reconcile_install_units() {
    mkdir -p "$(dirname "${OVPN_RECONCILE_BIN}")" "${OVPN_SYSTEMD_DIR}" \
        "$(dirname "${OVPN_RECONCILE_SPOOL}")"

    cat > "${OVPN_RECONCILE_BIN}" <<BIN
#!/usr/bin/env bash
set -euo pipefail
source "${OVPN_LIB_DIR}/route_reconcile.sh"
ovpn_reconcile_apply "${OVPN_STATUS_FILE}"
BIN
    chmod +x "${OVPN_RECONCILE_BIN}"

    cat > "${OVPN_SYSTEMD_DIR}/openvpn-route-reconcile.service" <<UNIT
[Unit]
Description=Reconcilia as rotas /32 dos clientes OpenVPN para o OSPF
[Service]
Type=oneshot
ExecStart=${OVPN_RECONCILE_BIN}
UNIT

    cat > "${OVPN_SYSTEMD_DIR}/openvpn-route-reconcile.path" <<UNIT
[Unit]
Description=Dispara o reconciliador quando um cliente conecta ou desconecta
[Path]
PathModified=${OVPN_RECONCILE_SPOOL}
[Install]
WantedBy=multi-user.target
UNIT

    cat > "${OVPN_SYSTEMD_DIR}/openvpn-route-reconcile.timer" <<UNIT
[Unit]
Description=Reconciliacao periodica das rotas /32 (rede de seguranca)
[Timer]
OnBootSec=30
OnUnitActiveSec=30
[Install]
WantedBy=timers.target
UNIT

    systemctl daemon-reload
    systemctl enable --now openvpn-route-reconcile.path openvpn-route-reconcile.timer
}
