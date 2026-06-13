#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    # Não carregamos o core aqui: cada teste arruma o ambiente antes de carregá-lo.
}

@test "core: caminhos têm padrão sob /etc/openvpn quando nada está definido" {
    unset OVPN_ETC OVPN_SERVER_DIR OVPN_PKI_DIR OVPN_CLIENTS_DIR
    load_lib core
    [ "$OVPN_ETC" = "/etc/openvpn" ]
    [ "$OVPN_SERVER_DIR" = "/etc/openvpn/server" ]
    [ "$OVPN_PKI_DIR" = "/etc/openvpn/pki" ]
    [ "$OVPN_CLIENTS_DIR" = "/etc/openvpn/clients" ]
}

@test "core: deriva os subdiretórios de OVPN_ETC quando ele é sobreposto" {
    unset OVPN_SERVER_DIR OVPN_PKI_DIR OVPN_CLIENTS_DIR
    export OVPN_ETC="/opt/vpn"
    load_lib core
    [ "$OVPN_ETC" = "/opt/vpn" ]
    [ "$OVPN_SERVER_DIR" = "/opt/vpn/server" ]
    [ "$OVPN_PKI_DIR" = "/opt/vpn/pki" ]
    [ "$OVPN_CLIENTS_DIR" = "/opt/vpn/clients" ]
}

@test "ovpn_die: escreve a mensagem no stderr e sai com código diferente de zero" {
    load_lib core
    run --separate-stderr ovpn_die "falha fatal"
    [ "$status" -ne 0 ]
    [[ "$stderr" == *"falha fatal"* ]]
}

@test "ovpn_require_root: falha quando o usuário não é root" {
    load_lib core
    _ovpn_current_uid() { echo 1000; }
    run --separate-stderr ovpn_require_root
    [ "$status" -ne 0 ]
    [[ "$stderr" == *root* ]]
}

@test "ovpn_require_root: passa quando o usuário é root" {
    load_lib core
    _ovpn_current_uid() { echo 0; }
    run ovpn_require_root
    [ "$status" -eq 0 ]
}
