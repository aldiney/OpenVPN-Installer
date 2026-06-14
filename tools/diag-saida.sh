#!/usr/bin/env bash
# diag-saida.sh — diagnóstico AUTOMÁTICO da saída para a internet pela VPN.
#
# Rode no servidor (hub), como root, ANTES de conectar o cliente. Ele mostra o
# estado do firewall/NAT, captura o tráfego dos clientes na interface da VPN por
# uma janela de tempo e diz, sozinho, se o tráfego de internet (ICMP/DNS/HTTPS)
# está saindo pela VPN E VOLTANDO — sem precisar de ninguém olhando ao vivo.
#
# Uso:
#   sudo ./tools/diag-saida.sh [segundos]      # padrão: 180
#
# Durante a janela, conecte o cliente e gere tráfego (ping/nslookup/navegar).
# Dica segura: teste com um perfil SPLIT (rotas 1.1.1.1/8.8.8.8) para não
# arriscar ficar sem internet — ver docs/troubleshooting.md.
set -euo pipefail

WINDOW="${1:-180}"
TUN="${OVPN_TUN_IFACE:-tun0}"
VPN_NET="${OVPN_VPN_NET:-10.8.0.0/24}"
VPN_NET6="${OVPN_VPN_NET6:-fd00:0:0:8::/64}"
WAN="$(ip route show default 2>/dev/null | awk '/default/{print $5; exit}')"
LOG="/tmp/diag-saida-$$.txt"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Rode como root: sudo ./tools/diag-saida.sh"
    exit 1
fi

echo "==== Estado do servidor ===="
echo "Interface VPN: ${TUN}   |   WAN (saída): ${WAN:-?}"
echo "ip_forward: $(sysctl -n net.ipv4.ip_forward 2>/dev/null)"
if iptables -vnL ufw-user-forward 2>/dev/null | grep -q "${TUN}"; then
    echo "Encaminhamento ${TUN}->${WAN}: LIBERADO (ufw route allow presente)"
else
    echo "Encaminhamento ${TUN}->${WAN}: NÃO liberado — rode 'ufw route allow in on ${TUN} out on ${WAN}'"
fi
if nft list table ip ovpn 2>/dev/null | grep -q masquerade \
   || iptables -t nat -S POSTROUTING 2>/dev/null | grep -q "${VPN_NET%/*}"; then
    echo "NAT (masquerade) para ${VPN_NET}: presente"
else
    echo "NAT (masquerade) para ${VPN_NET}: AUSENTE — ative a saída para a internet no menu"
fi

echo ""
echo ">>> Capturando ${WINDOW}s em ${TUN}. CONECTE O CLIENTE e gere tráfego AGORA"
echo "    (ping 1.1.1.1 ; nslookup globo.com 1.1.1.1 ; abrir um site)."
timeout "${WINDOW}" tcpdump -nni "${TUN}" \
    "(icmp or icmp6 or port 53 or port 443) and not net ${VPN_NET} and not net ${VPN_NET6}" \
    > "${LOG}" 2>/dev/null || true

# Respostas VOLTANDO para um cliente (10.8.0.x) = prova de ida e volta.
icmp_reply="$(grep -cE 'ICMP echo reply' "${LOG}" 2>/dev/null || true)"
dns_reply="$(grep -cE '\.53 > '            "${LOG}" 2>/dev/null || true)"
https_reply="$(grep -cE '\.443 > '          "${LOG}" 2>/dev/null || true)"
total="$(grep -cE 'IP'                      "${LOG}" 2>/dev/null || true)"
fwd_pkts="$(iptables -vnL ufw-user-forward 2>/dev/null | awk -v t="${TUN}" '$0 ~ t {print $1; exit}')"

echo ""
echo "==== Resultado ===="
echo "Pacotes capturados em ${TUN}: ${total:-0}"
echo "Respostas ICMP (ping)  voltando ao cliente: ${icmp_reply:-0}"
echo "Respostas DNS  (porta 53) voltando ao cliente: ${dns_reply:-0}"
echo "Respostas HTTPS(porta 443) voltando ao cliente: ${https_reply:-0}"
echo "Pacotes encaminhados ${TUN}->${WAN}: ${fwd_pkts:-0}"
echo ""

if [[ "${icmp_reply:-0}" -gt 0 || "${dns_reply:-0}" -gt 0 || "${https_reply:-0}" -gt 0 ]]; then
    echo "RESULTADO: PASSOU ✅ — o tráfego de internet do cliente sai pela VPN e volta."
elif [[ "${total:-0}" -gt 0 ]]; then
    echo "RESULTADO: PARCIAL ⚠️ — houve tráfego de saída, mas SEM respostas voltando."
    echo "           Provável NAT/encaminhamento incompleto no servidor. Veja o estado acima."
else
    echo "RESULTADO: SEM TRÁFEGO ⛔ — o cliente não conectou ou não gerou tráfego na janela."
    echo "           Confirme que conectou e testou durante os ${WINDOW}s."
fi
echo "Captura completa em: ${LOG}"
