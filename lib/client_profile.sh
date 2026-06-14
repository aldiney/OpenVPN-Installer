#!/usr/bin/env bash
# Módulo client_profile — gera o perfil .ovpn do cliente, QR Code e listagem.
# O .ovpn leva os certificados embutidos (inline), então é um único arquivo.
# Depende dos módulos core, log, pki, wizard_ipproto, server_config e ccd.

: "${OVPN_PROTO:=udp}"
: "${OVPN_PORT:=1194}"
: "${OVPN_DATA_CIPHERS:=AES-256-GCM:AES-128-GCM}"
OVPN_REMOTE_HOST_PLACEHOLDER='ALTERE-PARA-O-IP-OU-DOMINIO-DO-HUB'
: "${OVPN_REMOTE_HOST:=${OVPN_REMOTE_HOST_PLACEHOLDER}}"
: "${OVPN_HOME_DIR:=${HOME}/ovpn-clients}"
: "${OVPN_FULL_TUNNEL_DNS:=1.1.1.1 8.8.8.8}"

# Emite o bloco de roteamento do .ovpn conforme o modo (client-side):
#   full    -> todo o tráfego pela VPN + DNS + block-outside-dns (Windows).
#   split   -> só as sub-redes informadas (routes_csv = "rede máscara,rede máscara").
#   default -> nada (o cliente só alcança a rede da VPN).
# 'setenv opt block-outside-dns' é não-fatal fora do Windows.
ovpn_client_routing_block() {
    local mode="${1:-default}" routes_csv="${2:-}"
    case "${mode}" in
        full)
            printf 'redirect-gateway def1\n'
            local dns_list dns
            read -ra dns_list <<< "${OVPN_FULL_TUNNEL_DNS}"
            for dns in "${dns_list[@]}"; do
                printf 'dhcp-option DNS %s\n' "${dns}"
            done
            printf 'setenv opt block-outside-dns\n'
            ;;
        split)
            local IFS=','
            local entry
            for entry in ${routes_csv}; do
                entry="${entry#"${entry%%[![:space:]]*}"}"   # tira espaço inicial
                [[ -n "${entry}" ]] && printf 'route %s\n' "${entry}"
            done
            ;;
        *)
            : # default: sem diretivas de rota
            ;;
    esac
}

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
    local name="$1" mode="${2:-default}" routes_csv="${3:-}"
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
        ovpn_client_routing_block "${mode}" "${routes_csv}"
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

# Gera o QR Code do perfil: salva um PNG (escaneável em qualquer tamanho) e
# mostra uma versão compacta no terminal. O perfil tem certs embutidos, então o
# QR é grande; o PNG é o caminho confiável para escanear.
ovpn_client_qr() {
    local name="$1"
    local profile png
    profile="$(ovpn_client_profile_path "${name}")"
    if ! _ovpn_has_qrencode; then
        ovpn_log_warn "qrencode não instalado — QR não gerado. Instale 'qrencode' para usar."
        return 0
    fi
    mkdir -p "${OVPN_HOME_DIR}"
    png="${OVPN_HOME_DIR}/${name}.png"
    if qrencode -o "${png}" -l L < "${profile}" 2>/dev/null; then
        ovpn_log_ok "QR salvo em ${png} (abra a imagem e escaneie no app)."
    fi
    # Versão compacta no terminal (meia altura, correção baixa = menor).
    qrencode -t UTF8 -l L < "${profile}"
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
