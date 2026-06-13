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
    load_lib controller

    export OVPN_REMOTE_HOST="vpn.exemplo.com"
    # Seams de criptografia substituídos (sem cripto real).
    _ovpn_pki_gen_ca_key()        { printf 'CA-KEY\n' > "$1"; }
    _ovpn_pki_gen_ca_cert()       { printf 'CA-CERT\n' > "$2"; }
    _ovpn_pki_gen_entity_key()    { printf 'ENT-KEY\n' > "$1"; }
    _ovpn_pki_sign_entity()       { printf 'ENT-CERT\n' > "$2"; }
    _ovpn_pki_gen_tls_crypt_key() { printf 'TLS-CRYPT\n' > "$1"; }
    ovpn_pki_build_ca >/dev/null
    ovpn_pki_gen_tls_crypt
}

@test "ovpn_client_create: gera o .ovpn com certificados embutidos (inline)" {
    ovpn_client_create alice
    local profile="${OVPN_CLIENTS_DIR}/alice.ovpn"
    [ -f "${profile}" ]
    grep -q "<ca>" "${profile}"
    grep -q "<cert>" "${profile}"
    grep -q "<key>" "${profile}"
    grep -q "<tls-crypt>" "${profile}"
}

@test "ovpn_client_create: copia o perfil para o home do operador" {
    ovpn_client_create alice
    [ -f "${OVPN_HOME_DIR}/alice.ovpn" ]
}

@test "ovpn_client_create: inclui 'remote' e 'remote-cert-tls server'" {
    ovpn_client_create alice
    local profile="${OVPN_CLIENTS_DIR}/alice.ovpn"
    grep -q "remote vpn.exemplo.com 1194" "${profile}"
    grep -q "remote-cert-tls server" "${profile}"
}

@test "ovpn_client_qr: usa o qrencode quando disponível" {
    ovpn_client_create alice
    run ovpn_client_qr alice
    [ "$status" -eq 0 ]
    run stub_calls qrencode
    [[ "$output" == *"ANSIUTF8"* ]]
}

@test "ovpn_client_qr: pula com aviso quando o qrencode não está disponível" {
    ovpn_client_create alice
    _ovpn_has_qrencode() { return 1; }
    run --separate-stderr ovpn_client_qr alice
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"qrencode"* ]]
}

@test "ovpn_client_list: mostra o cliente e seu IP fixo" {
    ovpn_client_create alice
    run ovpn_client_list
    [[ "$output" == *"alice"* ]]
    [[ "$output" == *"10.8.0."* ]]
}

@test "ovpn_action_add_client: cria o perfil pelo controller" {
    run ovpn_action_add_client bob
    [ "$status" -eq 0 ]
    [ -f "${OVPN_CLIENTS_DIR}/bob.ovpn" ]
}

@test "ovpn_action_add_client: nome vazio é recusado" {
    run ovpn_action_add_client ""
    [ "$status" -ne 0 ]
}
