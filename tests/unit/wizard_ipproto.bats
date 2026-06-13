#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
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
