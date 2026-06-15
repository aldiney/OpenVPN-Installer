#!/usr/bin/env bash
# Módulo gateway — saída para a internet (NAT) opcional, por hub.
#
# Habilita o NAT (masquerade) do tráfego da VPN pela interface WAN e o
# ENCAMINHAMENTO tun->WAN. QUEM usa a saída é decidido por cliente (ver
# ovpn_client_routing_block / ovpn_ccd_set_full_tunnel).
#
# Em host com UFW (caso comum): a política de FORWARD costuma ser DROP, o que
# descartaria o tráfego roteado mesmo com o masquerade. Por isso usamos
# `ufw route allow in on <tun> out on <wan>` (alvo, persistente) e gravamos o
# masquerade no /etc/ufw/before.rules (persiste no reboot). Backends sem UFW:
# nft (padrão) ou iptables, em runtime. Depende de core, log e firewall.

: "${OVPN_SUBNET_V4:=10.8.0.0}"
: "${OVPN_TUN_IFACE:=tun0}"
: "${OVPN_UFW_BEFORE_RULES:=/etc/ufw/before.rules}"

# Ativa a saída para a internet (NAT + encaminhamento) pela interface WAN.
ovpn_gateway_enable() {
    local wan="$1"
    [[ -n "${wan}" ]] || ovpn_die "Informe a interface WAN (ex.: eth0)."
    ovpn_sysctl_set net.ipv4.ip_forward 1

    case "$(_ovpn_firewall_backend)" in
        ufw)
            _ovpn_gateway_ufw_enable "${wan}"
            ;;
        nft)
            _ovpn_gateway_nft_masquerade "${wan}"
            ;;
        *)
            iptables -t nat -A POSTROUTING -s "${OVPN_SUBNET_V4}/24" -o "${wan}" -j MASQUERADE
            ;;
    esac
    ovpn_log_ok "Saída para a internet (NAT) ativada via ${wan}. Marque clientes como full-tunnel para usá-la."
}

# Desativa a saída para a internet (remove NAT e encaminhamento).
ovpn_gateway_disable() {
    local wan="${1:-}"
    case "$(_ovpn_firewall_backend)" in
        ufw)
            if [[ -n "${wan}" ]]; then
                _ovpn_gateway_ufw_disable "${wan}"
            fi
            ;;
        nft)
            nft delete table ip ovpn 2>/dev/null || true
            ;;
        *)
            if [[ -n "${wan}" ]]; then
                iptables -t nat -D POSTROUTING \
                    -s "${OVPN_SUBNET_V4}/24" -o "${wan}" -j MASQUERADE 2>/dev/null || true
            fi
            ;;
    esac
    ovpn_log_ok "Saída para a internet desativada."
}

# --- UFW: encaminhamento (ufw route) + NAT persistente (before.rules) -----

_ovpn_gateway_ufw_enable() {
    local wan="$1"
    # Remove um NAT legado em runtime (versões antigas usavam 'nft table ip ovpn'),
    # para não ficar com masquerade DUPLICADO — o que bagunça o de-NAT das
    # respostas ICMP (traceroute/mtr falham embora a navegação funcione).
    nft delete table ip ovpn 2>/dev/null || true
    ufw route allow in on "${OVPN_TUN_IFACE}" out on "${wan}"
    _ovpn_gateway_ufw_nat_add "${wan}"
    ufw reload
}

_ovpn_gateway_ufw_disable() {
    local wan="$1"
    nft delete table ip ovpn 2>/dev/null || true
    ufw route delete allow in on "${OVPN_TUN_IFACE}" out on "${wan}" 2>/dev/null || true
    _ovpn_gateway_ufw_nat_remove "${wan}"
    ufw reload
}

# Regra de masquerade que será persistida.
_ovpn_gateway_nat_rule() {
    printf -- '-A POSTROUTING -s %s/24 -o %s -j MASQUERADE' "${OVPN_SUBNET_V4}" "$1"
}

# Grava o masquerade no before.rules do UFW (idempotente, persiste no reboot).
_ovpn_gateway_ufw_nat_add() {
    local wan="$1" before="${OVPN_UFW_BEFORE_RULES}" rule
    rule="$(_ovpn_gateway_nat_rule "${wan}")"
    [[ -f "${before}" ]] || return 0
    if awk -v r="${rule}" 'index($0, r) { f = 1 } END { exit !f }' "${before}"; then
        return 0
    fi
    local tmp
    tmp="$(mktemp)"
    if awk '/^\*nat/ { f = 1 } END { exit !f }' "${before}"; then
        # Já existe um bloco *nat: insere a regra logo após a linha *nat.
        awk -v r="${rule}" '{ print } /^\*nat/ && !d { print r; d = 1 }' "${before}" > "${tmp}"
    else
        # Sem *nat: prepende um bloco novo.
        {
            printf '*nat\n:POSTROUTING ACCEPT [0:0]\n%s\nCOMMIT\n\n' "${rule}"
            cat "${before}"
        } > "${tmp}"
    fi
    mv "${tmp}" "${before}"
}

# Remove a regra de masquerade do before.rules.
_ovpn_gateway_ufw_nat_remove() {
    local wan="$1" before="${OVPN_UFW_BEFORE_RULES}" rule tmp
    rule="$(_ovpn_gateway_nat_rule "${wan}")"
    [[ -f "${before}" ]] || return 0
    tmp="$(mktemp)"
    awk -v r="${rule}" '!index($0, r)' "${before}" > "${tmp}" && mv "${tmp}" "${before}"
}

# --- nft (host sem UFW) ---------------------------------------------------

_ovpn_gateway_nft_masquerade() {
    local wan="$1"
    nft add table ip ovpn 2>/dev/null || true
    nft add chain ip ovpn postrouting '{ type nat hook postrouting priority 100 ; }' 2>/dev/null || true
    nft add rule ip ovpn postrouting ip saddr "${OVPN_SUBNET_V4}/24" oifname "${wan}" masquerade
}
