#!/usr/bin/env bash
# Módulo mikrotik_profile — perfil OpenVPN compatível com MikroTik/RouterOS.
#
# Particularidades do RouterOS (isoladas aqui, fora dos perfis padrão):
#   - não faz negociação de cipher (NCP): o cipher precisa ser EXPLÍCITO;
#   - não suporta compressão LZO;
#   - tls-crypt exige RouterOS v7.17+ (ver docs/mikrotik-guide.md);
#   - UDP exige RouterOS v7+ (senão use TCP).
# Depende dos módulos core, log, pki, wizard_ipproto, server_config e ccd.

: "${OVPN_PROTO:=udp}"
: "${OVPN_PORT:=1194}"
: "${OVPN_REMOTE_HOST:=ALTERE-PARA-O-IP-OU-DOMINIO-DO-HUB}"
# Cipher explícito (deve estar entre os data-ciphers aceitos pelo servidor).
: "${OVPN_MIKROTIK_CIPHER:=AES-256-GCM}"
: "${OVPN_MIKROTIK_AUTH:=SHA256}"

ovpn_mikrotik_profile_path() { printf '%s' "${OVPN_CLIENTS_DIR}/${1}.mikrotik.ovpn"; }
ovpn_mikrotik_rsc_path()     { printf '%s' "${OVPN_CLIENTS_DIR}/${1}.rsc"; }

# Cria o perfil .ovpn compatível com RouterOS e o script .rsc para colar no
# terminal do MikroTik.
ovpn_mikrotik_create() {
    local name="$1"
    mkdir -p "${OVPN_CLIENTS_DIR}"
    ovpn_pki_issue_client "${name}" >/dev/null
    ovpn_ccd_assign "${name}" >/dev/null

    local prof rsc
    prof="$(ovpn_mikrotik_profile_path "${name}")"
    rsc="$(ovpn_mikrotik_rsc_path "${name}")"

    # --- .ovpn (cipher explícito, sem LZO) ---
    {
        printf 'client\n'
        printf 'dev tun\n'
        printf 'proto %s\n' "${OVPN_PROTO}"
        printf 'remote %s %s\n' "${OVPN_REMOTE_HOST}" "${OVPN_PORT}"
        printf 'nobind\n'
        printf 'persist-key\n'
        printf 'remote-cert-tls server\n'
        printf 'cipher %s\n' "${OVPN_MIKROTIK_CIPHER}"
        printf 'auth %s\n' "${OVPN_MIKROTIK_AUTH}"
        printf 'verb 3\n'
        printf '<ca>\n'; cat "$(ovpn_pki_ca_cert)"; printf '</ca>\n'
        printf '<cert>\n'; cat "${OVPN_PKI_DIR}/issued/${name}.crt"; printf '</cert>\n'
        printf '<key>\n'; cat "${OVPN_PKI_DIR}/private/${name}.key"; printf '</key>\n'
        printf '<tls-crypt>\n'; cat "$(ovpn_pki_tls_crypt)"; printf '</tls-crypt>\n'
    } > "${prof}"

    # --- .rsc (comandos RouterOS prontos para colar) ---
    {
        printf '# Comandos RouterOS para o cliente "%s".\n' "${name}"
        printf '# Antes: importe os certificados (ca, cert do cliente) em /certificate.\n'
        printf '# Requer RouterOS v7+ (UDP) e v7.17+ para tls-crypt. Ver mikrotik-guide.md.\n'
        printf '/interface ovpn-client add name=ovpn-%s connect-to=%s port=%s \\\n' \
            "${name}" "${OVPN_REMOTE_HOST}" "${OVPN_PORT}"
        printf '    protocol=%s mode=ip user="%s" \\\n' "${OVPN_PROTO}" "${name}"
        printf '    cipher=%s auth=%s certificate=%s-cert \\\n' \
            "${OVPN_MIKROTIK_CIPHER}" "${OVPN_MIKROTIK_AUTH}" "${name}"
        printf '    verify-server-certificate=yes disabled=no\n'
    } > "${rsc}"

    ovpn_log_ok "Perfil MikroTik criado: ${prof} e script ${rsc}."
}
