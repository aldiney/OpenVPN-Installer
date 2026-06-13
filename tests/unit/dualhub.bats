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
    load_lib dualhub

    export OVPN_REMOTE_HOST="hubA.exemplo.com"
    _ovpn_pki_gen_ca_key()        { printf 'CA-KEY\n' > "$1"; }
    _ovpn_pki_gen_ca_cert()       { printf 'CA-CERT\n' > "$2"; }
    _ovpn_pki_gen_entity_key()    { printf 'ENT-KEY\n' > "$1"; }
    _ovpn_pki_sign_entity()       { printf 'ENT-CERT\n' > "$2"; }
    _ovpn_pki_gen_tls_crypt_key() { printf 'TLS-CRYPT\n' > "$1"; }
    ovpn_pki_build_ca >/dev/null
    ovpn_pki_gen_tls_crypt
}

@test "ovpn_dualhub_validate_subnets: recusa sub-redes iguais (sobreposição)" {
    run ovpn_dualhub_validate_subnets 10.8.0.0 10.8.0.0
    [ "$status" -ne 0 ]
}

@test "ovpn_dualhub_validate_subnets: aceita sub-redes diferentes" {
    run ovpn_dualhub_validate_subnets 10.8.0.0 10.8.1.0
    [ "$status" -eq 0 ]
}

@test "ovpn_dualhub_configure: adiciona rota e push para a sub-rede do hub par" {
    mkdir -p "${OVPN_SERVER_DIR}"
    printf 'dev tun\n' > "$(ovpn_server_conf_path)"
    run ovpn_dualhub_configure 10.8.1.0 255.255.255.0
    [ "$status" -eq 0 ]
    local conf
    conf="$(ovpn_server_conf_path)"
    grep -q '^route 10.8.1.0 255.255.255.0' "${conf}"
    grep -q 'push "route 10.8.1.0 255.255.255.0"' "${conf}"
}

@test "client_profile: com dois hubs, o .ovpn lista os dois remote" {
    export OVPN_REMOTE_HOST_2="hubB.exemplo.com"
    ovpn_client_create alice
    local prof="${OVPN_CLIENTS_DIR}/alice.ovpn"
    grep -q "remote hubA.exemplo.com" "${prof}"
    grep -q "remote hubB.exemplo.com" "${prof}"
}
