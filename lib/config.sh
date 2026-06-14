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
