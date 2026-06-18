#!/usr/bin/env bash
# Módulo hub_identity — IP de identidade fixo deste hub na VPN.
#
# Como todos os hubs compartilham o espaço (e o servidor de cada um fica no .1),
# não há como um cliente endereçar um hub ESPECÍFICO. Este módulo dá a cada hub
# um /32 próprio, reservado no TOPO do espaço e derivado do HUB_ID (ex.: hub 1 =
# .241, hub 2 = .242), atribuído a uma interface dummy e anunciado pelo OSPF
# (redistribute connected, filtrado para /32 — ver lib/frr.sh). Assim, de
# qualquer cliente, esse IP cai sempre no hub certo (o /32 segue o hub pelo
# enlace). Ver ADR 0005. Depende do módulo core.

: "${OVPN_HUB_RESERVED:=15}"
: "${OVPN_HUB_SELF_IFACE:=ovpn-self}"
: "${OVPN_SYSTEMD_DIR:=/etc/systemd/system}"

# IP de identidade deste hub: bloco reservado no topo do espaço (broadcast menos
# OVPN_HUB_RESERVED), deslocado pelo HUB_ID. Uso: ovpn_hub_identity_ip [hub_id]
# shellcheck disable=SC2120  # hub_id é opcional (cai p/ OVPN_HUB_ID); chamada sem arg é válida.
ovpn_hub_identity_ip() {
    local hub_id="${1:-${OVPN_HUB_ID:-1}}" mask_int net bcast
    mask_int="$(ovpn_ip_to_int "${OVPN_NETMASK_V4}")"
    net=$(( $(ovpn_ip_to_int "${OVPN_SUBNET_V4}") & mask_int ))
    bcast=$(( net | (~mask_int & 0xFFFFFFFF) ))
    ovpn_int_to_ip $(( bcast - OVPN_HUB_RESERVED + hub_id ))
}

# Atribui (e PERSISTE) o IP de identidade numa interface dummy via unit systemd,
# para o hub responder nele e o OSPF anunciá-lo. Idempotente.
ovpn_hub_identity_install() {
    local ip
    # shellcheck disable=SC2119  # usa o default (OVPN_HUB_ID); não há arg posicional aqui.
    ip="$(ovpn_hub_identity_ip)"
    mkdir -p "${OVPN_SYSTEMD_DIR}"
    cat > "${OVPN_SYSTEMD_DIR}/openvpn-hub-identity.service" <<UNIT
[Unit]
Description=IP de identidade deste hub na VPN (${ip})
After=network.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'ip link show ${OVPN_HUB_SELF_IFACE} >/dev/null 2>&1 || ip link add ${OVPN_HUB_SELF_IFACE} type dummy; ip addr replace ${ip}/32 dev ${OVPN_HUB_SELF_IFACE}; ip link set ${OVPN_HUB_SELF_IFACE} up'
ExecStop=/bin/sh -c 'ip link del ${OVPN_HUB_SELF_IFACE} 2>/dev/null || true'
[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable --now openvpn-hub-identity.service
}
