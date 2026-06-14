#!/usr/bin/env bats
# Fluxo ponta a ponta (sobre stubs): instalar o hub single-server.

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
    load_lib log
    load_lib ui
    load_lib pki
    load_lib wizard_ipproto
    load_lib server_config
    load_lib ccd
    load_lib deps
    load_lib firewall
    load_lib upgrade
    load_lib controller
}

# Substitui os seams de criptografia (não dependemos de cripto real aqui),
# trata as dependências como já instaladas (sem apt) e força o backend de
# firewall para nft (que tem stub).
fake_pki_seams() {
    _ovpn_pki_gen_ca_key()        { printf 'K\n' > "$1"; }
    _ovpn_pki_gen_ca_cert()       { printf 'CA\n' > "$2"; }
    _ovpn_pki_gen_entity_key()    { printf 'EK\n' > "$1"; }
    _ovpn_pki_sign_entity()       { printf 'CERT\n' > "$2"; }
    _ovpn_pki_gen_tls_crypt_key() { printf 'TC\n' > "$1"; }
    _ovpn_pkg_installed()         { return 0; }
    _ovpn_firewall_backend()      { printf 'nft'; }
}

@test "instalar hub: gera a config e habilita o serviço (fluxo completo)" {
    fake_pki_seams
    run ovpn_action_install_hub ipv4
    [ "$status" -eq 0 ]

    [ -f "${OVPN_SERVER_DIR}/server.conf" ]
    grep -q "^client-to-client$" "${OVPN_SERVER_DIR}/server.conf"
    [ -f "${OVPN_PKI_DIR}/ca.crt" ]
    [ -f "${OVPN_PKI_DIR}/issued/server.crt" ]
    [ -f "${OVPN_PKI_DIR}/tls-crypt.key" ]

    run stub_calls systemctl
    [[ "$output" == *"enable"* ]]
    [[ "$output" == *"openvpn-server@server"* ]]
}

@test "instalar hub: garante as dependências (instala faltantes após confirmação)" {
    fake_pki_seams
    _ovpn_pkg_installed() { return 1; }   # openvpn e qrencode faltando
    run ovpn_action_install_hub ipv4 <<< "s"
    [ "$status" -eq 0 ]
    run stub_calls apt-get
    [[ "$output" == *"install -y openvpn qrencode"* ]]
}
