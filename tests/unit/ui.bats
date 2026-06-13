#!/usr/bin/env bats

load ../test_helper/common

setup() {
    common_setup
    load_lib ui
}

@test "ovpn_ui_confirm: 's' confirma (status 0)" {
    run ovpn_ui_confirm "Prosseguir?" <<< "s"
    [ "$status" -eq 0 ]
}

@test "ovpn_ui_confirm: resposta vazia recusa (padrão é não)" {
    run ovpn_ui_confirm "Prosseguir?" <<< ""
    [ "$status" -eq 1 ]
}

@test "ovpn_ui_confirm: 'n' recusa" {
    run ovpn_ui_confirm "Prosseguir?" <<< "n"
    [ "$status" -eq 1 ]
}

@test "ovpn_ui_banner: mostra o nome do projeto" {
    run ovpn_ui_banner
    [ "$status" -eq 0 ]
    [[ "$output" == *"OpenVPN-Installer"* ]]
}

@test "ovpn_ui_menu: mostra o título e numera as opções" {
    run ovpn_ui_menu "Menu Principal" "Instalar hub" "Adicionar cliente"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Menu Principal"* ]]
    [[ "$output" == *"1. Instalar hub"* ]]
    [[ "$output" == *"2. Adicionar cliente"* ]]
}
