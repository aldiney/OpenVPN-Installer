#!/usr/bin/env bash
# Módulo config — persistência simples de preferências do instalador.
# Guarda pares CHAVE=valor em ${OVPN_ETC}/installer.conf (parse seguro, sem
# `source`). Usado, por exemplo, para lembrar o host/IP do hub. Depende do core.

ovpn_config_path() { printf '%s' "${OVPN_ETC}/installer.conf"; }

# Lê o valor de uma chave (stdout vazio se não existir).
ovpn_config_get() {
    local key="$1" file
    file="$(ovpn_config_path)"
    [[ -f "${file}" ]] || return 0
    awk -F= -v k="${key}" '$1==k { sub(/^[^=]*=/, ""); print; exit }' "${file}"
}

# Carrega no ambiente as preferências persistidas (sub-rede da VPN e hosts do
# hub), para que os módulos as usem sem precisar exportar variáveis na mão. A
# sub-rede também fixa o prefixo /24 derivado, mantendo os dois consistentes.
# Chamado no startup do install.sh.
ovpn_config_apply() {
    local v
    v="$(ovpn_config_get OVPN_SUBNET_V4)"
    if [[ -n "${v}" ]]; then
        export OVPN_SUBNET_V4="${v}"
        export OVPN_VPN_PREFIX_V4="${v%.*}"
    fi
    v="$(ovpn_config_get OVPN_NETMASK_V4)"
    if [[ -n "${v}" ]]; then export OVPN_NETMASK_V4="${v}"; fi
    v="$(ovpn_config_get OVPN_REMOTE_HOST)"
    if [[ -n "${v}" ]]; then export OVPN_REMOTE_HOST="${v}"; fi
    v="$(ovpn_config_get OVPN_REMOTE_HOST_2)"
    if [[ -n "${v}" ]]; then export OVPN_REMOTE_HOST_2="${v}"; fi
    # Chaves do roteamento dinâmico / IP estável global (passagem direta).
    local k
    for k in OVPN_DYNROUTING OVPN_DOMAIN_ID OVPN_HUB_ID OVPN_HUB_ROLE \
             OVPN_TRANSPORT_NET_V4 OVPN_OSPF_AREA OVPN_LINK_PORT; do
        v="$(ovpn_config_get "${k}")"
        if [[ -n "${v}" ]]; then export "${k}=${v}"; fi
    done
    return 0
}

# Define/atualiza uma chave (idempotente, sem duplicar).
ovpn_config_set() {
    local key="$1" value="$2" file tmp
    file="$(ovpn_config_path)"
    mkdir -p "${OVPN_ETC}"
    touch "${file}"
    tmp="$(mktemp)"
    awk -F= -v k="${key}" '$1 != k' "${file}" > "${tmp}"
    printf '%s=%s\n' "${key}" "${value}" >> "${tmp}"
    mv "${tmp}" "${file}"
}
