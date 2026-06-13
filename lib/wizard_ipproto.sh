#!/usr/bin/env bash
# Módulo wizard_ipproto — traduz a escolha de protocolo IP em fragmentos de
# configuração do servidor. Nesta versão, o caminho IPv4. IPv6/dual-stack
# entram em uma fatia futura. Depende do módulo core.

: "${OVPN_PROTO:=udp}"
: "${OVPN_PORT:=1194}"
: "${OVPN_SUBNET_V4:=10.8.0.0}"
: "${OVPN_NETMASK_V4:=255.255.255.0}"

# Emite as linhas de configuração do modo IPv4.
ovpn_wizard_ipproto_ipv4() {
    printf 'proto %s\n' "${OVPN_PROTO}"
    printf 'port %s\n' "${OVPN_PORT}"
    printf 'server %s %s\n' "${OVPN_SUBNET_V4}" "${OVPN_NETMASK_V4}"
}

# Despacha conforme o modo escolhido.
ovpn_wizard_ipproto() {
    local mode="${1:-ipv4}"
    case "${mode}" in
        ipv4)
            ovpn_wizard_ipproto_ipv4
            ;;
        *)
            ovpn_die "Modo IP não suportado nesta versão: ${mode}"
            ;;
    esac
}
