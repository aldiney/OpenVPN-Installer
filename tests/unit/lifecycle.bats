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
    load_lib lifecycle

    mkdir -p "${OVPN_SERVER_DIR}" "${OVPN_PKI_DIR}"
    printf 'dev tun\n' > "$(ovpn_server_conf_path)"
    mkdir -p "$(ovpn_server_ccd_dir)"
    printf 'CA\n' > "$(ovpn_pki_ca_cert)"
}

@test "ovpn_uninstall: para o serviço e remove a config, preservando a PKI" {
    run ovpn_uninstall keep
    [ "$status" -eq 0 ]
    [ ! -f "$(ovpn_server_conf_path)" ]
    [ ! -d "$(ovpn_server_ccd_dir)" ]
    [ -f "$(ovpn_pki_ca_cert)" ]
    run stub_calls systemctl
    [[ "$output" == *"disable"* ]]
    [[ "$output" == *"openvpn-server@server"* ]]
}

@test "ovpn_uninstall purge: também remove a PKI" {
    run ovpn_uninstall purge
    [ "$status" -eq 0 ]
    [ ! -d "${OVPN_PKI_DIR}" ]
}
