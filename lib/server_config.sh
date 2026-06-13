#!/usr/bin/env bash
# Módulo server_config — gera o server.conf e gerencia o serviço systemd.
# Topologia: tun + topology subnet + client-to-client + tls-crypt.
# Depende dos módulos core, log, pki e wizard_ipproto.

: "${OVPN_SERVER_NAME:=server}"
: "${OVPN_DATA_CIPHERS:=AES-256-GCM:AES-128-GCM}"

# Caminhos derivados.
ovpn_server_conf_path() { printf '%s' "${OVPN_SERVER_DIR}/${OVPN_SERVER_NAME}.conf"; }
ovpn_server_ccd_dir()   { printf '%s' "${OVPN_SERVER_DIR}/ccd"; }

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
        printf 'client-to-client\n'
        printf 'client-config-dir %s\n' "${ccd}"
        printf 'keepalive 10 120\n'
        printf 'persist-key\n'
        printf 'persist-tun\n'
        printf 'user nobody\n'
        printf 'group nogroup\n'
        printf 'verb 3\n'
    } > "$(ovpn_server_conf_path)"
}

# Habilita e inicia o serviço do servidor via systemd.
ovpn_server_enable() {
    systemctl enable --now "openvpn-server@${OVPN_SERVER_NAME}"
}

# Mostra se o serviço está ativo.
ovpn_server_status() {
    systemctl is-active "openvpn-server@${OVPN_SERVER_NAME}"
}
