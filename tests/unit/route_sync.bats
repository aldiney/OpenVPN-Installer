#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
    load_lib log
    load_lib ccd
    load_lib route_sync
    export OVPN_DOMAIN_ID=acme
    export OVPN_SUBNET_V4=10.80.0.0
    export OVPN_NETMASK_V4=255.255.252.0
}

@test "ovpn_route_sync_export/import: o mapa cliente->IP é replicado idêntico" {
    ovpn_ccd_assign alice >/dev/null   # 10.80.0.2
    local bundle="${BATS_TEST_TMPDIR}/map.tar.gz"
    ovpn_route_sync_export "${bundle}"

    export OVPN_SERVER_DIR="${BATS_TEST_TMPDIR}/serverB"
    ovpn_route_sync_import "${bundle}"
    grep -q '^ifconfig-push 10.80.0.2 ' "$(ovpn_ccd_dir)/alice"
}

@test "ovpn_route_sync_import: recusa bundle de outro domínio" {
    ovpn_ccd_assign alice >/dev/null
    local bundle="${BATS_TEST_TMPDIR}/map.tar.gz"
    ovpn_route_sync_export "${bundle}"
    export OVPN_DOMAIN_ID=outro
    run ovpn_route_sync_import "${bundle}"
    [ "$status" -ne 0 ]
}

@test "ovpn_route_sync_import: recusa bundle adulterado (checksum)" {
    ovpn_ccd_assign alice >/dev/null
    local bundle="${BATS_TEST_TMPDIR}/map.tar.gz"
    ovpn_route_sync_export "${bundle}"
    local t="${BATS_TEST_TMPDIR}/t"; mkdir -p "${t}"
    tar xzf "${bundle}" -C "${t}"
    printf 'evil 10.80.0.99 255.255.252.0\n' >> "${t}/clients.map"
    ( cd "${t}" && tar czf "${bundle}" clients.map manifest checksum.sha256 )
    run ovpn_route_sync_import "${bundle}"
    [ "$status" -ne 0 ]
}

@test "ovpn_route_sync_import: preserva outras linhas do ccd (ex.: iroute)" {
    ovpn_ccd_assign alice >/dev/null
    local bundle="${BATS_TEST_TMPDIR}/map.tar.gz"
    ovpn_route_sync_export "${bundle}"

    export OVPN_SERVER_DIR="${BATS_TEST_TMPDIR}/serverB"
    mkdir -p "$(ovpn_ccd_dir)"
    printf 'iroute 10.9.0.0 255.255.255.0\n' > "$(ovpn_ccd_dir)/alice"
    ovpn_route_sync_import "${bundle}"
    grep -q '^iroute 10.9.0.0' "$(ovpn_ccd_dir)/alice"
    grep -q '^ifconfig-push 10.80.0.2 ' "$(ovpn_ccd_dir)/alice"
}
