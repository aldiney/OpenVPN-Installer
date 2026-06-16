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

# Carrega o 2º hub salvo (dual-hub) para o ambiente, sem perguntar. Assim, os
# perfis de cliente listam os dois hubs (failover) logo após defini-lo, mesmo
# sem reiniciar o instalador.
_ovpn_load_remote_host_2() {
    if [[ -n "${OVPN_REMOTE_HOST_2:-}" ]]; then return 0; fi
    local saved
    saved="$(ovpn_config_get OVPN_REMOTE_HOST_2)"
    if [[ -n "${saved}" ]]; then export OVPN_REMOTE_HOST_2="${saved}"; fi
    return 0
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
    _ovpn_load_remote_host_2
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

# Define e salva o IP/domínio do SEGUNDO hub (dual-hub ativo-ativo). Os perfis
# de cliente passam a listar os dois hubs, com failover (remote-random). Valor
# vazio remove o 2º hub (os perfis voltam a um hub só).
ovpn_action_set_host_2() {
    local host
    read -r -p "IP/domínio do 2º hub (vazio = remover): " host || return 1
    export OVPN_REMOTE_HOST_2="${host}"
    ovpn_config_set OVPN_REMOTE_HOST_2 "${host}"
    if [[ -z "${host}" ]]; then
        ovpn_log_ok "2º hub removido (perfis voltam a um hub só)."
    else
        ovpn_log_ok "2º hub salvo: ${host} (novos perfis listarão os dois hubs)."
    fi
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

# --- Dois hubs (ativo-ativo) ---------------------------------------------
# Cada ação confirma antes de tocar o sistema (CLAUDE.md).

# Exporta a CA MESTRA (inclui a chave privada) para o hub par emitir certs.
ovpn_action_hub_export_master() {
    local out
    read -r -p "Arquivo de saída do bundle MESTRA (ex.: /root/ca-mestra.tar.gz): " out || return 1
    [[ -n "${out}" ]] || { ovpn_log_warn "Caminho vazio."; return 1; }
    ovpn_log_warn "O bundle MESTRA contém a CHAVE PRIVADA da CA — compartilhe só com um hub plenamente confiável."
    ovpn_ui_confirm "Exportar a CA mestra para ${out}?" || return 0
    ovpn_hub_export_master "${out}"
}

# Exporta só a identidade pública da CA (ca.crt + tls-crypt), sem a chave.
ovpn_action_hub_export() {
    local out
    read -r -p "Arquivo de saída do bundle público (ex.: /root/ca.tar.gz): " out || return 1
    [[ -n "${out}" ]] || { ovpn_log_warn "Caminho vazio."; return 1; }
    ovpn_ui_confirm "Exportar a identidade pública da CA para ${out}?" || return 0
    ovpn_hub_export "${out}"
}

# Importa a CA de um bundle (substitui a CA local).
ovpn_action_hub_import() {
    local in
    read -r -p "Arquivo do bundle a importar: " in || return 1
    [[ -f "${in}" ]] || { ovpn_log_warn "Arquivo não encontrado: ${in}"; return 1; }
    ovpn_log_warn "Importar substitui a CA local pela do bundle."
    ovpn_ui_confirm "Importar a CA de ${in}?" || return 0
    ovpn_hub_import "${in}"
}

# Registra o hub par (no hub A): emite o perfil do enlace, marca iroute e rota.
ovpn_action_dualhub_register_peer() {
    local name subnet mask
    read -r -p "Nome do hub par (ex.: hub-b): " name || return 1
    read -r -p "Sub-rede do hub par (ex.: 10.8.1.0): " subnet || return 1
    read -r -p "Máscara [255.255.255.0]: " mask || true
    [[ -n "${mask}" ]] || mask="255.255.255.0"
    [[ -n "${name}" && -n "${subnet}" ]] || { ovpn_log_warn "Informe nome e sub-rede."; return 1; }
    ovpn_ui_confirm "Registrar o peer ${name} (sub-rede ${subnet})?" || return 0
    ovpn_dualhub_register_peer "${name}" "${subnet}" "${mask}"
}

# Anuncia aos clientes deste hub a sub-rede do hub par (push-only; usado no hub
# que CONECTA — a rota de kernel para o par já vem pelo enlace).
ovpn_action_dualhub_announce() {
    local subnet mask
    read -r -p "Sub-rede do hub par a anunciar (ex.: 10.8.0.0): " subnet || return 1
    read -r -p "Máscara [255.255.255.0]: " mask || true
    [[ -n "${mask}" ]] || mask="255.255.255.0"
    [[ -n "${subnet}" ]] || { ovpn_log_warn "Informe a sub-rede."; return 1; }
    ovpn_ui_confirm "Anunciar ${subnet} (sub-rede do hub par) aos clientes?" || return 0
    ovpn_dualhub_announce "${subnet}" "${mask}"
}

# Ativa o encaminhamento do tráfego inter-hub (no hub que conecta como cliente).
ovpn_action_dualhub_link_forwarding() {
    local link
    read -r -p "Interface do enlace (ex.: tun1): " link || return 1
    [[ -n "${link}" ]] || { ovpn_log_warn "Informe a interface."; return 1; }
    ovpn_ui_confirm "Ativar o encaminhamento inter-hub via ${link} (sem NAT)?" || return 0
    ovpn_dualhub_link_forwarding "${link}"
}

# Submenu do dual-hub ativo-ativo.
ovpn_menu_dualhub() {
    local choice
    while true; do
        ovpn_ui_menu "Dois hubs (ativo-ativo)" \
            "Exportar CA mestra (inclui a chave; leve ao hub par)" \
            "Exportar identidade pública da CA (sem a chave)" \
            "Importar CA de um bundle" \
            "Registrar hub par (enlace + iroute) — no hub A" \
            "Anunciar a sub-rede do hub par aos clientes — no hub B" \
            "Ativar encaminhamento do enlace (no hub que conecta)" \
            "Definir/alterar o 2º hub dos clientes (failover)"
        printf '0. Voltar\n'
        read -r -p "Escolha uma opção: " choice || return 0
        case "${choice}" in
            1) ovpn_action_hub_export_master ;;
            2) ovpn_action_hub_export ;;
            3) ovpn_action_hub_import ;;
            4) ovpn_action_dualhub_register_peer ;;
            5) ovpn_action_dualhub_announce ;;
            6) ovpn_action_dualhub_link_forwarding ;;
            7) ovpn_action_set_host_2 ;;
            0) return 0 ;;
            *) ovpn_log_warn "Opção inválida." ;;
        esac
    done
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
            "Instalar comando no PATH" \
            "Dois hubs (ativo-ativo)"
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
            15) ovpn_menu_dualhub ;;
            0) return 0 ;;
            *) ovpn_log_warn "Opção inválida." ;;
        esac
    done
}
