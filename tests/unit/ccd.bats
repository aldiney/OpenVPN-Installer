#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ../test_helper/common

setup() {
    common_setup
    load_lib core
    load_lib ccd
}

@test "ovpn_vpn_prefix: deriva o prefixo /24 (3 primeiros octetos) da sub-rede" {
    [ "$(ovpn_vpn_prefix 10.8.0.0)" = "10.8.0" ]
    [ "$(ovpn_vpn_prefix 192.168.50.0)" = "192.168.50" ]
}

@test "ovpn_ccd_assign: respeita a rede configurada (rede da VPN escolhida)" {
    export OVPN_SUBNET_V4=10.8.9.0
    run ovpn_ccd_assign alice
    [ "$status" -eq 0 ]
    grep -q "ifconfig-push 10.8.9.2 " "${OVPN_SERVER_DIR}/ccd/alice"
}

@test "ovpn_ccd_next_free_ip: aloca além de .254 num /22 (espaço amplo)" {
    export OVPN_SUBNET_V4=10.80.0.0
    export OVPN_NETMASK_V4=255.255.252.0
    mkdir -p "$(ovpn_ccd_dir)"
    local f="$(ovpn_ccd_dir)/seed" i
    for i in $(seq 2 254); do printf 'ifconfig-push 10.80.0.%s 255.255.252.0\n' "$i" >> "$f"; done
    run ovpn_ccd_next_free_ip
    [ "$status" -eq 0 ]
    [ "$output" = "10.80.0.255" ]
}

@test "ovpn_ccd_next_free_ip: respeita o limite da máscara (/29: só .2-.6)" {
    export OVPN_SUBNET_V4=10.80.0.0
    export OVPN_NETMASK_V4=255.255.255.248
    mkdir -p "$(ovpn_ccd_dir)"
    local f="$(ovpn_ccd_dir)/seed" i
    for i in 2 3 4 5 6; do printf 'ifconfig-push 10.80.0.%s 255.255.255.248\n' "$i" >> "$f"; done
    run ovpn_ccd_next_free_ip
    [ "$status" -ne 0 ]
}

@test "ovpn_ccd_readdress: re-endereça preservando o último octeto (/24 -> /22)" {
    mkdir -p "$(ovpn_ccd_dir)"
    printf 'ifconfig-push 10.8.0.5 255.255.255.0\n' > "$(ovpn_ccd_dir)/alice"
    printf 'ifconfig-push 10.8.0.200 255.255.255.0\niroute 10.9.0.0 255.255.255.0\n' > "$(ovpn_ccd_dir)/hub-b"
    ovpn_ccd_readdress 10.8.0.0 255.255.255.0 10.80.0.0 255.255.252.0
    grep -q '^ifconfig-push 10.80.0.5 255.255.252.0$' "$(ovpn_ccd_dir)/alice"
    grep -q '^ifconfig-push 10.80.0.200 255.255.252.0$' "$(ovpn_ccd_dir)/hub-b"
    grep -q '^iroute 10.9.0.0' "$(ovpn_ccd_dir)/hub-b"
    [ -d "$(ovpn_ccd_dir).pre-readdress" ]
}

@test "ovpn_ccd_readdress: idempotente (não re-desloca se já no novo espaço)" {
    mkdir -p "$(ovpn_ccd_dir)"
    printf 'ifconfig-push 10.80.0.5 255.255.252.0\n' > "$(ovpn_ccd_dir)/alice"
    ovpn_ccd_readdress 10.8.0.0 255.255.255.0 10.80.0.0 255.255.252.0
    grep -q '^ifconfig-push 10.80.0.5 255.255.252.0$' "$(ovpn_ccd_dir)/alice"
}

@test "ovpn_ccd_set_iroute: marca a sub-rede atrás do peer (idempotente)" {
    ovpn_ccd_assign hub-b >/dev/null
    ovpn_ccd_set_iroute hub-b 10.8.1.0 255.255.255.0
    ovpn_ccd_set_iroute hub-b 10.8.1.0 255.255.255.0
    local f="${OVPN_SERVER_DIR}/ccd/hub-b"
    grep -q 'iroute 10.8.1.0 255.255.255.0' "${f}"
    [ "$(grep -c 'iroute' "${f}")" -eq 1 ]
}

@test "ovpn_ccd_assign: cria a entrada do cliente com IP fixo (ifconfig-push)" {
    run ovpn_ccd_assign alice
    [ "$status" -eq 0 ]
    [ -f "${OVPN_SERVER_DIR}/ccd/alice" ]
    grep -q "ifconfig-push" "${OVPN_SERVER_DIR}/ccd/alice"
}

@test "ovpn_ccd_assign: é idempotente (mantém o mesmo IP)" {
    local first second
    first="$(ovpn_ccd_assign alice)"
    second="$(ovpn_ccd_assign alice)"
    [ -n "${first}" ]
    [ "${first}" = "${second}" ]
}

@test "ovpn_ccd_assign: clientes diferentes recebem IPs diferentes" {
    local a b
    a="$(ovpn_ccd_assign alice)"
    b="$(ovpn_ccd_assign bob)"
    [ "${a}" != "${b}" ]
}

@test "ovpn_ccd_assign: 3+ clientes recebem IPs distintos e sequenciais" {
    [ "$(ovpn_ccd_assign alice)" = "10.8.0.2" ]
    [ "$(ovpn_ccd_assign bob)"   = "10.8.0.3" ]
    [ "$(ovpn_ccd_assign carol)" = "10.8.0.4" ]
    [ "$(ovpn_ccd_assign dave)"  = "10.8.0.5" ]
}

@test "ovpn_ccd_set_full_tunnel: empurra redirect-gateway e DNS só para o cliente" {
    ovpn_ccd_assign alice >/dev/null
    ovpn_ccd_set_full_tunnel alice
    local f="${OVPN_SERVER_DIR}/ccd/alice"
    grep -q 'push "redirect-gateway def1"' "${f}"
    grep -q 'dhcp-option DNS' "${f}"
}

@test "ovpn_ccd_set_full_tunnel: é idempotente (não duplica)" {
    ovpn_ccd_assign alice >/dev/null
    ovpn_ccd_set_full_tunnel alice
    ovpn_ccd_set_full_tunnel alice
    local n
    n="$(grep -c 'redirect-gateway' "${OVPN_SERVER_DIR}/ccd/alice")"
    [ "${n}" -eq 1 ]
}

@test "ovpn_ccd_unset_full_tunnel: remove a marcação (volta a split-tunnel)" {
    ovpn_ccd_assign alice >/dev/null
    ovpn_ccd_set_full_tunnel alice
    ovpn_ccd_unset_full_tunnel alice
    local f="${OVPN_SERVER_DIR}/ccd/alice"
    ! grep -q 'redirect-gateway' "${f}"
    grep -q 'ifconfig-push' "${f}"
}
