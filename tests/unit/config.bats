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
