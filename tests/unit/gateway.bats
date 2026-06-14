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

@test "ovpn_gateway_enable: em UFW, libera o forward (ufw route) e grava NAT persistente" {
    _ovpn_firewall_backend() { printf 'ufw'; }
    export OVPN_UFW_BEFORE_RULES="${BATS_TEST_TMPDIR}/before.rules"
    printf '*filter\n:ufw-before-input - [0:0]\nCOMMIT\n' > "${OVPN_UFW_BEFORE_RULES}"

    run ovpn_gateway_enable ens3
    [ "$status" -eq 0 ]
    run stub_calls ufw
    [[ "$output" == *"route allow in on tun0 out on ens3"* ]]
    [[ "$output" == *"reload"* ]]
    grep -q -- '-A POSTROUTING -s 10.8.0.0/24 -o ens3 -j MASQUERADE' "${OVPN_UFW_BEFORE_RULES}"
}

@test "ovpn_gateway_enable UFW: idempotente (não duplica o NAT)" {
    _ovpn_firewall_backend() { printf 'ufw'; }
    export OVPN_UFW_BEFORE_RULES="${BATS_TEST_TMPDIR}/before.rules"
    printf '*filter\nCOMMIT\n' > "${OVPN_UFW_BEFORE_RULES}"
    ovpn_gateway_enable ens3
    ovpn_gateway_enable ens3
    [ "$(grep -c 'MASQUERADE' "${OVPN_UFW_BEFORE_RULES}")" -eq 1 ]
}

@test "ovpn_gateway_enable UFW: insere o NAT num before.rules que já tem *nat" {
    _ovpn_firewall_backend() { printf 'ufw'; }
    export OVPN_UFW_BEFORE_RULES="${BATS_TEST_TMPDIR}/before.rules"
    printf '*nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s 172.17.0.0/16 -j MASQUERADE\nCOMMIT\n\n*filter\nCOMMIT\n' \
        > "${OVPN_UFW_BEFORE_RULES}"
    run ovpn_gateway_enable ens3
    [ "$status" -eq 0 ]
    grep -q -- '-A POSTROUTING -s 10.8.0.0/24 -o ens3 -j MASQUERADE' "${OVPN_UFW_BEFORE_RULES}"
    [ "$(grep -c '^\*nat' "${OVPN_UFW_BEFORE_RULES}")" -eq 1 ]
}

@test "ovpn_gateway_disable UFW: remove o route allow e o NAT" {
    _ovpn_firewall_backend() { printf 'ufw'; }
    export OVPN_UFW_BEFORE_RULES="${BATS_TEST_TMPDIR}/before.rules"
    printf '*filter\nCOMMIT\n' > "${OVPN_UFW_BEFORE_RULES}"
    ovpn_gateway_enable ens3
    run ovpn_gateway_disable ens3
    [ "$status" -eq 0 ]
    ! grep -q 'MASQUERADE' "${OVPN_UFW_BEFORE_RULES}"
    run stub_calls ufw
    [[ "$output" == *"route delete allow in on tun0 out on ens3"* ]]
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

@test "ovpn_gateway_enable: NÃO mexe no server.conf (full-tunnel é por cliente)" {
    _ovpn_firewall_backend() { printf 'nft'; }
    mkdir -p "${OVPN_SERVER_DIR}"
    printf 'dev tun\n' > "${OVPN_SERVER_DIR}/server.conf"
    run ovpn_gateway_enable eth0
    [ "$status" -eq 0 ]
    ! grep -q 'redirect-gateway' "${OVPN_SERVER_DIR}/server.conf"
}
