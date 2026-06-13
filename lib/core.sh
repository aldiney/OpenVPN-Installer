#!/usr/bin/env bash
# Módulo core — constantes de caminho e utilitários básicos.
# Carregado via `source`; não é executado diretamente.

# Constantes de caminho. Cada uma respeita um valor já definido no ambiente
# (útil para testes em sandbox e para instalações fora do padrão).
: "${OVPN_ETC:=/etc/openvpn}"
: "${OVPN_SERVER_DIR:=${OVPN_ETC}/server}"
: "${OVPN_PKI_DIR:=${OVPN_ETC}/pki}"
: "${OVPN_CLIENTS_DIR:=${OVPN_ETC}/clients}"

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
