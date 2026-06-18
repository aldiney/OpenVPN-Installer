#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
    load_lib log
    load_lib ccd
    load_lib route_sync
    load_lib mapsync
    export OVPN_DOMAIN_ID=acme
    export OVPN_SUBNET_V4=10.80.0.0
    export OVPN_NETMASK_V4=255.255.252.0
    export OVPN_TRANSPORT_NET_V4=10.255.0.0
    export OVPN_MAP_BUNDLE="${BATS_TEST_TMPDIR}/var/clients-map.tar.gz"
    export OVPN_MAPSYNC_DIR="${BATS_TEST_TMPDIR}/etc/openvpn-installer"
    export OVPN_MAPSYNC_KEY="${OVPN_MAPSYNC_DIR}/mapsync_key"
    export OVPN_MAPSYNC_AUTHKEYS="${BATS_TEST_TMPDIR}/root/.ssh/authorized_keys"
    export OVPN_MAPSYNC_BIN="${BATS_TEST_TMPDIR}/bin/mapsync-pull.sh"
    export OVPN_SYSTEMD_DIR="${BATS_TEST_TMPDIR}/systemd"
}

@test "_ovpn_mapsync_core_ip: o primário é o .1 da rede de transporte" {
    [ "$(_ovpn_mapsync_core_ip)" = "10.255.0.1" ]
}

@test "ovpn_mapsync_publish: exporta o mapa para o caminho fixo" {
    ovpn_ccd_assign alice >/dev/null
    ovpn_mapsync_publish
    [ -f "${OVPN_MAP_BUNDLE}" ]
}

@test "ovpn_mapsync_keygen: gera a chave (idempotente) e ecoa a pública" {
    run ovpn_mapsync_keygen
    [ "$status" -eq 0 ]
    [[ "$output" == ssh-ed25519* ]]
    [ -f "${OVPN_MAPSYNC_KEY}" ]
    # idempotente: a 2ª chamada NÃO roda ssh-keygen de novo (chave já existe)
    ovpn_mapsync_keygen >/dev/null
    run stub_calls ssh-keygen
    [ "$(printf '%s\n' "$output" | grep -c ed25519)" -eq 1 ]
}

@test "ovpn_mapsync_authorize: adiciona a chave com forced-command (idempotente)" {
    local pub="ssh-ed25519 AAAAKEYDATA spoke2"
    ovpn_mapsync_authorize "${pub}"
    ovpn_mapsync_authorize "${pub}"
    grep -q "command=\"cat ${OVPN_MAP_BUNDLE}\",restrict ssh-ed25519 AAAAKEYDATA" "${OVPN_MAPSYNC_AUTHKEYS}"
    [ "$(grep -c 'AAAAKEYDATA' "${OVPN_MAPSYNC_AUTHKEYS}")" -eq 1 ]
}

@test "ovpn_mapsync_authorize: sem chave, aborta" {
    run ovpn_mapsync_authorize ""
    [ "$status" -ne 0 ]
}

@test "ovpn_mapsync_pull: puxa do core (.1) por ssh e importa quando vem conteúdo" {
    export STUB_SSH_OUTPUT="BUNDLE-BYTES"
    local got=""
    ovpn_route_sync_import() { got="imported:$1"; printf '%s' "${got}" > "${BATS_TEST_TMPDIR}/imported"; }
    ovpn_mapsync_pull
    run stub_calls ssh
    [[ "$output" == *"root@10.255.0.1"* ]]
    [[ "$output" == *"-i ${OVPN_MAPSYNC_KEY}"* ]]
    [ -f "${BATS_TEST_TMPDIR}/imported" ]
}

@test "ovpn_mapsync_pull: sem conteúdo do core, NÃO importa" {
    export STUB_SSH_OUTPUT=""
    ovpn_route_sync_import() { printf 'X' > "${BATS_TEST_TMPDIR}/imported"; }
    ovpn_mapsync_pull
    [ ! -f "${BATS_TEST_TMPDIR}/imported" ]
}

@test "ovpn_mapsync_install_units: escreve o entrypoint + timer e habilita" {
    export OVPN_LIB_DIR="${PROJECT_ROOT}/lib"
    ovpn_mapsync_install_units
    [ -x "${OVPN_MAPSYNC_BIN}" ]
    [ -f "${OVPN_SYSTEMD_DIR}/openvpn-mapsync.service" ]
    [ -f "${OVPN_SYSTEMD_DIR}/openvpn-mapsync.timer" ]
    run stub_calls systemctl
    [[ "$output" == *"enable --now openvpn-mapsync.timer"* ]]
}
