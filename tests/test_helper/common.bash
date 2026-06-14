#!/usr/bin/env bash
# Utilitários compartilhados pelos testes bats.
#
# Cada teste chama `common_setup` no seu setup(). Isso:
#   - descobre a raiz do projeto (PROJECT_ROOT);
#   - aponta as constantes de caminho para um sandbox em $BATS_TEST_TMPDIR
#     (nenhum teste toca /etc, /home ou o sistema real);
#   - coloca os stubs à frente do PATH (apt, openvpn, openssl... substituídos).
#
# Depois, `load_lib <nome>` carrega o módulo de lib/ sob teste.

common_setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    export PROJECT_ROOT

    # Sandbox de caminhos — sobrepõe os padrões dos módulos.
    export OVPN_ETC="${BATS_TEST_TMPDIR}/etc/openvpn"
    export OVPN_SERVER_DIR="${OVPN_ETC}/server"
    export OVPN_PKI_DIR="${OVPN_ETC}/pki"
    export OVPN_CLIENTS_DIR="${OVPN_ETC}/clients"
    export OVPN_HOME_DIR="${BATS_TEST_TMPDIR}/home"
    export OVPN_SYSCTL_FILE="${BATS_TEST_TMPDIR}/sysctl.conf"

    # Onde os stubs registram os argumentos que recebem.
    export STUB_CALLS_DIR="${BATS_TEST_TMPDIR}/calls"
    mkdir -p "${STUB_CALLS_DIR}"

    PATH="${PROJECT_ROOT}/tests/test_helper/stubs:${PATH}"
    export PATH
}

# Carrega um módulo de lib/ no shell do teste.
load_lib() {
    # shellcheck disable=SC1090
    source "${PROJECT_ROOT}/lib/${1}.sh"
}

# Retorna o que um stub registrou (uma chamada por linha).
stub_calls() {
    cat "${STUB_CALLS_DIR}/${1}" 2>/dev/null || true
}
