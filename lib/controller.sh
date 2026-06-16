#!/usr/bin/env bash
# Módulo controller — orquestradores finos que ligam o menu aos módulos.
# A lógica mora nos módulos; aqui só sequenciamos as chamadas.
# Espera que todos os módulos de domínio já estejam carregados (ver install.sh).

# Pacotes necessários para o hub funcionar.
ovpn_action_check_deps() {
    ovpn_deps_ensure openvpn qrencode
}

# Garante OVPN_REMOTE_HOST: usa o valor salvo na config; se não houver, pergunta
# UMA vez e salva (não pergunta de novo nas próximas criações de cliente).
_ovpn_ensure_remote_host() {
    if [[ -n "${OVPN_REMOTE_HOST:-}" \
        && "${OVPN_REMOTE_HOST}" != "${OVPN_REMOTE_HOST_PLACEHOLDER:-}" ]]; then
        return 0
    fi
    local saved
    saved="$(ovpn_config_get OVPN_REMOTE_HOST)"
    if [[ -n "${saved}" ]]; then
        export OVPN_REMOTE_HOST="${saved}"
        return 0
    fi
    local host
    read -r -p "IP público ou domínio deste hub (para o 'remote' do cliente): " host || return 1
    export OVPN_REMOTE_HOST="${host}"
    ovpn_config_set OVPN_REMOTE_HOST "${host}"
}

# Pergunta o modo de roteamento do cliente; ecoa "modo<TAB>rotas_csv".
_ovpn_choose_routing() {
    local choice routes
    {
        printf 'Roteamento deste cliente:\n'
        printf '  1) Padrão — só a rede VPN (mantém a internet do cliente)\n'
        printf '  2) Full-tunnel — todo o tráfego + DNS pela VPN\n'
        printf '  3) Rotas específicas (split) — só sub-redes informadas\n'
    } >&2
    read -r -p "Escolha [1-3] (padrão 1): " choice || true
    case "${choice}" in
        2) printf 'full\t' ;;
        3)
            read -r -p "Sub-redes (formato 'rede máscara', separadas por vírgula): " routes || true
            printf 'split\t%s' "${routes}"
            ;;
        *) printf 'default\t' ;;
    esac
}

# Cria (ou regera) o perfil de um cliente de forma interativa: host, modo de
# roteamento e QR opcional.
_ovpn_create_client_interactive() {
    local name="$1"
    _ovpn_ensure_remote_host || return 1
    local sel mode routes
    sel="$(_ovpn_choose_routing)"
    mode="${sel%%$'\t'*}"
    routes="${sel#*$'\t'}"
    ovpn_client_create "${name}" "${mode}" "${routes}"
    if ovpn_ui_confirm "Gerar QR Code do perfil agora?"; then
        ovpn_client_qr "${name}"
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
    ovpn_firewall_open_port "${OVPN_PORT}" udp
    _ovpn_upgrade_write_stamp "${OVPN_SCHEMA_VERSION}"
    ovpn_log_ok "Hub instalado. Configuração em $(ovpn_server_conf_path)."
}

# Adiciona um cliente (pergunta roteamento e QR).
ovpn_action_add_client() {
    local name="$1"
    if [[ -z "${name}" ]]; then
        ovpn_log_warn "Nome do cliente vazio."
        return 1
    fi
    _ovpn_create_client_interactive "${name}"
}

# Regera o perfil .ovpn de um cliente existente (sem reemitir o certificado),
# por exemplo para mudar o modo de roteamento.
ovpn_action_regen_client() {
    local name
    read -r -p "Nome do cliente para regerar o perfil: " name || return 1
    if [[ -z "${name}" ]]; then
        ovpn_log_warn "Nome vazio."
        return 1
    fi
    _ovpn_create_client_interactive "${name}"
}

# Altera e salva o IP/domínio do hub usado nos perfis.
ovpn_action_set_host() {
    local host
    read -r -p "Novo IP/domínio do hub: " host || return 1
    if [[ -z "${host}" ]]; then
        ovpn_log_warn "Valor vazio."
        return 1
    fi
    export OVPN_REMOTE_HOST="${host}"
    ovpn_config_set OVPN_REMOTE_HOST "${host}"
    ovpn_log_ok "Host do hub salvo: ${host}"
}

# Instala o comando 'openvpn-installer' no PATH.
ovpn_action_install_path() {
    ovpn_install_path_command "${OVPN_INSTALL_SH:-${PWD}/install.sh}"
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

# Aplica as migrações de upgrade e reporta achados de rota (sem alterar).
ovpn_action_upgrade() {
    ovpn_upgrade_run
    ovpn_upgrade_report
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
            "Verificar/instalar dependências" \
            "Atualizar/migrar instalação" \
            "Regerar perfil de um cliente" \
            "Alterar host/IP do hub" \
            "Instalar comando no PATH"
        printf '0. Sair\n'
        read -r -p "Escolha uma opção: " choice || return 0
        case "${choice}" in
            1)
                ovpn_wizard_choose_subnet
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
            11) ovpn_action_upgrade ;;
            12) ovpn_action_regen_client ;;
            13) ovpn_action_set_host ;;
            14) ovpn_action_install_path ;;
            0) return 0 ;;
            *) ovpn_log_warn "Opção inválida." ;;
        esac
    done
}
