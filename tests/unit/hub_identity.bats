#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
    load_lib log
    load_lib hub_identity
    export OVPN_SUBNET_V4=10.80.0.0
    export OVPN_NETMASK_V4=255.255.255.0
    export OVPN_SYSTEMD_DIR="${BATS_TEST_TMPDIR}/systemd"
}

@test "ovpn_hub_identity_ip: deriva o /32 reservado do topo (HUB_ID)" {
    [ "$(OVPN_HUB_ID=1 ovpn_hub_identity_ip)" = "10.80.0.241" ]
    [ "$(OVPN_HUB_ID=2 ovpn_hub_identity_ip)" = "10.80.0.242" ]
    [ "$(ovpn_hub_identity_ip 3)" = "10.80.0.243" ]
}

@test "ovpn_hub_identity_ip: respeita a máscara (/22 -> topo do /22)" {
    export OVPN_NETMASK_V4=255.255.252.0
    [ "$(OVPN_HUB_ID=1 ovpn_hub_identity_ip)" = "10.80.3.241" ]
}

@test "ovpn_hub_identity_install: escreve a unit com o IP/dummy e habilita" {
    export OVPN_HUB_ID=1
    ovpn_hub_identity_install
    local u="${OVPN_SYSTEMD_DIR}/openvpn-hub-identity.service"
    [ -f "${u}" ]
    grep -q '10.80.0.241/32' "${u}"
    grep -q 'ovpn-self' "${u}"
    run stub_calls systemctl
    [[ "$output" == *"enable --now openvpn-hub-identity.service"* ]]
}
