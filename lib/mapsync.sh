#!/usr/bin/env bash
# Módulo mapsync — sincronização automática do mapa cliente->IP entre os hubs.
#
# O hub PRIMÁRIO (alocador) publica o mapa num caminho fixo a cada mudança de
# cliente; cada SPOKE PUXA esse mapa pelo enlace (ovpn-link) via SSH com uma
# CHAVE RESTRITA (forced-command que só lê o mapa) e o importa por um timer
# systemd. Reusa lib/route_sync (bundle verificável: checksum + DOMAIN_ID) e o
# enlace já cifrado (tls-crypt). Pull de uma fonte de verdade única = robusto e
# auto-corretivo (igual ao reconciliador). Ver ADR 0005. Depende de core, log,
# ccd e route_sync. Comandos externos: ssh, ssh-keygen, systemctl (seams/stubs).

: "${OVPN_MAP_BUNDLE:=/var/lib/openvpn-installer/clients-map.tar.gz}"
: "${OVPN_MAPSYNC_DIR:=/etc/openvpn-installer}"
: "${OVPN_MAPSYNC_KEY:=${OVPN_MAPSYNC_DIR}/mapsync_key}"
: "${OVPN_MAPSYNC_AUTHKEYS:=/root/.ssh/authorized_keys}"
: "${OVPN_MAPSYNC_BIN:=/usr/local/lib/openvpn-installer/mapsync-pull.sh}"
: "${OVPN_TRANSPORT_NET_V4:=10.255.0.0}"
: "${OVPN_SYSTEMD_DIR:=/etc/systemd/system}"
: "${OVPN_LIB_DIR:=/root/OpenVPN-Installer/lib}"

# IP de transporte do core (o primário é sempre o .1 da rede de transporte).
_ovpn_mapsync_core_ip() { printf '%s.1' "${OVPN_TRANSPORT_NET_V4%.*}"; }

# PRIMÁRIO: publica o mapa atual num caminho fixo (que a chave restrita serve).
ovpn_mapsync_publish() {
    mkdir -p "$(dirname "${OVPN_MAP_BUNDLE}")"
    ovpn_route_sync_export "${OVPN_MAP_BUNDLE}"
}

# SPOKE: gera (idempotente) o par de chaves do pull e ECOA a chave PÚBLICA, para
# o operador autorizá-la no primário.
ovpn_mapsync_keygen() {
    mkdir -p "${OVPN_MAPSYNC_DIR}"
    if [[ ! -f "${OVPN_MAPSYNC_KEY}" ]]; then
        ssh-keygen -t ed25519 -N "" -C "openvpn-installer-mapsync" -f "${OVPN_MAPSYNC_KEY}" >/dev/null
        chmod 600 "${OVPN_MAPSYNC_KEY}" 2>/dev/null || true
    fi
    cat "${OVPN_MAPSYNC_KEY}.pub"
}

# PRIMÁRIO: autoriza a chave pública do spoke com forced-command — a sessão SSH
# daquela chave só consegue LER o mapa (sem shell). Idempotente.
ovpn_mapsync_authorize() {
    local pubkey="$1" dir keyfield
    [[ -n "${pubkey}" ]] || ovpn_die "Informe a chave pública do spoke."
    dir="$(dirname "${OVPN_MAPSYNC_AUTHKEYS}")"
    mkdir -p "${dir}"; chmod 700 "${dir}" 2>/dev/null || true
    touch "${OVPN_MAPSYNC_AUTHKEYS}"
    keyfield="$(printf '%s' "${pubkey}" | awk '{print $2}')"
    if [[ -n "${keyfield}" ]] && ! grep -q -- "${keyfield}" "${OVPN_MAPSYNC_AUTHKEYS}" 2>/dev/null; then
        printf 'command="cat %s",restrict %s\n' "${OVPN_MAP_BUNDLE}" "${pubkey}" >> "${OVPN_MAPSYNC_AUTHKEYS}"
        chmod 600 "${OVPN_MAPSYNC_AUTHKEYS}" 2>/dev/null || true
    fi
}

# SPOKE: puxa o mapa do primário pelo enlace e importa. Idempotente (o import
# sobrescreve os mesmos ifconfig-push); silencioso e tolerante a falha de rede
# (o timer tenta de novo).
ovpn_mapsync_pull() {
    local core_ip tmp
    core_ip="$(_ovpn_mapsync_core_ip)"
    tmp="$(mktemp)"
    if ssh -i "${OVPN_MAPSYNC_KEY}" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout=10 "root@${core_ip}" > "${tmp}" 2>/dev/null && [[ -s "${tmp}" ]]; then
        ovpn_route_sync_import "${tmp}" >/dev/null 2>&1 || true
    fi
    rm -f "${tmp}"
}

# SPOKE: instala o entrypoint + units systemd (timer que puxa o mapa) e habilita.
ovpn_mapsync_install_units() {
    mkdir -p "$(dirname "${OVPN_MAPSYNC_BIN}")" "${OVPN_SYSTEMD_DIR}"

    cat > "${OVPN_MAPSYNC_BIN}" <<BIN
#!/usr/bin/env bash
set -euo pipefail
source "${OVPN_LIB_DIR}/core.sh"
source "${OVPN_LIB_DIR}/log.sh"
source "${OVPN_LIB_DIR}/ccd.sh"
source "${OVPN_LIB_DIR}/route_sync.sh"
source "${OVPN_LIB_DIR}/mapsync.sh"
ovpn_mapsync_pull
BIN
    chmod +x "${OVPN_MAPSYNC_BIN}"

    cat > "${OVPN_SYSTEMD_DIR}/openvpn-mapsync.service" <<UNIT
[Unit]
Description=Sincroniza o mapa cliente->IP do hub primario (pull pelo enlace)
[Service]
Type=oneshot
ExecStart=${OVPN_MAPSYNC_BIN}
UNIT

    cat > "${OVPN_SYSTEMD_DIR}/openvpn-mapsync.timer" <<UNIT
[Unit]
Description=Sincronizacao periodica do mapa de clientes
[Timer]
OnBootSec=60
OnUnitActiveSec=120
[Install]
WantedBy=timers.target
UNIT

    systemctl daemon-reload
    systemctl enable --now openvpn-mapsync.timer
}
