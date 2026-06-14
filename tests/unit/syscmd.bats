#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
    load_lib log
    load_lib syscmd
    export OVPN_BIN_DIR="${BATS_TEST_TMPDIR}/bin"
    printf '#!/usr/bin/env bash\n' > "${BATS_TEST_TMPDIR}/install.sh"
}

@test "ovpn_install_path_command: cria o symlink openvpn-installer no PATH" {
    run ovpn_install_path_command "${BATS_TEST_TMPDIR}/install.sh"
    [ "$status" -eq 0 ]
    [ -L "${OVPN_BIN_DIR}/openvpn-installer" ]
    [ "$(readlink "${OVPN_BIN_DIR}/openvpn-installer")" = "${BATS_TEST_TMPDIR}/install.sh" ]
}

@test "ovpn_install_path_command: aborta se o install.sh não existe" {
    run ovpn_install_path_command "/nao/existe/install.sh"
    [ "$status" -ne 0 ]
}
