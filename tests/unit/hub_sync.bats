#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
    load_lib log
    load_lib pki
    load_lib hub_sync

    _ovpn_pki_gen_ca_key()        { printf 'CA-KEY\n' > "$1"; }
    _ovpn_pki_gen_ca_cert()       { printf 'CA-IDENTIDADE\n' > "$2"; }
    _ovpn_pki_gen_tls_crypt_key() { printf 'TLS-CRYPT\n' > "$1"; }
    ovpn_pki_build_ca >/dev/null
    ovpn_pki_gen_tls_crypt
}

@test "ovpn_hub_export: gera o bundle com ca, tls-crypt, manifest e checksum" {
    local bundle="${BATS_TEST_TMPDIR}/b.tar.gz"
    ovpn_hub_export "${bundle}"
    [ -f "${bundle}" ]
    run tar tzf "${bundle}"
    [[ "$output" == *"ca.crt"* ]]
    [[ "$output" == *"tls-crypt.key"* ]]
    [[ "$output" == *"manifest"* ]]
    [[ "$output" == *"checksum.sha256"* ]]
}

@test "ovpn_hub_export/import: round-trip preserva a identidade da CA" {
    local bundle="${BATS_TEST_TMPDIR}/b.tar.gz"
    ovpn_hub_export "${bundle}"
    local before
    before="$(sha256sum "$(ovpn_pki_ca_cert)" | cut -d' ' -f1)"

    export OVPN_PKI_DIR="${BATS_TEST_TMPDIR}/pki2"
    ovpn_hub_import "${bundle}"
    local after
    after="$(sha256sum "$(ovpn_pki_ca_cert)" | cut -d' ' -f1)"
    [ "${before}" = "${after}" ]
}

@test "ovpn_hub_import: recusa bundle adulterado (checksum inválido)" {
    local bundle="${BATS_TEST_TMPDIR}/b.tar.gz"
    ovpn_hub_export "${bundle}"

    # Adultera o ca.crt dentro do bundle sem atualizar o checksum.
    local t="${BATS_TEST_TMPDIR}/tamper"
    mkdir -p "${t}"
    tar xzf "${bundle}" -C "${t}"
    printf 'ALTERADO\n' > "${t}/ca.crt"
    ( cd "${t}" && tar czf "${bundle}" ca.crt tls-crypt.key manifest checksum.sha256 )

    export OVPN_PKI_DIR="${BATS_TEST_TMPDIR}/pki3"
    run ovpn_hub_import "${bundle}"
    [ "$status" -ne 0 ]
}
