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

@test "ovpn_link_render_core: entrega o espaço de clientes ao spoke (iroute no ccd DEFAULT)" {
    # Sem iroute, o OpenVPN-core não sabe a qual cliente entregar os /32 atrás do
    # spoke (identidade do outro hub, clientes em roam) e os descarta.
    export OVPN_SUBNET_V4=10.80.0.0
    export OVPN_NETMASK_V4=255.255.255.0
    ovpn_link_render_core 1195
    local c="$(ovpn_link_conf_path_core)" d
    d="$(ovpn_link_ccd_dir)"
    grep -q "^client-config-dir ${d}\$" "${c}"
    [ -f "${d}/DEFAULT" ]
    grep -q '^iroute 10.80.0.0 255.255.255.0$' "${d}/DEFAULT"
    # Com client-to-client, o iroute do /24 mascararia os endereços LOCAIS do
    # core (sua identidade, seus clientes) como se estivessem atrás do spoke —
    # o core deixaria de entregá-los. Sem ele, a entrada cai no kernel (que sabe
    # o que é local pelo OSPF/connected); o iroute fica só p/ a saída core->spoke.
    ! grep -q '^client-to-client$' "${c}"
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
