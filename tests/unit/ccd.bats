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

@test "ovpn_ccd_set_full_tunnel: empurra redirect-gateway e DNS só para o cliente" {
    ovpn_ccd_assign alice >/dev/null
    ovpn_ccd_set_full_tunnel alice
    local f="${OVPN_SERVER_DIR}/ccd/alice"
    grep -q 'push "redirect-gateway def1"' "${f}"
    grep -q 'dhcp-option DNS' "${f}"
}

@test "ovpn_ccd_set_full_tunnel: é idempotente (não duplica)" {
    ovpn_ccd_assign alice >/dev/null
    ovpn_ccd_set_full_tunnel alice
    ovpn_ccd_set_full_tunnel alice
    local n
    n="$(grep -c 'redirect-gateway' "${OVPN_SERVER_DIR}/ccd/alice")"
    [ "${n}" -eq 1 ]
}

@test "ovpn_ccd_unset_full_tunnel: remove a marcação (volta a split-tunnel)" {
    ovpn_ccd_assign alice >/dev/null
    ovpn_ccd_set_full_tunnel alice
    ovpn_ccd_unset_full_tunnel alice
    local f="${OVPN_SERVER_DIR}/ccd/alice"
    ! grep -q 'redirect-gateway' "${f}"
    grep -q 'ifconfig-push' "${f}"
}
