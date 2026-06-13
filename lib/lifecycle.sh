#!/usr/bin/env bash
# Módulo lifecycle — operações de ciclo de vida do servidor (desinstalação).
# Depende dos módulos core, log, server_config e pki.

# Desinstala o hub: para e desabilita o serviço, remove a configuração e o ccd.
# Por padrão PRESERVA a PKI (passe "purge" para remover também a PKI).
ovpn_uninstall() {
    local pki_mode="${1:-keep}"

    systemctl disable --now "openvpn-server@${OVPN_SERVER_NAME}" 2>/dev/null || true

    rm -f "$(ovpn_server_conf_path)"
    rm -rf "$(ovpn_server_ccd_dir)"

    if [[ "${pki_mode}" == "purge" ]]; then
        rm -rf "${OVPN_PKI_DIR}"
        ovpn_log_ok "Desinstalação concluída. PKI removida."
    else
        ovpn_log_ok "Desinstalação concluída. PKI preservada em ${OVPN_PKI_DIR}."
    fi
}
