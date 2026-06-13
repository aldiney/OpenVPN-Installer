#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
    load_lib log
    load_lib ui
    load_lib pki
    load_lib wizard_ipproto
    load_lib server_config
    load_lib ccd
    load_lib controller
}

@test "ovpn_menu_main: mostra o menu e a opção 0 encerra" {
    run ovpn_menu_main <<< "0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Instalar"* ]]
}
