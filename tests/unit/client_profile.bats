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
    load_lib config
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

@test "ovpn_client_routing_block full: redirect-gateway + DNS + block-outside-dns" {
    run ovpn_client_routing_block full
    [[ "$output" == *"redirect-gateway def1"* ]]
    [[ "$output" == *"dhcp-option DNS"* ]]
    [[ "$output" == *"setenv opt block-outside-dns"* ]]
}

@test "ovpn_client_routing_block split: emite só as rotas informadas" {
    run ovpn_client_routing_block split "10.0.0.0 255.255.255.0,192.168.1.0 255.255.255.0"
    [[ "$output" == *"route 10.0.0.0 255.255.255.0"* ]]
    [[ "$output" == *"route 192.168.1.0 255.255.255.0"* ]]
    [[ "$output" != *"redirect-gateway"* ]]
}

@test "ovpn_client_routing_block default: não emite nada" {
    run ovpn_client_routing_block default
    [ -z "$output" ]
}

@test "ovpn_client_create full: .ovpn força tudo pela VPN (redirect-gateway + block-outside-dns)" {
    ovpn_client_create alice full
    grep -q "redirect-gateway def1" "${OVPN_CLIENTS_DIR}/alice.ovpn"
    grep -q "block-outside-dns" "${OVPN_CLIENTS_DIR}/alice.ovpn"
}

@test "ovpn_client_create: regerar com novo modo atualiza o .ovpn" {
    ovpn_client_create alice default
    ! grep -q redirect-gateway "${OVPN_CLIENTS_DIR}/alice.ovpn"
    ovpn_client_create alice full
    grep -q redirect-gateway "${OVPN_CLIENTS_DIR}/alice.ovpn"
}

@test "ovpn_client_create: inclui 'remote' e 'remote-cert-tls server'" {
    ovpn_client_create alice
    local profile="${OVPN_CLIENTS_DIR}/alice.ovpn"
    grep -q "remote vpn.exemplo.com 1194" "${profile}"
    grep -q "remote-cert-tls server" "${profile}"
}

@test "ovpn_client_qr: salva PNG e mostra versão compacta (UTF8) no terminal" {
    ovpn_client_create alice
    run ovpn_client_qr alice
    [ "$status" -eq 0 ]
    [ -f "${OVPN_HOME_DIR}/alice.png" ]
    run stub_calls qrencode
    [[ "$output" == *"UTF8"* ]]
    [[ "$output" == *"-o"* ]]
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

@test "ovpn_action_add_client: escolher full no menu gera .ovpn full-tunnel" {
    # stdin: '2' (full) + 'n' (não gerar QR)
    run ovpn_action_add_client zara <<< $'2\nn'
    [ "$status" -eq 0 ]
    grep -q "redirect-gateway def1" "${OVPN_CLIENTS_DIR}/zara.ovpn"
}

@test "_ovpn_ensure_remote_host: pergunta e salva quando não há host" {
    export OVPN_REMOTE_HOST="${OVPN_REMOTE_HOST_PLACEHOLDER}"
    run _ovpn_ensure_remote_host <<< "meuhub.exemplo.com"
    [ "$status" -eq 0 ]
    [ "$(ovpn_config_get OVPN_REMOTE_HOST)" = "meuhub.exemplo.com" ]
}

@test "ovpn_client_revoke: remove o ccd e o perfil do cliente" {
    ovpn_client_create alice
    [ -f "${OVPN_CLIENTS_DIR}/alice.ovpn" ]
    ovpn_client_revoke alice
    [ ! -f "${OVPN_SERVER_DIR}/ccd/alice" ]
    [ ! -f "${OVPN_CLIENTS_DIR}/alice.ovpn" ]
    [ ! -f "${OVPN_HOME_DIR}/alice.ovpn" ]
}
