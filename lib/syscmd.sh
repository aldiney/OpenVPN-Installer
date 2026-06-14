#!/usr/bin/env bash
# Módulo syscmd — integra o instalador ao sistema (comando no PATH).
# Cria um symlink para o install.sh, permitindo chamar o menu de qualquer lugar.
# Depende dos módulos core e log.

: "${OVPN_BIN_DIR:=/usr/local/bin}"
: "${OVPN_CMD_NAME:=openvpn-installer}"

# Instala o comando no PATH apontando para o install.sh informado.
ovpn_install_path_command() {
    local target="$1"
    [[ -f "${target}" ]] || ovpn_die "install.sh não encontrado: ${target}"
    mkdir -p "${OVPN_BIN_DIR}"
    ln -sf "${target}" "${OVPN_BIN_DIR}/${OVPN_CMD_NAME}"
    chmod +x "${target}" 2>/dev/null || true
    ovpn_log_ok "Comando '${OVPN_CMD_NAME}' instalado em ${OVPN_BIN_DIR}. Rode 'sudo ${OVPN_CMD_NAME}' de qualquer lugar."
}
