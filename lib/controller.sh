#!/usr/bin/env bash
# Módulo controller — orquestradores finos que ligam o menu aos módulos.
# A lógica mora nos módulos; aqui só sequenciamos as chamadas.
# Espera que todos os módulos de domínio já estejam carregados (ver install.sh).

# Pacotes necessários para o hub funcionar.
ovpn_action_check_deps() {
    ovpn_deps_ensure openvpn qrencode
}

# Garante que OVPN_REMOTE_HOST esteja definido; pergunta se ainda é o placeholder.
_ovpn_ensure_remote_host() {
    if [[ -z "${OVPN_REMOTE_HOST:-}" \
        || "${OVPN_REMOTE_HOST}" == "${OVPN_REMOTE_HOST_PLACEHOLDER:-}" ]]; then
        local host
        read -r -p "IP público ou domínio deste hub (para o 'remote' do cliente): " host \
            || return 1
        export OVPN_REMOTE_HOST="${host}"
    fi
}

# Instala o hub single-server: dependências, PKI, certificados, tls-crypt,
# configuração e serviço.
ovpn_action_install_hub() {
    local mode="${1:-ipv4}"
    ovpn_log_step "Instalando o hub OpenVPN (modo ${mode})..."
    ovpn_action_check_deps || return 1
    ovpn_pki_build_ca
    ovpn_pki_issue_server "${OVPN_SERVER_NAME}"
    ovpn_pki_gen_tls_crypt
    ovpn_server_render "${mode}"
    ovpn_server_apply_forwarding "${mode}"
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
    _ovpn_ensure_remote_host || return 1
    ovpn_client_create "${name}"
    ovpn_client_qr "${name}"
}

# Ativa a saída para a internet por uma interface WAN.
ovpn_action_gateway_enable() {
    local wan
    read -r -p "Interface WAN (ex.: eth0): " wan || return 1
    ovpn_gateway_enable "${wan}"
}

# Desativa a saída para a internet.
ovpn_action_gateway_disable() {
    local wan
    read -r -p "Interface WAN usada (ex.: eth0): " wan || return 1
    ovpn_gateway_disable "${wan}"
}

# Adiciona um cliente MikroTik (perfil .ovpn compatível + script .rsc).
ovpn_action_add_mikrotik() {
    local name="$1"
    if [[ -z "${name}" ]]; then
        ovpn_log_warn "Nome do cliente vazio."
        return 1
    fi
    _ovpn_ensure_remote_host || return 1
    ovpn_mikrotik_create "${name}"
}

# Revoga o acesso de um cliente.
ovpn_action_revoke_client() {
    local name
    read -r -p "Nome do cliente a revogar: " name || return 1
    ovpn_client_revoke "${name}"
}

# Desinstala o hub, perguntando se a PKI deve ser preservada.
ovpn_action_uninstall() {
    if ! ovpn_ui_confirm "Tem certeza que deseja desinstalar o hub?"; then
        return 0
    fi
    local pki_mode="keep"
    if ovpn_ui_confirm "Remover também a PKI (certificados)?"; then
        pki_mode="purge"
    fi
    ovpn_uninstall "${pki_mode}"
}

# Mostra o status do servidor e os clientes cadastrados.
ovpn_action_status() {
    ovpn_server_status || ovpn_log_warn "Servidor não está ativo."
    printf 'Clientes:\n'
    ovpn_client_list
}

# Laço principal do menu interativo.
ovpn_menu_main() {
    local choice name mode
    while true; do
        ovpn_ui_banner
        ovpn_ui_menu "Menu Principal" \
            "Instalar hub (servidor)" \
            "Adicionar cliente" \
            "Listar clientes" \
            "Status do servidor" \
            "Ativar saída para a internet" \
            "Desativar saída para a internet" \
            "Adicionar cliente MikroTik" \
            "Revogar cliente" \
            "Desinstalar o hub" \
            "Verificar/instalar dependências"
        printf '0. Sair\n'
        read -r -p "Escolha uma opção: " choice || return 0
        case "${choice}" in
            1)
                mode="$(ovpn_wizard_choose_mode)"
                ovpn_action_install_hub "${mode}"
                ;;
            2)
                read -r -p "Nome do cliente: " name || continue
                ovpn_action_add_client "${name}"
                ;;
            3) ovpn_client_list ;;
            4) ovpn_action_status ;;
            5) ovpn_action_gateway_enable ;;
            6) ovpn_action_gateway_disable ;;
            7)
                read -r -p "Nome do cliente MikroTik: " name || continue
                ovpn_action_add_mikrotik "${name}"
                ;;
            8) ovpn_action_revoke_client ;;
            9) ovpn_action_uninstall ;;
            10) ovpn_action_check_deps ;;
            0) return 0 ;;
            *) ovpn_log_warn "Opção inválida." ;;
        esac
    done
}
