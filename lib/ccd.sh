#!/usr/bin/env bash
# Módulo ccd — IP fixo por cliente via client-config-dir + ifconfig-push.
# Cada cliente recebe um endereço estável e previsível dentro da VPN.
# Depende do módulo core.

: "${OVPN_NETMASK_V4:=255.255.255.0}"
: "${OVPN_SUBNET_V4:=10.8.0.0}"

# Prefixo /24 (3 primeiros octetos) de uma sub-rede x.x.x.0.
ovpn_vpn_prefix() { printf '%s' "${1%.*}"; }

# Prefixo da rede da VPN, derivado da sub-rede (mantém os dois consistentes;
# os hosts vão de .2 a .254; .1 é o servidor).
: "${OVPN_VPN_PREFIX_V4:=$(ovpn_vpn_prefix "${OVPN_SUBNET_V4}")}"
# DNS empurrado aos clientes full-tunnel (para resolverem nomes pela VPN).
: "${OVPN_FULL_TUNNEL_DNS:=1.1.1.1 8.8.8.8}"

# Diretório de configurações por cliente (mesmo usado no server.conf).
ovpn_ccd_dir() {
    printf '%s' "${OVPN_SERVER_DIR}/ccd"
}

# Retorna o próximo IP livre no espaço da VPN (derivado de OVPN_SUBNET_V4 +
# OVPN_NETMASK_V4, de qualquer máscara — /24, /22, ...). A faixa vai de rede+2
# (.0 = rede, .1 = servidor) até broadcast-1. Falha se o espaço encher. Lê os
# IPs já atribuídos direto dos arquivos do ccd (campo do ifconfig-push).
ovpn_ccd_next_free_ip() {
    local dir ip i used mask_int network bcast first last
    dir="$(ovpn_ccd_dir)"
    mkdir -p "${dir}"
    # Lista dos IPs já usados, separados por ESPAÇO (o $() junta com quebra de
    # linha; o tr normaliza para o teste de pertencimento abaixo funcionar).
    used=" $(awk '/ifconfig-push/ {print $2}' "${dir}"/* 2>/dev/null | tr '\n' ' ') "
    mask_int="$(ovpn_ip_to_int "${OVPN_NETMASK_V4}")"
    network=$(( $(ovpn_ip_to_int "${OVPN_SUBNET_V4}") & mask_int ))
    bcast=$(( network | (~mask_int & 0xFFFFFFFF) ))
    first=$(( network + 2 ))
    last=$(( bcast - 1 ))
    for (( i = first; i <= last; i++ )); do
        ip="$(ovpn_int_to_ip "${i}")"
        case "${used}" in
            *" ${ip} "*) ;;   # já em uso — pula
            *) printf '%s' "${ip}"; return 0 ;;
        esac
    done
    return 1
}

# Garante o IP fixo de um cliente. Idempotente: se já houver, mantém e devolve
# o mesmo IP. Stdout = IP atribuído.
ovpn_ccd_assign() {
    local name="$1" dir file ip
    dir="$(ovpn_ccd_dir)"
    mkdir -p "${dir}"
    file="${dir}/${name}"

    if [[ -f "${file}" ]]; then
        awk '/ifconfig-push/ {print $2}' "${file}"
        return 0
    fi

    ip="$(ovpn_ccd_next_free_ip)" || ovpn_die "Sem IPs livres no espaço ${OVPN_SUBNET_V4}/$(ovpn_netmask_to_plen "${OVPN_NETMASK_V4}")."
    printf 'ifconfig-push %s %s\n' "${ip}" "${OVPN_NETMASK_V4}" > "${file}"
    printf '%s' "${ip}"
}

# Re-endereça os IPs fixos do ccd de um espaço antigo para um novo, PRESERVANDO
# o deslocamento do host (ex.: 10.8.0.5/24 -> 10.80.0.5/22). Faz backup do ccd
# em <dir>.pre-readdress, preserva as demais linhas (iroute/push) e é idempotente
# (pula quem já está no novo espaço). Usado ao migrar para o espaço estável /22.
ovpn_ccd_readdress() {
    local old_space="$1" old_mask="$2" new_space="$3" new_mask="$4"
    local dir f ip ip_int old_net new_net new_mask_int off newip tmp
    dir="$(ovpn_ccd_dir)"
    [[ -d "${dir}" ]] || return 0
    old_net=$(( $(ovpn_ip_to_int "${old_space}") & $(ovpn_ip_to_int "${old_mask}") ))
    new_mask_int="$(ovpn_ip_to_int "${new_mask}")"
    new_net=$(( $(ovpn_ip_to_int "${new_space}") & new_mask_int ))

    rm -rf "${dir}.pre-readdress"
    cp -a "${dir}" "${dir}.pre-readdress"

    for f in "${dir}"/*; do
        [[ -e "${f}" ]] || continue
        ip="$(awk '/ifconfig-push/{print $2; exit}' "${f}")"
        [[ -n "${ip}" ]] || continue
        ip_int="$(ovpn_ip_to_int "${ip}")"
        if (( (ip_int & new_mask_int) == new_net )); then continue; fi   # já no novo espaço
        off=$(( ip_int - old_net ))
        newip="$(ovpn_int_to_ip $(( new_net + off )))"
        tmp="$(mktemp)"
        awk -v nip="${newip}" -v nm="${new_mask}" \
            '/ifconfig-push/ { print "ifconfig-push " nip " " nm; next } { print }' "${f}" > "${tmp}" \
            && mv "${tmp}" "${f}"
    done
}

# Marca a sub-rede que fica ATRÁS de um peer (um hub conectado como cliente),
# via iroute no ccd — o OpenVPN passa a rotear essa sub-rede para a conexão dele
# (base do enlace site-to-site por cliente+iroute). Idempotente.
ovpn_ccd_set_iroute() {
    local name="$1" subnet="$2" netmask="${3:-255.255.255.0}"
    local file
    file="$(ovpn_ccd_dir)/${name}"
    mkdir -p "$(ovpn_ccd_dir)"
    if awk -v p="iroute ${subnet} ${netmask}" 'index($0, p) { f = 1 } END { exit !f }' "${file}" 2>/dev/null; then
        return 0
    fi
    printf 'iroute %s %s\n' "${subnet}" "${netmask}" >> "${file}"
}

# Marca um cliente como "full-tunnel": empurra a rota padrão e DNS apenas para
# ele (via ccd). Assim, só os clientes marcados saem pela internet do hub; os
# demais ficam em split-tunnel (usam a própria internet). Idempotente.
# Requer a saída-internet (NAT) ativa no hub — ver módulo gateway.
ovpn_ccd_set_full_tunnel() {
    local name="$1"
    local file
    file="$(ovpn_ccd_dir)/${name}"
    mkdir -p "$(ovpn_ccd_dir)"
    if awk 'index($0, "redirect-gateway") { f = 1 } END { exit !f }' "${file}" 2>/dev/null; then
        return 0
    fi
    printf 'push "redirect-gateway def1"\n' >> "${file}"
    local dns_list dns
    read -ra dns_list <<< "${OVPN_FULL_TUNNEL_DNS}"
    for dns in "${dns_list[@]}"; do
        printf 'push "dhcp-option DNS %s"\n' "${dns}" >> "${file}"
    done
}

# Remove a marcação de full-tunnel de um cliente (volta a split-tunnel).
ovpn_ccd_unset_full_tunnel() {
    local name="$1"
    local file
    file="$(ovpn_ccd_dir)/${name}"
    [[ -f "${file}" ]] || return 0
    local tmp
    tmp="$(mktemp)"
    awk '!index($0, "redirect-gateway") && !index($0, "dhcp-option DNS")' "${file}" > "${tmp}" \
        && mv "${tmp}" "${file}"
}
