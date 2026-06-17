#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
    load_lib route_reconcile
}

@test "ovpn_reconcile_parse_status: extrai os IPs virtuais dos CLIENT_LIST" {
    local s="${BATS_TEST_TMPDIR}/status"
    cat > "${s}" <<EOF
TITLE,OpenVPN
HEADER,CLIENT_LIST,Common Name,Real Address,Virtual Address,Virtual IPv6
CLIENT_LIST,alice,1.2.3.4:5,10.80.0.5,,1,1
CLIENT_LIST,bob,1.2.3.5:6,10.80.0.6,,1,1
GLOBAL_STATS,Max bcast
END
EOF
    run ovpn_reconcile_parse_status "${s}"
    [[ "$output" == *"10.80.0.5"* ]]
    [[ "$output" == *"10.80.0.6"* ]]
    [[ "$output" != *"GLOBAL_STATS"* ]]
}

@test "ovpn_reconcile_apply: instala /32 dos conectados e remove os órfãos" {
    local s="${BATS_TEST_TMPDIR}/status"
    printf 'CLIENT_LIST,alice,1.2.3.4:5,10.80.0.5,,1,1\n' > "${s}"
    export STUB_IP_ROUTES="10.80.0.9/32 dev tun0 proto static metric 50"
    export OVPN_TUN_IFACE=tun0
    run ovpn_reconcile_apply "${s}"
    [ "$status" -eq 0 ]
    run stub_calls ip
    [[ "$output" == *"route replace 10.80.0.5/32 dev tun0 proto static metric 50"* ]]
    [[ "$output" == *"route del 10.80.0.9/32"* ]]
}

@test "ovpn_reconcile_apply: idempotente (não remove cliente ainda conectado)" {
    local s="${BATS_TEST_TMPDIR}/status"
    printf 'CLIENT_LIST,alice,1.2.3.4:5,10.80.0.5,,1,1\n' > "${s}"
    export STUB_IP_ROUTES="10.80.0.5/32 dev tun0 proto static metric 50"
    export OVPN_TUN_IFACE=tun0
    run ovpn_reconcile_apply "${s}"
    [ "$status" -eq 0 ]
    run stub_calls ip
    [[ "$output" != *"route del 10.80.0.5"* ]]
}

@test "ovpn_reconcile_install_units: escreve o entrypoint + units e habilita via systemd" {
    export OVPN_RECONCILE_BIN="${BATS_TEST_TMPDIR}/bin/route-reconcile.sh"
    export OVPN_SYSTEMD_DIR="${BATS_TEST_TMPDIR}/systemd"
    export OVPN_RECONCILE_SPOOL="${BATS_TEST_TMPDIR}/run/reconcile.trigger"
    export OVPN_LIB_DIR="${PROJECT_ROOT}/lib"
    ovpn_reconcile_install_units
    [ -x "${OVPN_RECONCILE_BIN}" ]
    [ -f "${OVPN_SYSTEMD_DIR}/openvpn-route-reconcile.service" ]
    [ -f "${OVPN_SYSTEMD_DIR}/openvpn-route-reconcile.path" ]
    [ -f "${OVPN_SYSTEMD_DIR}/openvpn-route-reconcile.timer" ]
    grep -q "PathModified=${OVPN_RECONCILE_SPOOL}" "${OVPN_SYSTEMD_DIR}/openvpn-route-reconcile.path"
    run stub_calls systemctl
    [[ "$output" == *"enable"* ]]
    [[ "$output" == *"openvpn-route-reconcile.path"* ]]
}
