#!/usr/bin/env bash
# Módulo client_profile — gera o perfil .ovpn do cliente, QR Code e listagem.
# O .ovpn leva os certificados embutidos (inline), então é um único arquivo.
# Depende dos módulos core, log, pki, wizard_ipproto, server_config e ccd.

: "${OVPN_PROTO:=udp}"
: "${OVPN_PORT:=1194}"
: "${OVPN_DATA_CIPHERS:=AES-256-GCM:AES-128-GCM}"
OVPN_REMOTE_HOST_PLACEHOLDER='ALTERE-PARA-O-IP-OU-DOMINIO-DO-HUB'
: "${OVPN_REMOTE_HOST:=${OVPN_REMOTE_HOST_PLACEHOLDER}}"
: "${OVPN_HOME_DIR:=${HOME}}"

# Seam: existe qrencode? (substituível nos testes)
_ovpn_has_qrencode() {
    command -v qrencode >/dev/null 2>&1
}

# Caminho do perfil de um cliente.
ovpn_client_profile_path() {
    printf '%s' "${OVPN_CLIENTS_DIR}/${1}.ovpn"
}

# Cria o perfil do cliente: emite o certificado, atribui IP fixo e escreve o
# .ovpn com ca/cert/key/tls-crypt embutidos. Copia o arquivo para o home.
ovpn_client_create() {
    local name="$1"
    mkdir -p "${OVPN_CLIENTS_DIR}"
    ovpn_pki_issue_client "${name}" >/dev/null
    local ip
    ip="$(ovpn_ccd_assign "${name}")"

    local profile
    profile="$(ovpn_client_profile_path "${name}")"
    {
        printf 'client\n'
        printf 'dev tun\n'
        printf 'proto %s\n' "${OVPN_PROTO}"
        printf 'remote %s %s\n' "${OVPN_REMOTE_HOST}" "${OVPN_PORT}"
        # Segundo hub (dual-hub ativo-ativo): o cliente tenta um, depois o outro.
        if [[ -n "${OVPN_REMOTE_HOST_2:-}" ]]; then
            printf 'remote %s %s\n' "${OVPN_REMOTE_HOST_2}" "${OVPN_PORT}"
            printf 'remote-random\n'
        fi
        printf 'resolv-retry infinite\n'
        printf 'nobind\n'
        printf 'remote-cert-tls server\n'
        printf 'data-ciphers %s\n' "${OVPN_DATA_CIPHERS}"
        printf 'verb 3\n'
        printf '<ca>\n'; cat "$(ovpn_pki_ca_cert)"; printf '</ca>\n'
        printf '<cert>\n'; cat "${OVPN_PKI_DIR}/issued/${name}.crt"; printf '</cert>\n'
        printf '<key>\n'; cat "${OVPN_PKI_DIR}/private/${name}.key"; printf '</key>\n'
        printf '<tls-crypt>\n'; cat "$(ovpn_pki_tls_crypt)"; printf '</tls-crypt>\n'
    } > "${profile}"

    # Cópia no home do operador, para transferência fácil.
    mkdir -p "${OVPN_HOME_DIR}"
    cp "${profile}" "${OVPN_HOME_DIR}/${name}.ovpn"

    ovpn_log_ok "Perfil criado: ${profile} (IP fixo ${ip}; cópia em ${OVPN_HOME_DIR})."
}

# Mostra o QR Code do perfil no terminal (para o app do celular escanear).
ovpn_client_qr() {
    local name="$1"
    local profile
    profile="$(ovpn_client_profile_path "${name}")"
    if _ovpn_has_qrencode; then
        qrencode -t ANSIUTF8 < "${profile}"
    else
        ovpn_log_warn "qrencode não instalado — QR não gerado. Instale 'qrencode' para usar."
        return 0
    fi
}

# Revoga o acesso de um cliente: revoga o certificado (CRL), libera o IP fixo e
# remove o perfil gerado (e a cópia no home).
ovpn_client_revoke() {
    local name="$1"
    if [[ -z "${name}" ]]; then
        ovpn_log_warn "Nome do cliente vazio."
        return 1
    fi
    ovpn_pki_revoke_client "${name}"
    rm -f "$(ovpn_ccd_dir)/${name}"
    rm -f "$(ovpn_client_profile_path "${name}")"
    rm -f "${OVPN_HOME_DIR}/${name}.ovpn"
    ovpn_log_ok "Acesso de ${name} revogado e perfil removido."
}

# Lista os clientes cadastrados e seus IPs fixos.
ovpn_client_list() {
    local dir f name ip
    dir="$(ovpn_ccd_dir)"
    [[ -d "${dir}" ]] || return 0
    for f in "${dir}"/*; do
        [[ -e "${f}" ]] || continue
        name="$(basename "${f}")"
        ip="$(awk '/ifconfig-push/ {print $2}' "${f}")"
        printf '%s\t%s\n' "${name}" "${ip}"
    done
}
