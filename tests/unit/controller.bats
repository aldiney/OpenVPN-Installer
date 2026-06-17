#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
    load_lib log
    load_lib ui
    load_lib config
    load_lib pki
    load_lib wizard_ipproto
    load_lib server_config
    load_lib ccd
    load_lib client_profile
    load_lib firewall
    load_lib hub_sync
    load_lib dualhub
    load_lib upgrade
    load_lib controller
}

@test "ovpn_menu_main: mostra o menu e a opção 0 encerra" {
    run ovpn_menu_main <<< "0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Instalar"* ]]
    [[ "$output" == *"cliente"* ]]
    [[ "$output" == *"Atualizar"* ]]
}

@test "ovpn_menu_main: opção 15 abre o submenu Dois hubs" {
    run ovpn_menu_main <<< $'15\n0\n0'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dois hubs (ativo-ativo)"* ]]
    [[ "$output" == *"Exportar CA mestra"* ]]
    [[ "$output" == *"Registrar hub par"* ]]
}

@test "ovpn_action_dualhub_link_forwarding: confirma (s) e ativa o encaminhamento" {
    _ovpn_firewall_backend() { printf 'ufw'; }
    run ovpn_action_dualhub_link_forwarding <<< $'tun1\ns'
    [ "$status" -eq 0 ]
    run stub_calls ufw
    [[ "$output" == *"route allow in on tun0 out on tun1"* ]]
}

@test "ovpn_action_dualhub_link_forwarding: recusa (n) não toca o firewall" {
    _ovpn_firewall_backend() { printf 'ufw'; }
    run ovpn_action_dualhub_link_forwarding <<< $'tun1\nn'
    [ "$status" -eq 0 ]
    run stub_calls ufw
    [ -z "$output" ]
}

@test "ovpn_menu_dualhub: mostra a opção de IP estável global (OSPF)" {
    run ovpn_menu_main <<< $'15\n0\n0'
    [ "$status" -eq 0 ]
    [[ "$output" == *"IP estável global"* ]]
}

@test "ovpn_action_enable_dynrouting: confirma (s) persiste e ativa (core)" {
    export OVPN_HUB_ROLE=core
    ovpn_frr_ensure()             { :; }
    ovpn_frr_render_daemons()     { :; }
    ovpn_frr_render_ospf()        { :; }
    ovpn_frr_enable()             { :; }
    ovpn_reconcile_install_units() { :; }
    ovpn_link_render_core()       { :; }
    ovpn_firewall_open_port()     { :; }
    run ovpn_action_enable_dynrouting <<< "s"
    [ "$status" -eq 0 ]
    [ "$(ovpn_config_get OVPN_DYNROUTING)" = "on" ]
    run stub_calls systemctl
    [[ "$output" == *"enable --now openvpn-server@link"* ]]
    [[ "$output" == *"restart openvpn-server@server"* ]]
}

@test "ovpn_action_enable_dynrouting: recusa (n) não ativa" {
    run ovpn_action_enable_dynrouting <<< "n"
    [ "$status" -eq 0 ]
    [ -z "$(ovpn_config_get OVPN_DYNROUTING)" ]
}

@test "ovpn_action_dualhub_announce: aplica a rota e reinicia o servidor" {
    mkdir -p "${OVPN_SERVER_DIR}"
    printf 'dev tun\n' > "$(ovpn_server_conf_path)"
    run ovpn_action_dualhub_announce <<< $'10.8.0.0\n\ns'
    [ "$status" -eq 0 ]
    grep -q 'push "route 10.8.0.0' "$(ovpn_server_conf_path)"
    run stub_calls systemctl
    [[ "$output" == *"restart"* ]]
    [[ "$output" == *"openvpn-server@server"* ]]
}

@test "ovpn_action_set_host_2: define e persiste o 2º hub" {
    run ovpn_action_set_host_2 <<< "hubB.exemplo.com"
    [ "$status" -eq 0 ]
    [ "$(ovpn_config_get OVPN_REMOTE_HOST_2)" = "hubB.exemplo.com" ]
}

@test "ovpn_action_set_host_2: valor vazio remove o 2º hub" {
    ovpn_config_set OVPN_REMOTE_HOST_2 hubB.exemplo.com
    run ovpn_action_set_host_2 <<< ""
    [ "$status" -eq 0 ]
    [ -z "$(ovpn_config_get OVPN_REMOTE_HOST_2)" ]
}

@test "_ovpn_load_remote_host_2: carrega o 2º hub salvo para o ambiente" {
    ovpn_config_set OVPN_REMOTE_HOST_2 hubB.exemplo.com
    unset OVPN_REMOTE_HOST_2
    _ovpn_load_remote_host_2
    [ "${OVPN_REMOTE_HOST_2}" = "hubB.exemplo.com" ]
}
