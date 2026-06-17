#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
    load_lib log
    load_lib pki
    load_lib link

    _ovpn_pki_gen_ca_key()        { printf 'CA-KEY\n' > "$1"; }
    _ovpn_pki_gen_ca_cert()       { printf 'CA-CERT\n' > "$2"; }
    _ovpn_pki_gen_entity_key()    { printf 'ENT-KEY\n' > "$1"; }
    _ovpn_pki_sign_entity()       { printf 'ENT-CERT\n' > "$2"; }
    _ovpn_pki_gen_tls_crypt_key() { printf 'TLS-CRYPT\n' > "$1"; }
    ovpn_pki_build_ca >/dev/null
    ovpn_pki_gen_tls_crypt
}

@test "ovpn_link_render_core: gera o link-server dedicado (ovpn-link, transporte, cert link-core)" {
    ovpn_link_render_core 1195
    local c="$(ovpn_link_conf_path_core)"
    [ -f "${c}" ]
    grep -q '^dev ovpn-link$' "${c}"
    grep -q '^dev-type tun$' "${c}"
    grep -q '^port 1195$' "${c}"
    grep -q '^server 10.255.0.0 255.255.255.0$' "${c}"
    grep -q 'issued/link-core.crt' "${c}"
    grep -q '^tls-crypt ' "${c}"
    [ -f "${OVPN_PKI_DIR}/issued/link-core.crt" ]
}

@test "ovpn_link_render_spoke: gera o link-client dedicado (remote core, ovpn-link, cert próprio)" {
    ovpn_link_render_spoke hubA.exemplo.com 1195 link-hub2
    local c="$(ovpn_link_conf_path_spoke)"
    [ -f "${c}" ]
    grep -q '^client$' "${c}"
    grep -q '^dev ovpn-link$' "${c}"
    grep -q '^remote hubA.exemplo.com 1195$' "${c}"
    grep -q '^remote-cert-tls server$' "${c}"
    grep -q 'issued/link-hub2.crt' "${c}"
    [ -f "${OVPN_PKI_DIR}/issued/link-hub2.crt" ]
}

@test "ovpn_link_render_spoke: sem host do core, aborta" {
    run ovpn_link_render_spoke "" 1195
    [ "$status" -ne 0 ]
}
