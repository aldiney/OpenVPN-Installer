#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
    load_lib log
    load_lib deps
    load_lib frr
    export OVPN_FRR_DIR="${BATS_TEST_TMPDIR}/frr"
    export OVPN_FRR_DAEMONS="${OVPN_FRR_DIR}/daemons"
    export OVPN_FRR_OSPF_CONF="${OVPN_FRR_DIR}/ospfd.conf"
}

@test "ovpn_frr_render_daemons: habilita só o ospfd (+ zebra), não o bgpd" {
    ovpn_frr_render_daemons
    grep -q '^zebra=yes$' "${OVPN_FRR_DAEMONS}"
    grep -q '^ospfd=yes$' "${OVPN_FRR_DAEMONS}"
    grep -q '^bgpd=no$' "${OVPN_FRR_DAEMONS}"
    ! grep -q '^bgpd=yes$' "${OVPN_FRR_DAEMONS}"
}

@test "ovpn_frr_render_ospf: redistribui só os /32 dos clientes (sem o /22 conectado)" {
    ovpn_frr_render_ospf 0.0.0.1 10.80.0.0 22 10.255.0.0/30 0.0.0.0 ovpn-link
    local c="${OVPN_FRR_OSPF_CONF}"
    grep -q 'ospf router-id 0.0.0.1' "${c}"
    grep -q 'redistribute static route-map ONLY-CLIENT-32' "${c}"
    ! grep -q 'redistribute kernel' "${c}"
    grep -q 'ip prefix-list CLIENT32 seq 5 permit 10.80.0.0/22 ge 32 le 32' "${c}"
    grep -q 'route-map ONLY-CLIENT-32 permit 10' "${c}"
    grep -q 'network 10.255.0.0/30 area 0.0.0.0' "${c}"
    grep -q 'no passive-interface ovpn-link' "${c}"
    grep -q 'ip ospf network point-to-multipoint' "${c}"
    ! grep -q 'redistribute connected' "${c}"
}

@test "ovpn_frr_ensure: passa pelo gate de dependências (frr)" {
    local got=""
    ovpn_deps_ensure() { got="$*"; }
    ovpn_frr_ensure
    [ "${got}" = "frr" ]
}

@test "ovpn_frr_enable: habilita e inicia o frr" {
    run ovpn_frr_enable
    [ "$status" -eq 0 ]
    run stub_calls systemctl
    [[ "$output" == *"enable --now frr"* ]]
}

@test "ovpn_frr_show_routes: consulta as rotas OSPF via vtysh" {
    run ovpn_frr_show_routes
    [ "$status" -eq 0 ]
    run stub_calls vtysh
    [[ "$output" == *"show ip route ospf"* ]]
}
