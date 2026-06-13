#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
    load_lib log
    load_lib wizard_ipproto
    load_lib server_config
    load_lib gateway
    # Cria um server.conf mínimo para o gateway editar.
    mkdir -p "${OVPN_SERVER_DIR}"
    printf 'dev tun\n' > "$(ovpn_server_conf_path)"
}

@test "ovpn_gateway_enable: adiciona o push redirect-gateway ao server.conf" {
    ovpn_gateway_enable eth0
    grep -q 'redirect-gateway def1' "$(ovpn_server_conf_path)"
}

@test "ovpn_gateway_enable: aplica NAT masquerade via nft (backend padrão)" {
    run ovpn_gateway_enable eth0
    [ "$status" -eq 0 ]
    run stub_calls nft
    [[ "$output" == *"masquerade"* ]]
    [[ "$output" == *"eth0"* ]]
}

@test "ovpn_gateway_enable: usa iptables quando o backend é iptables" {
    _ovpn_gateway_backend() { printf 'iptables'; }
    run ovpn_gateway_enable eth0
    [ "$status" -eq 0 ]
    run stub_calls iptables
    [[ "$output" == *"MASQUERADE"* ]]
    [[ "$output" == *"eth0"* ]]
}

@test "ovpn_gateway_enable: sem interface WAN, aborta" {
    run ovpn_gateway_enable ""
    [ "$status" -ne 0 ]
}

@test "ovpn_gateway_disable: remove o push redirect-gateway do server.conf" {
    ovpn_gateway_enable eth0
    ovpn_gateway_disable eth0
    run cat "$(ovpn_server_conf_path)"
    [[ "$output" != *"redirect-gateway def1"* ]]
}
