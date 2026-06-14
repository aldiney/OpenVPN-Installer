#!/usr/bin/env bats
# Verifica que o install.sh resolve corretamente o diretório dos módulos quando
# chamado por um symlink (caso do comando 'openvpn-installer' em /usr/local/bin).

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
}

@test "install.sh via symlink: carrega lib/ do alvo (não do dir do symlink)" {
    local link="${BATS_TEST_TMPDIR}/openvpn-installer"
    ln -s "${PROJECT_ROOT}/install.sh" "${link}"

    # Roda via symlink. Como não somos root, deve falhar em require_root —
    # mas NUNCA por não achar lib/core.sh.
    run bash "${link}"
    [[ "$output" != *"lib/core.sh"* ]]
    [[ "$output" != *"No such file"* ]]
    # Chegou a carregar os módulos e parou no require_root (mensagem em pt-BR).
    [[ "$output" == *"root"* ]]
}
