#!/usr/bin/env bash
# Módulo controller — orquestradores finos que ligam o menu aos módulos.
# A lógica mora nos módulos; aqui só sequenciamos as chamadas.
# Espera que todos os módulos de domínio já estejam carregados (ver install.sh).

# Instala o hub single-server: PKI, certificados, tls-crypt, config e serviço.
ovpn_action_install_hub() {
    local mode="${1:-ipv4}"
    ovpn_log_step "Instalando o hub OpenVPN (modo ${mode})..."
    ovpn_pki_build_ca
    ovpn_pki_issue_server "${OVPN_SERVER_NAME}"
    ovpn_pki_gen_tls_crypt
    ovpn_server_render "${mode}"
    ovpn_server_enable
    ovpn_log_ok "Hub instalado. Configuração em $(ovpn_server_conf_path)."
}

# Adiciona um cliente: cria o perfil .ovpn e mostra o QR Code.
ovpn_action_add_client() {
    local name="$1"
    if [[ -z "${name}" ]]; then
        ovpn_log_warn "Nome do cliente vazio."
        return 1
    fi
    ovpn_client_create "${name}"
    ovpn_client_qr "${name}"
}

# Mostra o status do servidor.
ovpn_action_status() {
    ovpn_server_status || ovpn_log_warn "Servidor não está ativo."
}

# Laço principal do menu interativo.
ovpn_menu_main() {
    local choice name
    while true; do
        ovpn_ui_banner
        ovpn_ui_menu "Menu Principal" \
            "Instalar hub (servidor)" \
            "Adicionar cliente" \
            "Listar clientes" \
            "Status do servidor"
        printf '0. Sair\n'
        read -r -p "Escolha uma opção: " choice || return 0
        case "${choice}" in
            1) ovpn_action_install_hub ipv4 ;;
            2)
                read -r -p "Nome do cliente: " name || continue
                ovpn_action_add_client "${name}"
                ;;
            3) ovpn_client_list ;;
            4) ovpn_action_status ;;
            0) return 0 ;;
            *) ovpn_log_warn "Opção inválida." ;;
        esac
    done
}
