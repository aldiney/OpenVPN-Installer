#!/usr/bin/env bash
# Módulo core — constantes de caminho e utilitários básicos.
# Carregado via `source`; não é executado diretamente.

# Constantes de caminho. Cada uma respeita um valor já definido no ambiente
# (útil para testes em sandbox e para instalações fora do padrão).
: "${OVPN_ETC:=/etc/openvpn}"
: "${OVPN_SERVER_DIR:=${OVPN_ETC}/server}"
: "${OVPN_PKI_DIR:=${OVPN_ETC}/pki}"
: "${OVPN_CLIENTS_DIR:=${OVPN_ETC}/clients}"
: "${OVPN_SYSCTL_FILE:=/etc/sysctl.d/99-openvpn-installer.conf}"

# Define um parâmetro de kernel de forma PERSISTENTE (grava em sysctl.d, para
# sobreviver ao reboot) e o aplica em runtime. Idempotente.
ovpn_sysctl_set() {
    local key="$1" value="$2"
    mkdir -p "$(dirname "${OVPN_SYSCTL_FILE}")"
    if [[ -f "${OVPN_SYSCTL_FILE}" ]]; then
        local tmp
        tmp="$(mktemp)"
        awk -F'[= ]+' -v k="${key}" '$1 != k' "${OVPN_SYSCTL_FILE}" > "${tmp}" \
            && mv "${tmp}" "${OVPN_SYSCTL_FILE}"
    fi
    printf '%s = %s\n' "${key}" "${value}" >> "${OVPN_SYSCTL_FILE}"
    sysctl -w "${key}=${value}" >/dev/null 2>&1 || true
}

# --- Aritmética de IPv4 (para alocar em espaços de qualquer máscara) -------

# IP dotted (a.b.c.d) -> inteiro de 32 bits.
ovpn_ip_to_int() {
    local IFS=. a b c d
    read -r a b c d <<< "$1"
    printf '%s' "$(( (a << 24) + (b << 16) + (c << 8) + d ))"
}

# Inteiro de 32 bits -> IP dotted.
ovpn_int_to_ip() {
    local n="$1"
    printf '%s.%s.%s.%s' "$(( (n >> 24) & 255 ))" "$(( (n >> 16) & 255 ))" "$(( (n >> 8) & 255 ))" "$(( n & 255 ))"
}

# Máscara dotted (255.255.252.0) -> prefix length (22). Conta os bits ligados.
ovpn_netmask_to_plen() {
    local n plen=0
    n="$(ovpn_ip_to_int "$1")"
    while (( n > 0 )); do
        plen=$(( plen + (n & 1) ))
        n=$(( n >> 1 ))
    done
    printf '%s' "${plen}"
}

# Prefix length (22) -> máscara dotted (255.255.252.0).
ovpn_plen_to_netmask() {
    local plen="$1" mask=0
    if (( plen > 0 )); then
        mask=$(( (0xFFFFFFFF << (32 - plen)) & 0xFFFFFFFF ))
    fi
    ovpn_int_to_ip "${mask}"
}

# Aborta com uma mensagem de erro no stderr e código de saída 1.
ovpn_die() {
    printf 'ERRO  %s\n' "$*" >&2
    exit 1
}

# UID atual. Isolado numa função própria para poder ser substituído nos testes.
_ovpn_current_uid() {
    id -u
}

# Exige que o comando esteja sendo executado como root.
ovpn_require_root() {
    if [[ "$(_ovpn_current_uid)" -ne 0 ]]; then
        ovpn_die "Este comando precisa ser executado como root (use sudo)."
    fi
}
