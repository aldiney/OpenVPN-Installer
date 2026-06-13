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

@test "ovpn_wizard_ipproto: modo não suportado aborta" {
    run ovpn_wizard_ipproto ipv9
    [ "$status" -ne 0 ]
}
