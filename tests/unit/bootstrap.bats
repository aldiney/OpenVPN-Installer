#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    # Carrega as funções do bootstrap sem executar o main (guardado por BASH_SOURCE).
    source "${PROJECT_ROOT}/bootstrap.sh"
}

@test "bootstrap_ensure_tools: nada a fazer quando git e gh já existem" {
    _bootstrap_cmd_exists() { return 0; }
    run bootstrap_ensure_tools
    [ "$status" -eq 0 ]
    run stub_calls apt-get
    [ -z "$output" ]
}

@test "bootstrap_ensure_tools: instala via apt após confirmação" {
    _bootstrap_cmd_exists() { return 1; }
    run bootstrap_ensure_tools <<< "s"
    [ "$status" -eq 0 ]
    run stub_calls apt-get
    [[ "$output" == *"install -y git gh"* ]]
}

@test "bootstrap_ensure_tools: não instala se o operador recusar" {
    _bootstrap_cmd_exists() { return 1; }
    run bootstrap_ensure_tools <<< "n"
    [ "$status" -ne 0 ]
    run stub_calls apt-get
    [ -z "$output" ]
}

@test "bootstrap_auth_github: chama 'gh auth login' quando não autenticado" {
    export STUB_GH_AUTH_STATUS_EXIT=1
    run bootstrap_auth_github
    [ "$status" -eq 0 ]
    run stub_calls gh
    [[ "$output" == *"auth login"* ]]
}

@test "bootstrap_clone: clona o repo quando o destino não é um git" {
    export OVPN_TARGET_DIR="${BATS_TEST_TMPDIR}/destino"
    run bootstrap_clone
    [ "$status" -eq 0 ]
    run stub_calls gh
    [[ "$output" == *"repo clone"* ]]
}
