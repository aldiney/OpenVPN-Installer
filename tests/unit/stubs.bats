#!/usr/bin/env bats
# Valida o harness de mocking que os demais testes usarão para substituir
# comandos de sistema (apt-get, openvpn, openssl...) sem efeitos reais.

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
}

@test "harness de stubs: o stub registra os argumentos recebidos" {
    run apt-get install -y openvpn
    [ "$status" -eq 0 ]

    run stub_calls apt-get
    [[ "$output" == *"install -y openvpn"* ]]
}

@test "harness de stubs: STUB_APT_GET_EXIT permite simular falha" {
    STUB_APT_GET_EXIT=1 run apt-get update
    [ "$status" -eq 1 ]
}
