#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
}

# Escreve um os-release falso no sandbox e aponta o módulo para ele.
write_os_release() {
    local id="$1" version="$2"
    cat > "${BATS_TEST_TMPDIR}/os-release" <<EOF
ID=${id}
VERSION_ID="${version}"
EOF
    export OVPN_OS_RELEASE_FILE="${BATS_TEST_TMPDIR}/os-release"
}

@test "ovpn_os_id: lê o ID do os-release" {
    write_os_release debian 12
    load_lib os_detect
    run ovpn_os_id
    [ "$output" = "debian" ]
}

@test "ovpn_os_is_supported: Debian 12 é suportado" {
    write_os_release debian 12
    load_lib os_detect
    run ovpn_os_is_supported
    [ "$status" -eq 0 ]
}

@test "ovpn_os_is_supported: Debian 13 é suportado" {
    write_os_release debian 13
    load_lib os_detect
    run ovpn_os_is_supported
    [ "$status" -eq 0 ]
}

@test "ovpn_os_is_supported: Ubuntu 24.04 é suportado" {
    write_os_release ubuntu 24.04
    load_lib os_detect
    run ovpn_os_is_supported
    [ "$status" -eq 0 ]
}

@test "ovpn_os_is_supported: Ubuntu 24.10 é suportado" {
    write_os_release ubuntu 24.10
    load_lib os_detect
    run ovpn_os_is_supported
    [ "$status" -eq 0 ]
}

@test "ovpn_os_is_supported: Debian 11 NÃO é suportado" {
    write_os_release debian 11
    load_lib os_detect
    run ovpn_os_is_supported
    [ "$status" -ne 0 ]
}

@test "ovpn_os_is_supported: Ubuntu 22.04 NÃO é suportado" {
    write_os_release ubuntu 22.04
    load_lib os_detect
    run ovpn_os_is_supported
    [ "$status" -ne 0 ]
}

@test "ovpn_os_is_supported: distro desconhecida NÃO é suportada" {
    write_os_release fedora 40
    load_lib os_detect
    run ovpn_os_is_supported
    [ "$status" -ne 0 ]
}

@test "ovpn_os_assert_supported: aborta com mensagem clara em sistema não suportado" {
    write_os_release ubuntu 22.04
    load_lib core
    load_lib log
    load_lib os_detect
    run --separate-stderr ovpn_os_assert_supported
    [ "$status" -ne 0 ]
    [[ "$stderr" == *"Debian 12"* ]]
    [[ "$stderr" == *"Ubuntu 24.04"* ]]
}
