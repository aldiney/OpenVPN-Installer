#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
    load_lib config
}

@test "ovpn_config_set/get: persiste e lê o valor" {
    ovpn_config_set OVPN_REMOTE_HOST vpn.exemplo.com
    [ "$(ovpn_config_get OVPN_REMOTE_HOST)" = "vpn.exemplo.com" ]
}

@test "ovpn_config_set: atualiza sem duplicar a chave" {
    ovpn_config_set OVPN_REMOTE_HOST a.exemplo.com
    ovpn_config_set OVPN_REMOTE_HOST b.exemplo.com
    [ "$(ovpn_config_get OVPN_REMOTE_HOST)" = "b.exemplo.com" ]
    [ "$(grep -c '^OVPN_REMOTE_HOST=' "$(ovpn_config_path)")" -eq 1 ]
}

@test "ovpn_config_get: vazio quando a chave não existe" {
    [ -z "$(ovpn_config_get NAO_EXISTE)" ]
}

@test "ovpn_config_apply: carrega a sub-rede persistida e deriva o prefixo" {
    ovpn_config_set OVPN_SUBNET_V4 10.8.7.0
    ovpn_config_apply
    [ "${OVPN_SUBNET_V4}" = "10.8.7.0" ]
    [ "${OVPN_VPN_PREFIX_V4}" = "10.8.7" ]
}

@test "ovpn_config_apply: carrega a máscara persistida (espaço amplo)" {
    ovpn_config_set OVPN_NETMASK_V4 255.255.252.0
    ovpn_config_apply
    [ "${OVPN_NETMASK_V4}" = "255.255.252.0" ]
}

@test "ovpn_config_apply: carrega os hosts do hub persistidos" {
    ovpn_config_set OVPN_REMOTE_HOST vpn.exemplo.com
    ovpn_config_set OVPN_REMOTE_HOST_2 vpn2.exemplo.com
    ovpn_config_apply
    [ "${OVPN_REMOTE_HOST}" = "vpn.exemplo.com" ]
    [ "${OVPN_REMOTE_HOST_2}" = "vpn2.exemplo.com" ]
}

@test "ovpn_config_apply: sem config persistido, não falha" {
    run ovpn_config_apply
    [ "$status" -eq 0 ]
}
