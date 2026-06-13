#!/usr/bin/env bash
# Módulo dualhub — segundo hub ativo-ativo.
#
# Os dois hubs usam sub-redes distintas (ex.: 10.8.0.0/24 e 10.8.1.0/24), a CA
# compartilhada (ver hub_sync) e um túnel site-to-site entre eles. Cada hub
# aprende e anuncia a rota para a sub-rede do outro, de modo que um cliente do
# hub A alcance um cliente do hub B. Os perfis de cliente listam os dois hubs
# como `remote` (ver client_profile, variável OVPN_REMOTE_HOST_2).
# Depende dos módulos core, log, wizard_ipproto e server_config.

: "${OVPN_SUBNET_V4:=10.8.0.0}"

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
