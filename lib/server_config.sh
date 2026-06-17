#!/usr/bin/env bash
# Módulo server_config — gera o server.conf e gerencia o serviço systemd.
# Topologia: tun + topology subnet + client-to-client + tls-crypt.
# Depende dos módulos core, log, pki e wizard_ipproto.

: "${OVPN_SERVER_NAME:=server}"
: "${OVPN_DATA_CIPHERS:=AES-256-GCM:AES-128-GCM}"
# MSS clamping: limita o tamanho do pacote no túnel para evitar travas de MTU
# (HTTPS/transferências grandes penduram enquanto ping/SSH passam). Vale p/ IPv4 e IPv6.
: "${OVPN_MSSFIX:=1420}"
# Roteamento dinâmico (IP estável global): off por padrão preserva o
# comportamento estático atual. Ver épico FRR+OSPF (ADR 0005).
: "${OVPN_DYNROUTING:=off}"
: "${OVPN_HOOKS_DIR:=${OVPN_SERVER_DIR}/hooks}"
: "${OVPN_STATUS_FILE:=/run/openvpn-server/status-${OVPN_SERVER_NAME}.log}"
: "${OVPN_RECONCILE_SPOOL:=/run/openvpn-installer/reconcile.trigger}"

# Caminhos derivados.
ovpn_server_conf_path() { printf '%s' "${OVPN_SERVER_DIR}/${OVPN_SERVER_NAME}.conf"; }
ovpn_server_ccd_dir()   { printf '%s' "${OVPN_SERVER_DIR}/ccd"; }

# Diretivas do modo dinâmico (status + hooks). No modo estático (default), não
# emite nada — o server.conf fica idêntico ao atual. Os hooks só SINALIZAM o
# reconciliador (que roda como root); o OpenVPN aqui já roda como nobody.
_ovpn_server_dynrouting_lines() {
    [[ "${OVPN_DYNROUTING}" == "on" ]] || return 0
    printf 'status-version 2\n'
    printf 'status %s 5\n' "${OVPN_STATUS_FILE}"
    printf 'script-security 2\n'
    printf 'client-connect %s/connect.sh\n' "${OVPN_HOOKS_DIR}"
    printf 'client-disconnect %s/disconnect.sh\n' "${OVPN_HOOKS_DIR}"
}

# Gera os hooks client-connect/disconnect: scripts triviais e auditáveis que
# apenas acrescentam uma linha no spool do reconciliador (gravável por nobody),
# sem nenhuma lógica de rota. O caminho do spool é fixado no script na geração.
ovpn_server_render_hooks() {
    local dir="${OVPN_HOOKS_DIR}" h
    mkdir -p "${dir}"
    for h in connect disconnect; do
        cat > "${dir}/${h}.sh" <<HOOK
#!/usr/bin/env bash
# Hook ${h} (gerado) — só sinaliza o reconciliador de rotas; nunca mexe em rota.
printf '%s %s\n' "\$(date +%s 2>/dev/null)" "${h}" >> "${OVPN_RECONCILE_SPOOL}" 2>/dev/null || true
exit 0
HOOK
        chmod +x "${dir}/${h}.sh"
    done
}

# Renderiza o server.conf para o modo de IP indicado (ipv4 nesta versão).
ovpn_server_render() {
    local mode="${1:-ipv4}"
    mkdir -p "${OVPN_SERVER_DIR}"
    local ccd
    ccd="$(ovpn_server_ccd_dir)"
    mkdir -p "${ccd}"
    {
        printf 'dev tun\n'
        printf 'topology subnet\n'
        ovpn_wizard_ipproto "${mode}"
        printf 'ca %s\n' "$(ovpn_pki_ca_cert)"
        printf 'cert %s/issued/%s.crt\n' "${OVPN_PKI_DIR}" "${OVPN_SERVER_NAME}"
        printf 'key %s/private/%s.key\n' "${OVPN_PKI_DIR}" "${OVPN_SERVER_NAME}"
        printf 'dh none\n'
        printf 'tls-crypt %s\n' "$(ovpn_pki_tls_crypt)"
        printf 'data-ciphers %s\n' "${OVPN_DATA_CIPHERS}"
        printf 'mssfix %s\n' "${OVPN_MSSFIX}"
        printf 'client-to-client\n'
        printf 'client-config-dir %s\n' "${ccd}"
        _ovpn_server_dynrouting_lines
        printf 'keepalive 10 120\n'
        printf 'persist-key\n'
        printf 'persist-tun\n'
        printf 'user nobody\n'
        printf 'group nogroup\n'
        printf 'verb 3\n'
    } > "$(ovpn_server_conf_path)"
}

# Habilita o encaminhamento de pacotes necessário para o modo escolhido.
# IPv6 (modos ipv6/dual) precisa de net.ipv6.conf.all.forwarding=1 para rotear
# além do tun. O encaminhamento IPv4 fica a cargo do módulo gateway (quando o
# operador ativa a saída para a internet), pois o client-to-client não o exige.
ovpn_server_apply_forwarding() {
    local mode="${1:-ipv4}"
    case "${mode}" in
        ipv6|dual)
            ovpn_sysctl_set net.ipv6.conf.all.forwarding 1
            ;;
    esac
}

# Habilita e inicia o serviço do servidor via systemd.
ovpn_server_enable() {
    systemctl enable --now "openvpn-server@${OVPN_SERVER_NAME}"
}

# Mostra se o serviço está ativo.
ovpn_server_status() {
    systemctl is-active "openvpn-server@${OVPN_SERVER_NAME}"
}
