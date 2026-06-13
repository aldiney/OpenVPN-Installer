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
    load_lib ccd
    load_lib client_profile
    load_lib gateway
    load_lib mikrotik_profile
    load_lib controller

    export OVPN_REMOTE_HOST="vpn.exemplo.com"
    _ovpn_pki_gen_ca_key()        { printf 'CA-KEY\n' > "$1"; }
    _ovpn_pki_gen_ca_cert()       { printf 'CA-CERT\n' > "$2"; }
    _ovpn_pki_gen_entity_key()    { printf 'ENT-KEY\n' > "$1"; }
    _ovpn_pki_sign_entity()       { printf 'ENT-CERT\n' > "$2"; }
    _ovpn_pki_gen_tls_crypt_key() { printf 'TLS-CRYPT\n' > "$1"; }
    ovpn_pki_build_ca >/dev/null
    ovpn_pki_gen_tls_crypt
}

@test "ovpn_mikrotik_create: gera .ovpn com cipher explícito e SEM comp-lzo" {
    ovpn_mikrotik_create rb750
    local prof="${OVPN_CLIENTS_DIR}/rb750.mikrotik.ovpn"
    [ -f "${prof}" ]
    grep -qE '^cipher ' "${prof}"
    ! grep -q 'comp-lzo' "${prof}"
    ! grep -q 'lzo' "${prof}"
}

@test "ovpn_mikrotik_create: .ovpn leva os certificados inline" {
    ovpn_mikrotik_create rb750
    local prof="${OVPN_CLIENTS_DIR}/rb750.mikrotik.ovpn"
    grep -q "<ca>" "${prof}"
    grep -q "<cert>" "${prof}"
    grep -q "<key>" "${prof}"
    grep -q "<tls-crypt>" "${prof}"
}

@test "ovpn_mikrotik_create: gera o script .rsc com /interface ovpn-client add" {
    ovpn_mikrotik_create rb750
    local rsc="${OVPN_CLIENTS_DIR}/rb750.rsc"
    [ -f "${rsc}" ]
    grep -q '/interface ovpn-client add' "${rsc}"
    grep -q 'connect-to=vpn.exemplo.com' "${rsc}"
}

@test "ovpn_action_add_mikrotik: cria o perfil pelo controller" {
    run ovpn_action_add_mikrotik rb750
    [ "$status" -eq 0 ]
    [ -f "${OVPN_CLIENTS_DIR}/rb750.mikrotik.ovpn" ]
    [ -f "${OVPN_CLIENTS_DIR}/rb750.rsc" ]
}
