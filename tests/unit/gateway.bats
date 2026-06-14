#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
    load_lib log
    load_lib firewall
    load_lib gateway
}

@test "ovpn_gateway_enable: sem interface WAN, aborta" {
    run ovpn_gateway_enable ""
    [ "$status" -ne 0 ]
}

@test "ovpn_gateway_enable: em UFW, libera o forward e faz masquerade" {
    _ovpn_firewall_backend() { printf 'ufw'; }
    export OVPN_UFW_DEFAULTS="${BATS_TEST_TMPDIR}/ufw_defaults"
    printf 'DEFAULT_FORWARD_POLICY="DROP"\n' > "${OVPN_UFW_DEFAULTS}"

    run ovpn_gateway_enable ens3
    [ "$status" -eq 0 ]
    grep -q 'DEFAULT_FORWARD_POLICY="ACCEPT"' "${OVPN_UFW_DEFAULTS}"

    run stub_calls ufw
    [[ "$output" == *"reload"* ]]
    run stub_calls nft
    [[ "$output" == *"masquerade"* ]]
    [[ "$output" == *"ens3"* ]]
}

@test "ovpn_gateway_enable: em nft, aplica masquerade na WAN" {
    _ovpn_firewall_backend() { printf 'nft'; }
    run ovpn_gateway_enable eth0
    [ "$status" -eq 0 ]
    run stub_calls nft
    [[ "$output" == *"masquerade"* ]]
    [[ "$output" == *"eth0"* ]]
}

@test "ovpn_gateway_enable: em iptables, aplica MASQUERADE na WAN" {
    _ovpn_firewall_backend() { printf 'iptables'; }
    run ovpn_gateway_enable eth0
    [ "$status" -eq 0 ]
    run stub_calls iptables
    [[ "$output" == *"MASQUERADE"* ]]
    [[ "$output" == *"eth0"* ]]
}

@test "ovpn_gateway_disable: remove a tabela de NAT (nft)" {
    _ovpn_firewall_backend() { printf 'nft'; }
    run ovpn_gateway_disable
    [ "$status" -eq 0 ]
    run stub_calls nft
    [[ "$output" == *"delete table ip ovpn"* ]]
}

@test "ovpn_gateway_enable: NÃO mexe no server.conf (full-tunnel é por cliente)" {
    _ovpn_firewall_backend() { printf 'nft'; }
    mkdir -p "${OVPN_SERVER_DIR}"
    printf 'dev tun\n' > "${OVPN_SERVER_DIR}/server.conf"
    run ovpn_gateway_enable eth0
    [ "$status" -eq 0 ]
    ! grep -q 'redirect-gateway' "${OVPN_SERVER_DIR}/server.conf"
}
