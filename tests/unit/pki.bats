#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
    load_lib log
    load_lib pki
}

@test "ovpn_pki_build_ca: cria o certificado da CA" {
    _ovpn_pki_gen_ca_key()  { printf 'FAKE-KEY\n' > "$1"; }
    _ovpn_pki_gen_ca_cert() { printf 'FAKE-CA\n' > "$2"; }
    run ovpn_pki_build_ca
    [ "$status" -eq 0 ]
    [ -f "${OVPN_PKI_DIR}/ca.crt" ]
}

@test "ovpn_pki_build_ca: é idempotente (não recria a CA existente)" {
    _ovpn_pki_gen_ca_key()  { printf 'K\n' > "$1"; }
    _ovpn_pki_gen_ca_cert() { printf 'CA-IDENTIDADE-ORIGINAL\n' > "$2"; }
    ovpn_pki_build_ca
    local first
    first="$(cat "${OVPN_PKI_DIR}/ca.crt")"

    # Se a segunda execução chamasse o seam, o conteúdo mudaria:
    _ovpn_pki_gen_ca_cert() { printf 'OUTRA-CA\n' > "$2"; }
    run ovpn_pki_build_ca
    [ "$status" -eq 0 ]
    [ "$(cat "${OVPN_PKI_DIR}/ca.crt")" = "${first}" ]
}

@test "ovpn_pki_build_ca: gera a chave da CA com curva prime256v1" {
    # Sem override dos seams: usa o stub de openssl, que registra os comandos.
    run ovpn_pki_build_ca
    [ "$status" -eq 0 ]
    run stub_calls openssl
    [[ "$output" == *"prime256v1"* ]]
}

@test "ovpn_pki_gen_tls_crypt: cria a chave tls-crypt" {
    _ovpn_pki_gen_tls_crypt_key() { printf 'TC\n' > "$1"; }
    run ovpn_pki_gen_tls_crypt
    [ "$status" -eq 0 ]
    [ -f "${OVPN_PKI_DIR}/tls-crypt.key" ]
}

@test "ovpn_pki_gen_tls_crypt: usa 'openvpn --genkey'" {
    run ovpn_pki_gen_tls_crypt
    [ "$status" -eq 0 ]
    run stub_calls openvpn
    [[ "$output" == *"--genkey"* ]]
}

@test "ovpn_pki_issue_client: cria o certificado do cliente" {
    _ovpn_pki_gen_ca_key()       { printf 'K\n' > "$1"; }
    _ovpn_pki_gen_ca_cert()      { printf 'CA\n' > "$2"; }
    _ovpn_pki_gen_entity_key()   { printf 'EK\n' > "$1"; }
    _ovpn_pki_sign_entity()      { printf 'CERT\n' > "$2"; }
    ovpn_pki_build_ca
    run ovpn_pki_issue_client alice
    [ "$status" -eq 0 ]
    [ -f "${OVPN_PKI_DIR}/issued/alice.crt" ]
}

@test "ovpn_pki_issue_client: é idempotente" {
    _ovpn_pki_gen_ca_key()       { printf 'K\n' > "$1"; }
    _ovpn_pki_gen_ca_cert()      { printf 'CA\n' > "$2"; }
    _ovpn_pki_gen_entity_key()   { printf 'EK\n' > "$1"; }
    _ovpn_pki_sign_entity()      { printf 'CERT-ORIGINAL\n' > "$2"; }
    ovpn_pki_build_ca
    ovpn_pki_issue_client alice
    local first
    first="$(cat "${OVPN_PKI_DIR}/issued/alice.crt")"
    _ovpn_pki_sign_entity()      { printf 'OUTRO\n' > "$2"; }
    run ovpn_pki_issue_client alice
    [ "$status" -eq 0 ]
    [ "$(cat "${OVPN_PKI_DIR}/issued/alice.crt")" = "${first}" ]
}

@test "ovpn_pki_issue_client: assina o certificado com a CA" {
    # Sem override do seam de assinatura: usa o stub de openssl.
    _ovpn_pki_gen_ca_key()  { printf 'K\n' > "$1"; }
    _ovpn_pki_gen_ca_cert() { printf 'CA\n' > "$2"; }
    ovpn_pki_build_ca
    run ovpn_pki_issue_client bob
    [ "$status" -eq 0 ]
    run stub_calls openssl
    [[ "$output" == *"-CA"* ]]
    [[ "$output" == *"ca.crt"* ]]
}

@test "ovpn_pki_issue_server: cria o certificado do servidor" {
    _ovpn_pki_gen_ca_key()       { printf 'K\n' > "$1"; }
    _ovpn_pki_gen_ca_cert()      { printf 'CA\n' > "$2"; }
    _ovpn_pki_gen_entity_key()   { printf 'EK\n' > "$1"; }
    _ovpn_pki_sign_entity()      { printf 'CERT\n' > "$2"; }
    ovpn_pki_build_ca
    run ovpn_pki_issue_server server
    [ "$status" -eq 0 ]
    [ -f "${OVPN_PKI_DIR}/issued/server.crt" ]
}

@test "_ovpn_pki_ext_content: servidor tem keyUsage + serverAuth; cliente tem clientAuth" {
    run _ovpn_pki_ext_content server
    [[ "$output" == *"keyUsage=digitalSignature,keyEncipherment"* ]]
    [[ "$output" == *"extendedKeyUsage=serverAuth"* ]]

    run _ovpn_pki_ext_content client
    [[ "$output" == *"keyUsage=digitalSignature"* ]]
    [[ "$output" == *"extendedKeyUsage=clientAuth"* ]]
}

@test "ovpn_pki_revoke_client: registra a revogação e atualiza a CRL" {
    _ovpn_pki_gen_crl() { printf 'CRL\n' > "$(ovpn_pki_crl_path)"; }
    run ovpn_pki_revoke_client alice
    [ "$status" -eq 0 ]
    [ -f "$(ovpn_pki_crl_path)" ]
    grep -q alice "${OVPN_PKI_DIR}/revoked.index"
}

@test "ovpn_pki_export_ca/import_ca: round-trip preserva a identidade da CA" {
    _ovpn_pki_gen_ca_key()        { printf 'K\n' > "$1"; }
    _ovpn_pki_gen_ca_cert()       { printf 'CA-IDENTIDADE-XYZ\n' > "$2"; }
    _ovpn_pki_gen_tls_crypt_key() { printf 'TC\n' > "$1"; }
    ovpn_pki_build_ca
    ovpn_pki_gen_tls_crypt
    local before
    before="$(sha256sum "${OVPN_PKI_DIR}/ca.crt" | cut -d' ' -f1)"

    local bundle="${BATS_TEST_TMPDIR}/ca-bundle.tar.gz"
    ovpn_pki_export_ca "${bundle}"
    [ -f "${bundle}" ]

    # Importa num diretório de PKI diferente (simula o segundo hub).
    export OVPN_PKI_DIR="${BATS_TEST_TMPDIR}/pki2"
    ovpn_pki_import_ca "${bundle}"
    local after
    after="$(sha256sum "${OVPN_PKI_DIR}/ca.crt" | cut -d' ' -f1)"
    [ "${before}" = "${after}" ]
}
