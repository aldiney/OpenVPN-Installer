#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib log
}

@test "ovpn_log_error: escreve a mensagem no stderr" {
    run --separate-stderr ovpn_log_error "deu ruim"
    [[ "$stderr" == *"deu ruim"* ]]
    [ -z "$output" ]
}

@test "ovpn_log_info: escreve a mensagem no stdout" {
    run --separate-stderr ovpn_log_info "ola mundo"
    [[ "$output" == *"ola mundo"* ]]
    [ -z "$stderr" ]
}

@test "ovpn_log_warn: escreve a mensagem no stderr" {
    run --separate-stderr ovpn_log_warn "cuidado"
    [[ "$stderr" == *"cuidado"* ]]
}

@test "ovpn_log_ok: mostra a mensagem sem códigos de cor fora de um terminal" {
    run ovpn_log_ok "concluido"
    [[ "$output" == *"concluido"* ]]
    [[ "$output" != *$'\033'* ]]
}

@test "ovpn_log_step: mostra a mensagem do passo no stdout" {
    run --separate-stderr ovpn_log_step "Etapa 1"
    [[ "$output" == *"Etapa 1"* ]]
}
