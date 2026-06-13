#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
    load_lib log
    load_lib ui
    load_lib deps
}

@test "ovpn_deps_missing: lista apenas os pacotes não instalados" {
    # Simula: 'openvpn' instalado, o resto faltando.
    _ovpn_pkg_installed() { [[ "$1" == "openvpn" ]]; }
    run ovpn_deps_missing openvpn qrencode easy-rsa
    [ "$status" -eq 0 ]
    [[ "$output" == *"qrencode"* ]]
    [[ "$output" == *"easy-rsa"* ]]
    [[ "$output" != *"openvpn"* ]]
}

@test "ovpn_deps_ensure: nada a fazer quando tudo já está instalado" {
    _ovpn_pkg_installed() { return 0; }
    run ovpn_deps_ensure openvpn <<< "n"
    [ "$status" -eq 0 ]
    run stub_calls apt-get
    [ -z "$output" ]
}

@test "ovpn_deps_ensure: mostra o que falta e o comando apt antes de instalar" {
    _ovpn_pkg_installed() { return 1; }
    # Recusa a instalação, mas o plano deve ter sido exibido.
    run ovpn_deps_ensure openvpn <<< "n"
    [[ "$output" == *"openvpn"* ]]
    [[ "$output" == *"apt-get install"* ]]
}

@test "ovpn_deps_ensure: NÃO instala quando o operador recusa" {
    _ovpn_pkg_installed() { return 1; }
    run ovpn_deps_ensure openvpn <<< "n"
    [ "$status" -ne 0 ]
    run stub_calls apt-get
    [ -z "$output" ]
}

@test "ovpn_deps_ensure: instala via apt após confirmação" {
    _ovpn_pkg_installed() { return 1; }
    run ovpn_deps_ensure openvpn qrencode <<< "s"
    [ "$status" -eq 0 ]
    run stub_calls apt-get
    [[ "$output" == *"install -y openvpn qrencode"* ]]
}

@test "ovpn_deps_ensure: recusa pacote lançado há menos de 7 dias (regra dos 7 dias)" {
    _ovpn_pkg_installed() { return 1; }
    _ovpn_pkg_age_days() { echo 3; }   # novo demais
    run --separate-stderr ovpn_deps_ensure openvpn <<< "s"
    [ "$status" -ne 0 ]
    [[ "$stderr" == *"7 dias"* ]]
    run stub_calls apt-get
    [ -z "$output" ]   # não instalou
}
