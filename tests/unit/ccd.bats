#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
    load_lib ccd
}

@test "ovpn_ccd_assign: cria a entrada do cliente com IP fixo (ifconfig-push)" {
    run ovpn_ccd_assign alice
    [ "$status" -eq 0 ]
    [ -f "${OVPN_SERVER_DIR}/ccd/alice" ]
    grep -q "ifconfig-push" "${OVPN_SERVER_DIR}/ccd/alice"
}

@test "ovpn_ccd_assign: é idempotente (mantém o mesmo IP)" {
    local first second
    first="$(ovpn_ccd_assign alice)"
    second="$(ovpn_ccd_assign alice)"
    [ -n "${first}" ]
    [ "${first}" = "${second}" ]
}

@test "ovpn_ccd_assign: clientes diferentes recebem IPs diferentes" {
    local a b
    a="$(ovpn_ccd_assign alice)"
    b="$(ovpn_ccd_assign bob)"
    [ "${a}" != "${b}" ]
}
