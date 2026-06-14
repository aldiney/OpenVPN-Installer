#!/usr/bin/env bash
# Módulo gateway — saída para a internet (NAT) opcional, por hub.
#
# Habilita o NAT (masquerade) do tráfego da VPN pela interface WAN. QUEM usa a
# saída é decidido POR CLIENTE (ver ovpn_ccd_set_full_tunnel): só os clientes
# marcados como full-tunnel saem pela internet do hub; os demais ficam em
# split-tunnel. Em host com UFW, ajusta a política de forward (que costuma ser
# DROP e bloquearia o encaminhamento). Backends: ufw, nft ou iptables.
# Depende dos módulos core, log e firewall.

: "${OVPN_SUBNET_V4:=10.8.0.0}"
: "${OVPN_UFW_DEFAULTS:=/etc/default/ufw}"

# Ativa a saída para a internet (NAT) pela interface WAN informada.
ovpn_gateway_enable() {
    local wan="$1"
    [[ -n "${wan}" ]] || ovpn_die "Informe a interface WAN (ex.: eth0)."
    sysctl -w net.ipv4.ip_forward=1

    case "$(_ovpn_firewall_backend)" in
        ufw)
            _ovpn_gateway_ufw_forward
            _ovpn_gateway_nft_masquerade "${wan}"
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

# Libera o encaminhamento no UFW (a política padrão costuma ser DROP, o que
# descartaria os pacotes roteados mesmo com o masquerade no lugar).
_ovpn_gateway_ufw_forward() {
    if [[ -f "${OVPN_UFW_DEFAULTS}" ]]; then
        sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' "${OVPN_UFW_DEFAULTS}"
        ufw reload
    fi
}

# Cria a regra de masquerade numa tabela nft própria (não conflita com o UFW).
_ovpn_gateway_nft_masquerade() {
    local wan="$1"
    nft add table ip ovpn 2>/dev/null || true
    nft add chain ip ovpn postrouting '{ type nat hook postrouting priority 100 ; }' 2>/dev/null || true
    nft add rule ip ovpn postrouting ip saddr "${OVPN_SUBNET_V4}/24" oifname "${wan}" masquerade
}

# Desativa a saída para a internet (remove o NAT).
ovpn_gateway_disable() {
    local wan="${1:-}"
    case "$(_ovpn_firewall_backend)" in
        ufw|nft)
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
