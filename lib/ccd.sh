#!/usr/bin/env bash
# Módulo ccd — IP fixo por cliente via client-config-dir + ifconfig-push.
# Cada cliente recebe um endereço estável e previsível dentro da VPN.
# Depende do módulo core.

: "${OVPN_NETMASK_V4:=255.255.255.0}"
# Prefixo /24 da rede da VPN (os hosts vão de .2 a .254; .1 é o servidor).
: "${OVPN_VPN_PREFIX_V4:=10.8.0}"

# Diretório de configurações por cliente (mesmo usado no server.conf).
ovpn_ccd_dir() {
    printf '%s' "${OVPN_SERVER_DIR}/ccd"
}

# Retorna o próximo IP livre na faixa (.2 .. .254). Falha se a faixa encher.
# Lê os IPs já atribuídos direto dos arquivos do ccd (campo do ifconfig-push),
# sem depender de busca recursiva no sistema de arquivos.
ovpn_ccd_next_free_ip() {
    local dir ip i used
    dir="$(ovpn_ccd_dir)"
    mkdir -p "${dir}"
    used=" $(awk '/ifconfig-push/ {print $2}' "${dir}"/* 2>/dev/null) "
    for i in $(seq 2 254); do
        ip="${OVPN_VPN_PREFIX_V4}.${i}"
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

    ip="$(ovpn_ccd_next_free_ip)" || ovpn_die "Sem IPs livres na faixa ${OVPN_VPN_PREFIX_V4}.0/24."
    printf 'ifconfig-push %s %s\n' "${ip}" "${OVPN_NETMASK_V4}" > "${file}"
    printf '%s' "${ip}"
}
