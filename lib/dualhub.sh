#!/usr/bin/env bash
# Módulo dualhub — segundo hub ativo-ativo.
#
# Os dois hubs usam sub-redes distintas (ex.: 10.8.0.0/24 e 10.8.1.0/24), a CA
# compartilhada (ver hub_sync) e um túnel site-to-site entre eles. Cada hub
# aprende e anuncia a rota para a sub-rede do outro, de modo que um cliente do
# hub A alcance um cliente do hub B. Os perfis de cliente listam os dois hubs
# como `remote` (ver client_profile, variável OVPN_REMOTE_HOST_2).
# O enlace site-to-site usa o mecanismo nativo do OpenVPN: o hub B conecta-se
# ao hub A como um cliente comum, e a sub-rede do hub B é marcada com `iroute`
# no ccd do hub A (ver ovpn_dualhub_register_peer). Cada hub também instala e
# anuncia a rota da sub-rede do outro (ver ovpn_dualhub_configure). Ver ADR 0004.
# Depende dos módulos core, log, pki, wizard_ipproto, server_config, ccd,
# client_profile e firewall.

: "${OVPN_SUBNET_V4:=10.8.0.0}"
: "${OVPN_TUN_IFACE:=tun0}"

# Verdadeiro (0) se as sub-redes /24 dos dois hubs NÃO se sobrepõem.
ovpn_dualhub_validate_subnets() {
    local local_subnet="$1" peer_subnet="$2"
    [[ -n "${local_subnet}" && -n "${peer_subnet}" ]] \
        || ovpn_die "Informe as sub-redes dos dois hubs."
    if [[ "${local_subnet}" == "${peer_subnet}" ]]; then
        ovpn_die "As sub-redes dos dois hubs não podem ser iguais (${local_subnet})."
    fi
    return 0
}

# Verdadeiro (0) se o server.conf já contém o trecho indicado.
_ovpn_dualhub_conf_has() {
    awk -v p="$1" 'index($0, p) { found = 1 } END { exit !found }' "$2" 2>/dev/null
}

# Configura este hub para alcançar a sub-rede do hub par: valida as sub-redes,
# adiciona a rota local (via túnel site-to-site) e a anuncia aos clientes.
ovpn_dualhub_configure() {
    local peer_subnet="$1" peer_netmask="${2:-255.255.255.0}"
    ovpn_dualhub_validate_subnets "${OVPN_SUBNET_V4}" "${peer_subnet}"

    local conf
    conf="$(ovpn_server_conf_path)"
    if ! _ovpn_dualhub_conf_has "route ${peer_subnet} ${peer_netmask}" "${conf}"; then
        printf 'route %s %s\n' "${peer_subnet}" "${peer_netmask}" >> "${conf}"
        printf 'push "route %s %s"\n' "${peer_subnet}" "${peer_netmask}" >> "${conf}"
    fi
    ovpn_log_ok "Hub configurado para alcançar a sub-rede ${peer_subnet} do hub par."
}

# Registra o hub par como peer DESTE hub (que age como ponto de encontro do
# enlace). Roda no hub A: emite o perfil de conexão do peer (.ovpn que o hub B
# usará para conectar aqui), fixa o IP, marca a sub-rede do peer com iroute
# (para o OpenVPN rotear até ele) e instala/anuncia a rota dessa sub-rede.
# O perfil sai com um único `remote` (o hub A) mesmo que haja 2º host definido.
ovpn_dualhub_register_peer() {
    local name="$1" peer_subnet="$2" peer_netmask="${3:-255.255.255.0}"
    [[ -n "${name}" ]] || ovpn_die "Informe o nome do peer (ex.: hub-b)."
    ovpn_dualhub_validate_subnets "${OVPN_SUBNET_V4}" "${peer_subnet}"

    # O enlace conecta especificamente ao hub A — sem 2º remote nem remote-random.
    ( unset OVPN_REMOTE_HOST_2; ovpn_client_create "${name}" >/dev/null )

    ovpn_ccd_set_iroute "${name}" "${peer_subnet}" "${peer_netmask}"
    ovpn_dualhub_configure "${peer_subnet}" "${peer_netmask}"

    ovpn_log_ok "Peer ${name} registrado (sub-rede ${peer_subnet} via iroute). Leve o perfil $(ovpn_client_profile_path "${name}") para o hub par."
}

# Habilita o encaminhamento do tráfego inter-hub no hub que conecta como cliente
# (tipicamente o hub B): o tráfego dos clientes (tun dos clientes) para o enlace
# é um forward de kernel. Habilita e PERSISTE o ip_forward e, em UFW (FORWARD
# DROP), libera o forward BIDIRECIONAL entre os clientes e o enlace. NUNCA aplica
# NAT — o tráfego inter-hub preserva os IPs reais da VPN (cada cliente enxerga o
# outro pelo IP de verdade). A porta do enlace não precisa ser aberta: o hub
# conecta para fora, no servidor já existente do hub par. <link> = interface do
# enlace (ex.: tun1, a que o openvpn-client do enlace cria).
ovpn_dualhub_link_forwarding() {
    local link="$1"
    [[ -n "${link}" ]] || ovpn_die "Informe a interface do enlace (ex.: tun1)."
    ovpn_sysctl_set net.ipv4.ip_forward 1

    case "$(_ovpn_firewall_backend)" in
        ufw)
            ufw route allow in on "${OVPN_TUN_IFACE}" out on "${link}"
            ufw route allow in on "${link}" out on "${OVPN_TUN_IFACE}"
            ufw reload
            ;;
        *)
            # nft/iptables: a política de FORWARD costuma ser ACCEPT; o
            # ip_forward persistido já basta. Nunca NATear o tráfego inter-hub.
            ovpn_log_info "Encaminhamento inter-hub por ip_forward (sem regra extra de FORWARD; sem NAT)."
            ;;
    esac
    ovpn_log_ok "Encaminhamento inter-hub ativado entre ${OVPN_TUN_IFACE} e ${link} (sem NAT)."
}
