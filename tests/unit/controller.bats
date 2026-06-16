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
    load_lib firewall
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
