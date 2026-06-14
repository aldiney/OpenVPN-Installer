#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
    load_lib log
    load_lib firewall
}

@test "_ovpn_firewall_backend: detecta ufw quando ativo" {
    run _ovpn_firewall_backend
    [ "$output" = "ufw" ]
}

@test "_ovpn_firewall_backend: cai para nft quando o ufw está inativo" {
    export STUB_UFW_STATUS="inactive"
    run _ovpn_firewall_backend
    [ "$output" = "nft" ]
}

@test "ovpn_firewall_open_port: usa ufw quando ativo" {
    _ovpn_firewall_backend() { printf 'ufw'; }
    run ovpn_firewall_open_port 1194 udp
    [ "$status" -eq 0 ]
    run stub_calls ufw
    [[ "$output" == *"allow 1194/udp"* ]]
}

@test "ovpn_firewall_open_port: usa nft como backend alternativo" {
    _ovpn_firewall_backend() { printf 'nft'; }
    run ovpn_firewall_open_port 1194 udp
    [ "$status" -eq 0 ]
    run stub_calls nft
    [[ "$output" == *"dport 1194"* ]]
    [[ "$output" == *"accept"* ]]
}

@test "ovpn_firewall_open_port: usa iptables como fallback" {
    _ovpn_firewall_backend() { printf 'iptables'; }
    run ovpn_firewall_open_port 1194 udp
    [ "$status" -eq 0 ]
    run stub_calls iptables
    [[ "$output" == *"--dport 1194"* ]]
    [[ "$output" == *"ACCEPT"* ]]
}
