#!/usr/bin/env bash
# Módulo firewall — abre a porta de escuta do OpenVPN no firewall ativo.
# Detecta ufw (se ativo), senão nft, senão iptables. Sem isto, o firewall do
# host bloqueia os clientes (causa comum de "conecta mas não responde").
# Depende dos módulos core e log.

: "${OVPN_PORT:=1194}"

# Detecta o backend de firewall: ufw (se ativo), senão nft, senão iptables.
_ovpn_firewall_backend() {
    local status
    if command -v ufw >/dev/null 2>&1; then
        status="$(ufw status 2>/dev/null || true)"
        if [[ "${status}" == *"Status: active"* ]]; then
            printf 'ufw'
            return 0
        fi
    fi
    if command -v nft >/dev/null 2>&1; then
        printf 'nft'
    else
        printf 'iptables'
    fi
}

# Abre a porta de escuta do OpenVPN no firewall ativo.
ovpn_firewall_open_port() {
    local port="${1:-${OVPN_PORT}}" proto="${2:-udp}"
    case "$(_ovpn_firewall_backend)" in
        ufw)
            ufw allow "${port}/${proto}" comment 'OpenVPN'
            ;;
        nft)
            nft add table inet ovpn_fw 2>/dev/null || true
            nft add chain inet ovpn_fw input '{ type filter hook input priority 0 ; policy accept ; }' 2>/dev/null || true
            nft add rule inet ovpn_fw input "${proto}" dport "${port}" accept
            ;;
        *)
            iptables -I INPUT -p "${proto}" --dport "${port}" -j ACCEPT
            ;;
    esac
    ovpn_log_ok "Porta ${port}/${proto} liberada no firewall."
}
