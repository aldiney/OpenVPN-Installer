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

@test "ovpn_hub_export_master: o bundle inclui a ca.key (CA mestra)" {
    local bundle="${BATS_TEST_TMPDIR}/m.tar.gz"
    ovpn_hub_export_master "${bundle}"
    run tar tzf "${bundle}"
    [[ "$output" == *"ca.key"* ]]
    [[ "$output" == *"ca.crt"* ]]
    [[ "$output" == *"tls-crypt.key"* ]]
}

@test "ovpn_hub_export: NÃO inclui a ca.key (só a identidade pública da CA)" {
    local bundle="${BATS_TEST_TMPDIR}/p.tar.gz"
    ovpn_hub_export "${bundle}"
    run tar tzf "${bundle}"
    [[ "$output" != *"ca.key"* ]]
}

@test "ovpn_hub_export_master/import: o hub B recebe a ca.key idêntica" {
    local bundle="${BATS_TEST_TMPDIR}/m.tar.gz"
    ovpn_hub_export_master "${bundle}"
    local before
    before="$(sha256sum "$(ovpn_pki_ca_key)" | cut -d' ' -f1)"

    export OVPN_PKI_DIR="${BATS_TEST_TMPDIR}/pkiB"
    ovpn_hub_import "${bundle}"
    [ -f "$(ovpn_pki_ca_key)" ]
    local after
    after="$(sha256sum "$(ovpn_pki_ca_key)" | cut -d' ' -f1)"
    [ "${before}" = "${after}" ]
}

@test "ovpn_hub_import: recusa bundle mestra com a ca.key adulterada" {
    local bundle="${BATS_TEST_TMPDIR}/m.tar.gz"
    ovpn_hub_export_master "${bundle}"

    local t="${BATS_TEST_TMPDIR}/tamper"
    mkdir -p "${t}"
    tar xzf "${bundle}" -C "${t}"
    printf 'ROUBADA\n' > "${t}/ca.key"
    ( cd "${t}" && tar czf "${bundle}" ca.crt ca.key tls-crypt.key manifest checksum.sha256 )

    export OVPN_PKI_DIR="${BATS_TEST_TMPDIR}/pkiX"
    run ovpn_hub_import "${bundle}"
    [ "$status" -ne 0 ]
}

@test "ovpn_hub_import: bundle mestra invalida o cert de servidor antigo (força reemissão)" {
    local bundle="${BATS_TEST_TMPDIR}/m.tar.gz"
    ovpn_hub_export_master "${bundle}"

    export OVPN_PKI_DIR="${BATS_TEST_TMPDIR}/pkiB"
    mkdir -p "${OVPN_PKI_DIR}/issued" "${OVPN_PKI_DIR}/private"
    printf 'CERT-ANTIGO\n' > "${OVPN_PKI_DIR}/issued/server.crt"
    printf 'KEY-ANTIGA\n'  > "${OVPN_PKI_DIR}/private/server.key"
    ovpn_hub_import "${bundle}"
    [ ! -f "${OVPN_PKI_DIR}/issued/server.crt" ]
    [ ! -f "${OVPN_PKI_DIR}/private/server.key" ]
}

@test "ovpn_hub_import: bundle público avisa que o hub não pode emitir certs" {
    local bundle="${BATS_TEST_TMPDIR}/p.tar.gz"
    ovpn_hub_export "${bundle}"
    export OVPN_PKI_DIR="${BATS_TEST_TMPDIR}/pkiP"
    run ovpn_hub_import "${bundle}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NÃO pode emitir"* ]]
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
