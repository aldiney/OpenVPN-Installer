#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
    load_lib log
    load_lib pki
    load_lib wizard_ipproto
    load_lib server_config
}

@test "ovpn_server_render: gera o server.conf com as diretivas essenciais" {
    ovpn_server_render ipv4
    conf="${OVPN_SERVER_DIR}/server.conf"
    [ -f "${conf}" ]
    grep -q "^dev tun$" "${conf}"
    grep -q "^topology subnet$" "${conf}"
    grep -q "^client-to-client$" "${conf}"
    grep -q "^tls-crypt " "${conf}"
    grep -q "^data-ciphers AES-256-GCM:AES-128-GCM$" "${conf}"
    grep -q "^client-config-dir " "${conf}"
}

@test "ovpn_server_enable: habilita e inicia o serviço via systemd" {
    run ovpn_server_enable
    [ "$status" -eq 0 ]
    run stub_calls systemctl
    [[ "$output" == *"enable"* ]]
    [[ "$output" == *"openvpn-server@server"* ]]
}

@test "ovpn_server_apply_forwarding: habilita encaminhamento IPv6 no modo dual" {
    run ovpn_server_apply_forwarding dual
    [ "$status" -eq 0 ]
    run stub_calls sysctl
    [[ "$output" == *"net.ipv6.conf.all.forwarding=1"* ]]
}

@test "ovpn_server_apply_forwarding: modo ipv4 não mexe no encaminhamento IPv6" {
    run ovpn_server_apply_forwarding ipv4
    [ "$status" -eq 0 ]
    run stub_calls sysctl
    [ -z "$output" ]
}

@test "ovpn_server_render: inclui mssfix (clamping de MSS contra travas de MTU)" {
    ovpn_server_render ipv4
    grep -qE '^mssfix [0-9]+$' "$(ovpn_server_conf_path)"
}

@test "ovpn_server_render: mssfix presente também em dual-stack" {
    ovpn_server_render dual
    grep -qE '^mssfix [0-9]+$' "$(ovpn_server_conf_path)"
}

@test "ovpn_server_render: mssfix é configurável via OVPN_MSSFIX" {
    export OVPN_MSSFIX=1400
    ovpn_server_render ipv4
    grep -q '^mssfix 1400$' "$(ovpn_server_conf_path)"
}
