#!/usr/bin/env bash
# Módulo gateway — saída para a internet opcional (desligada por padrão).
# Quando ativada, um hub passa a rotear o tráfego de internet dos clientes:
# empurra a rota padrão (redirect-gateway) e faz NAT masquerade na WAN.
# Backend de firewall: nft (padrão nos alvos) ou iptables (fallback).
# Depende dos módulos core, log, wizard_ipproto e server_config.

: "${OVPN_SUBNET_V4:=10.8.0.0}"

# Seam: escolhe o backend de firewall disponível.
_ovpn_gateway_backend() {
    if command -v nft >/dev/null 2>&1; then
        printf 'nft'
    else
        printf 'iptables'
    fi
}

# Verdadeiro (0) se o server.conf já contém a linha de push indicada.
_ovpn_gateway_conf_has() {
    awk -v p="$1" 'index($0, p) { found = 1 } END { exit !found }' "$2" 2>/dev/null
}

# Ativa a saída para a internet pela interface WAN informada.
ovpn_gateway_enable() {
    local wan="$1"
    [[ -n "${wan}" ]] || ovpn_die "Informe a interface WAN (ex.: eth0)."

    sysctl -w net.ipv4.ip_forward=1

    local conf
    conf="$(ovpn_server_conf_path)"
    if ! _ovpn_gateway_conf_has 'redirect-gateway def1' "${conf}"; then
        printf 'push "redirect-gateway def1"\n' >> "${conf}"
    fi

    case "$(_ovpn_gateway_backend)" in
        nft)
            nft add table ip ovpn 2>/dev/null || true
            nft add chain ip ovpn postrouting '{ type nat hook postrouting priority 100 ; }' 2>/dev/null || true
            nft add rule ip ovpn postrouting ip saddr "${OVPN_SUBNET_V4}/24" oifname "${wan}" masquerade
            ;;
        *)
            iptables -t nat -A POSTROUTING -s "${OVPN_SUBNET_V4}/24" -o "${wan}" -j MASQUERADE
            ;;
    esac

    ovpn_log_ok "Saída para a internet ativada via ${wan}."
}

# Desativa a saída para a internet (remove o push e a regra de NAT).
ovpn_gateway_disable() {
    local wan="${1:-}"
    local conf
    conf="$(ovpn_server_conf_path)"
    if [[ -f "${conf}" ]]; then
        awk '!index($0, "redirect-gateway def1")' "${conf}" > "${conf}.tmp" \
            && mv "${conf}.tmp" "${conf}"
    fi

    case "$(_ovpn_gateway_backend)" in
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
