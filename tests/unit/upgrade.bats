#!/usr/bin/env bats

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
    load_lib firewall
    load_lib upgrade

    # require_root passa (testes rodam sem root).
    _ovpn_current_uid() { printf '0'; }
}

# Semeia uma instalação: CA, cert do servidor (sem KU), 1 cliente e o server.conf.
seed_deployment() {
    mkdir -p "${OVPN_PKI_DIR}/issued" "${OVPN_PKI_DIR}/private" \
             "${OVPN_CLIENTS_DIR}" "${OVPN_SERVER_DIR}/ccd"
    printf 'CA-CERT\n'      > "${OVPN_PKI_DIR}/ca.crt"
    printf 'CA-KEY\n'       > "${OVPN_PKI_DIR}/private/ca.key"
    printf 'OLD-SRV-CERT\n' > "${OVPN_PKI_DIR}/issued/server.crt"
    printf 'OLD-SRV-KEY\n'  > "${OVPN_PKI_DIR}/private/server.key"
    printf 'ALICE-CERT\n'   > "${OVPN_PKI_DIR}/issued/alice.crt"
    printf 'ALICE-KEY\n'    > "${OVPN_PKI_DIR}/private/alice.key"
    printf 'client\nremote x 1194\n' > "${OVPN_CLIENTS_DIR}/alice.ovpn"
    printf 'ifconfig-push 10.8.0.2 255.255.255.0\n' > "${OVPN_SERVER_DIR}/ccd/alice"
    printf 'dev tun\nproto udp\nport 1194\nserver 10.8.0.0 255.255.255.0\n' \
        > "$(ovpn_server_conf_path)"
}

@test "_ovpn_upgrade_read_stamp: 0 quando ausente; preserva quando gravado" {
    [ "$(_ovpn_upgrade_read_stamp)" = "0" ]
    _ovpn_upgrade_write_stamp 2
    [ "$(_ovpn_upgrade_read_stamp)" = "2" ]
}

@test "_ovpn_upgrade_read_stamp: 0 quando carimbo está corrompido" {
    mkdir -p "${OVPN_ETC}"
    printf 'lixo\n' > "$(ovpn_upgrade_stamp_path)"
    [ "$(_ovpn_upgrade_read_stamp)" = "0" ]
}

@test "_ovpn_upgrade_should_offer: sem instalação, não oferece" {
    run _ovpn_upgrade_should_offer
    [ "$status" -ne 0 ]
}

@test "_ovpn_upgrade_should_offer: instalação antiga oferece; atual não" {
    seed_deployment
    run _ovpn_upgrade_should_offer
    [ "$status" -eq 0 ]
    _ovpn_upgrade_write_stamp "${OVPN_SCHEMA_VERSION}"
    run _ovpn_upgrade_should_offer
    [ "$status" -ne 0 ]
}

@test "ovpn_upgrade_run: sem instalação, no-op e não carimba" {
    run ovpn_upgrade_run
    [ "$status" -eq 0 ]
    [ ! -f "$(ovpn_upgrade_stamp_path)" ]
}

@test "migração mssfix: adiciona quando falta; idempotente quando já tem" {
    seed_deployment
    _ovpn_upgrade_cert_has_ku() { return 0; }   # não mexe no cert
    _ovpn_upgrade_port_is_open() { return 0; }  # não mexe no firewall
    run ovpn_upgrade_run
    [ "$status" -eq 0 ]
    grep -qE '^mssfix ' "$(ovpn_server_conf_path)"
    # 2ª execução: nada muda (idempotente), sem restart
    : > "${STUB_CALLS_DIR}/systemctl" 2>/dev/null || true
    run ovpn_upgrade_run
    run stub_calls systemctl
    [ -z "$output" ]
}

@test "migração firewall: lê a porta do server.conf (não dos defaults)" {
    seed_deployment
    # porta não-padrão no conf
    printf 'dev tun\nproto tcp\nport 1195\nserver 10.8.0.0 255.255.255.0\nmssfix 1420\n' \
        > "$(ovpn_server_conf_path)"
    _ovpn_upgrade_cert_has_ku() { return 0; }
    _ovpn_firewall_backend() { printf 'nft'; }
    _ovpn_upgrade_port_is_open() { return 1; }   # fechada
    run ovpn_upgrade_run
    [ "$status" -eq 0 ]
    run stub_calls nft
    [[ "$output" == *"1195"* ]]
}

@test "migração cert: reemite o cert do servidor SEM tocar CA nem clientes" {
    seed_deployment
    _ovpn_pki_gen_entity_key() { printf 'NEW-KEY\n' > "$1"; }
    _ovpn_pki_sign_entity()    { printf 'NEW-SRV-CERT-COM-KU\n' > "$2"; }
    _ovpn_upgrade_cert_has_ku() { return 1; }    # falta KU
    _ovpn_upgrade_port_is_open() { return 0; }

    local ca_before client_before server_before
    ca_before="$(sha256sum "${OVPN_PKI_DIR}/ca.crt" "${OVPN_PKI_DIR}/private/ca.key")"
    client_before="$(sha256sum "${OVPN_PKI_DIR}/issued/alice.crt" "${OVPN_PKI_DIR}/private/alice.key" "${OVPN_CLIENTS_DIR}/alice.ovpn" "${OVPN_SERVER_DIR}/ccd/alice")"
    server_before="$(sha256sum "${OVPN_PKI_DIR}/issued/server.crt")"

    run ovpn_upgrade_run
    [ "$status" -eq 0 ]

    [ "$(sha256sum "${OVPN_PKI_DIR}/ca.crt" "${OVPN_PKI_DIR}/private/ca.key")" = "${ca_before}" ]
    [ "$(sha256sum "${OVPN_PKI_DIR}/issued/alice.crt" "${OVPN_PKI_DIR}/private/alice.key" "${OVPN_CLIENTS_DIR}/alice.ovpn" "${OVPN_SERVER_DIR}/ccd/alice")" = "${client_before}" ]
    [ "$(sha256sum "${OVPN_PKI_DIR}/issued/server.crt")" != "${server_before}" ]
}

@test "ovpn_upgrade_run: reinicia o serviço quando algo mudou; carimba a versão" {
    seed_deployment
    _ovpn_upgrade_cert_has_ku() { return 0; }
    _ovpn_upgrade_port_is_open() { return 0; }
    run ovpn_upgrade_run                 # mssfix faltando -> muda
    [ "$status" -eq 0 ]
    run stub_calls systemctl
    [[ "$output" == *"restart openvpn-server@server"* ]]
    [ "$(_ovpn_upgrade_read_stamp)" = "${OVPN_SCHEMA_VERSION}" ]
}

@test "migração cert: openssl indeterminado pula com aviso (não reemite)" {
    seed_deployment
    _ovpn_upgrade_cert_has_ku() { return 2; }    # indeterminado
    _ovpn_upgrade_port_is_open() { return 0; }
    local server_before
    server_before="$(sha256sum "${OVPN_PKI_DIR}/issued/server.crt")"
    run ovpn_upgrade_run
    [ "$status" -eq 0 ]
    [ "$(sha256sum "${OVPN_PKI_DIR}/issued/server.crt")" = "${server_before}" ]
}

@test "ovpn_upgrade_report: avisa sobre redirect-gateway global (sem alterar)" {
    seed_deployment
    printf 'push "redirect-gateway def1"\n' >> "$(ovpn_server_conf_path)"
    local before
    before="$(sha256sum "$(ovpn_server_conf_path)")"
    run --separate-stderr ovpn_upgrade_report
    [[ "$stderr" == *"redirect-gateway"* ]]
    [ "$(sha256sum "$(ovpn_server_conf_path)")" = "${before}" ]
}
