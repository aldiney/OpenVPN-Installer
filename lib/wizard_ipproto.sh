#!/usr/bin/env bash
# Módulo wizard_ipproto — traduz a escolha de protocolo IP em fragmentos de
# configuração do servidor. Suporta IPv4, IPv6 e dual-stack. Depende do core.

: "${OVPN_PROTO:=udp}"
: "${OVPN_PORT:=1194}"
: "${OVPN_SUBNET_V4:=10.8.0.0}"
: "${OVPN_NETMASK_V4:=255.255.255.0}"
: "${OVPN_SUBNET_V6:=fd00:0:0:8::/64}"

# Linhas comuns ao IPv6 (sub-rede interna + rota anunciada aos clientes).
ovpn_wizard_ipproto_v6_lines() {
    printf 'server-ipv6 %s\n' "${OVPN_SUBNET_V6}"
    printf 'push "route-ipv6 %s"\n' "${OVPN_SUBNET_V6}"
}

# Linha do server IPv4.
ovpn_wizard_ipproto_v4_line() {
    printf 'server %s %s\n' "${OVPN_SUBNET_V4}" "${OVPN_NETMASK_V4}"
}

# Emite os fragmentos de configuração conforme o modo: ipv4, ipv6 ou dual.
ovpn_wizard_ipproto() {
    local mode="${1:-ipv4}"
    case "${mode}" in
        ipv4)
            printf 'proto %s\n' "${OVPN_PROTO}"
            printf 'port %s\n' "${OVPN_PORT}"
            ovpn_wizard_ipproto_v4_line
            ;;
        ipv6)
            printf 'proto %s6\n' "${OVPN_PROTO}"
            printf 'port %s\n' "${OVPN_PORT}"
            ovpn_wizard_ipproto_v6_lines
            ;;
        dual)
            printf 'proto %s6\n' "${OVPN_PROTO}"
            printf 'port %s\n' "${OVPN_PORT}"
            ovpn_wizard_ipproto_v4_line
            ovpn_wizard_ipproto_v6_lines
            ;;
        *)
            ovpn_die "Modo IP não suportado: ${mode}"
            ;;
    esac
}

# Pergunta a rede da VPN (/24) e persiste. Mantém o atual se a entrada for
# vazia ou inválida. Também fixa o prefixo derivado, deixando os dois
# consistentes (a sub-rede vira o `server`; o prefixo, os IPs fixos do ccd).
# Permite que o hub B use uma sub-rede distinta sem exportar variáveis na mão.
ovpn_wizard_choose_subnet() {
    local input
    read -r -p "Rede da VPN (/24, formato x.x.x.0) [${OVPN_SUBNET_V4}]: " input || true
    [[ -n "${input}" ]] || return 0
    if [[ ! "${input}" =~ ^([0-9]{1,3}\.){3}0$ ]]; then
        ovpn_log_warn "Sub-rede inválida (use o formato x.x.x.0); mantendo ${OVPN_SUBNET_V4}."
        return 0
    fi
    export OVPN_SUBNET_V4="${input}"
    export OVPN_VPN_PREFIX_V4="${input%.*}"
    ovpn_config_set OVPN_SUBNET_V4 "${input}"
    ovpn_log_ok "Rede da VPN definida: ${OVPN_SUBNET_V4}/24"
}

# Pergunta ao operador o modo de IP e devolve 'ipv4', 'ipv6' ou 'dual'.
ovpn_wizard_choose_mode() {
    local choice
    read -r -p "Modo de IP [1=IPv4, 2=IPv6, 3=dual-stack] (padrão 1): " choice || true
    case "${choice}" in
        2) printf 'ipv6' ;;
        3) printf 'dual' ;;
        *) printf 'ipv4' ;;
    esac
}
