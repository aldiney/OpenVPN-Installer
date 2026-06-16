#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
    load_lib log
    load_lib config
    load_lib wizard_ipproto
}

@test "ovpn_wizard_ipproto ipv4: emite proto, port e a rede IPv4" {
    run ovpn_wizard_ipproto ipv4
    [ "$status" -eq 0 ]
    [[ "$output" == *"proto udp"* ]]
    [[ "$output" == *"port 1194"* ]]
    [[ "$output" == *"server 10.8.0.0 255.255.255.0"* ]]
}

@test "ovpn_wizard_ipproto ipv6: emite proto udp6 e server-ipv6 (sem server IPv4)" {
    run ovpn_wizard_ipproto ipv6
    [ "$status" -eq 0 ]
    [[ "$output" == *"proto udp6"* ]]
    [[ "$output" == *"server-ipv6 "* ]]
    [[ "$output" != *"server 10.8.0.0"* ]]
}

@test "ovpn_wizard_ipproto dual: emite proto udp6, server IPv4 e server-ipv6 + push route-ipv6" {
    run ovpn_wizard_ipproto dual
    [ "$status" -eq 0 ]
    [[ "$output" == *"proto udp6"* ]]
    [[ "$output" == *"server 10.8.0.0 255.255.255.0"* ]]
    [[ "$output" == *"server-ipv6 "* ]]
    [[ "$output" == *"route-ipv6"* ]]
}

@test "ovpn_wizard_choose_mode: mapeia a escolha numérica para o modo" {
    run ovpn_wizard_choose_mode <<< "2"
    [ "$output" = "ipv6" ]
    run ovpn_wizard_choose_mode <<< "3"
    [ "$output" = "dual" ]
    run ovpn_wizard_choose_mode <<< ""
    [ "$output" = "ipv4" ]
}

@test "ovpn_wizard_ipproto: modo não suportado aborta" {
    run ovpn_wizard_ipproto ipv9
    [ "$status" -ne 0 ]
}

@test "ovpn_wizard_choose_subnet: entrada válida define e persiste a sub-rede" {
    run ovpn_wizard_choose_subnet <<< "10.8.4.0"
    [ "$status" -eq 0 ]
    [ "$(ovpn_config_get OVPN_SUBNET_V4)" = "10.8.4.0" ]
}

@test "ovpn_wizard_choose_subnet: define no ambiente a sub-rede e o prefixo derivado" {
    ovpn_wizard_choose_subnet <<< "172.20.5.0"
    [ "${OVPN_SUBNET_V4}" = "172.20.5.0" ]
    [ "${OVPN_VPN_PREFIX_V4}" = "172.20.5" ]
}

@test "ovpn_wizard_choose_subnet: entrada vazia mantém o padrão" {
    ovpn_wizard_choose_subnet <<< ""
    [ "${OVPN_SUBNET_V4}" = "10.8.0.0" ]
}

@test "ovpn_wizard_choose_subnet: entrada inválida mantém a sub-rede atual" {
    ovpn_wizard_choose_subnet <<< "banana"
    [ "${OVPN_SUBNET_V4}" = "10.8.0.0" ]
}
