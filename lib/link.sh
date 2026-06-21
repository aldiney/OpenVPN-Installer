#!/usr/bin/env bash
# Módulo link — enlace inter-hub DEDICADO para o roteamento dinâmico (OSPF).
#
# Para o IP estável global, o OSPF precisa de uma interface ponto-a-ponto entre
# os hubs SEM os clientes comuns (celular/MikroTik não falam OSPF). Por isso o
# enlace é uma 2ª instância OpenVPN, só para hubs, numa porta e sub-rede de
# transporte próprias, com a interface fixa `ovpn-link`. O OSPF roda só nela.
# - Core (ponto de encontro): roda um link-server (openvpn-server@link).
# - Spoke (quem conecta): roda um link-client (openvpn-client@link).
# Reusa a CA compartilhada e o tls-crypt. Ver ADR 0005. Depende de core e pki.

: "${OVPN_LINK_IFACE:=ovpn-link}"
: "${OVPN_LINK_NAME:=link}"
: "${OVPN_LINK_PORT:=1195}"
: "${OVPN_TRANSPORT_NET_V4:=10.255.0.0}"
: "${OVPN_TRANSPORT_MASK_V4:=255.255.255.0}"
: "${OVPN_CLIENT_CONF_DIR:=${OVPN_ETC}/client}"
: "${OVPN_PROTO:=udp}"
: "${OVPN_DATA_CIPHERS:=AES-256-GCM:AES-128-GCM}"
: "${OVPN_SUBNET_V4:=10.8.0.0}"
: "${OVPN_NETMASK_V4:=255.255.255.0}"

ovpn_link_conf_path_core()  { printf '%s' "${OVPN_SERVER_DIR}/${OVPN_LINK_NAME}.conf"; }
ovpn_link_conf_path_spoke() { printf '%s' "${OVPN_CLIENT_CONF_DIR}/${OVPN_LINK_NAME}.conf"; }
# ccd dedicado do enlace (separado do ccd dos clientes comuns).
ovpn_link_ccd_dir()         { printf '%s' "${OVPN_SERVER_DIR}/ccd-link"; }

# Renderiza o link-server do hub core: emite o cert dedicado (serverAuth) e
# escreve a config da 2ª instância OpenVPN (dev ovpn-link, sub-rede de
# transporte, porta própria). Uso: ovpn_link_render_core [porta]
ovpn_link_render_core() {
    local port="${1:-${OVPN_LINK_PORT}}"
    ovpn_pki_issue_server "link-core" >/dev/null
    mkdir -p "${OVPN_SERVER_DIR}"
    {
        printf 'dev %s\n' "${OVPN_LINK_IFACE}"
        printf 'dev-type tun\n'
        printf 'proto %s\n' "${OVPN_PROTO}"
        printf 'port %s\n' "${port}"
        printf 'topology subnet\n'
        printf 'server %s %s\n' "${OVPN_TRANSPORT_NET_V4}" "${OVPN_TRANSPORT_MASK_V4}"
        # Entrega o espaço de clientes ao spoke. O OpenVPN-server só roteia a um
        # cliente o que tiver iroute; sem isto, os /32 atrás do spoke (identidade
        # do outro hub, clientes em roam) chegam ao tun do core e são descartados.
        # O kernel já filtra (só manda à ovpn-link os /32 que o OSPF aprendeu lá),
        # então iroutar o /24 inteiro ao único spoke é seguro. O ccd DEFAULT vale
        # p/ o spoke seja qual for o CN dele. (Topologia de 1 core + 1 spoke.)
        printf 'client-config-dir %s\n' "$(ovpn_link_ccd_dir)"
        printf 'ca %s\n' "$(ovpn_pki_ca_cert)"
        printf 'cert %s/issued/link-core.crt\n' "${OVPN_PKI_DIR}"
        printf 'key %s/private/link-core.key\n' "${OVPN_PKI_DIR}"
        printf 'dh none\n'
        printf 'tls-crypt %s\n' "$(ovpn_pki_tls_crypt)"
        printf 'data-ciphers %s\n' "${OVPN_DATA_CIPHERS}"
        # SEM client-to-client de propósito: com o iroute do /24, ele faria o
        # OpenVPN tratar TODO o espaço (inclusive a identidade e os clientes
        # LOCAIS do core) como "atrás do spoke", e os pacotes de entrada para
        # esses endereços não seriam entregues localmente. Sem ele, a entrada
        # vai ao kernel (que roteia pelo OSPF/connected) e o iroute serve só
        # para a saída core->spoke. (Enlace de 1 core + 1 spoke.)
        printf 'keepalive 10 60\n'
        printf 'persist-key\n'
        printf 'persist-tun\n'
        printf 'verb 3\n'
    } > "$(ovpn_link_conf_path_core)"
    mkdir -p "$(ovpn_link_ccd_dir)"
    printf 'iroute %s %s\n' "${OVPN_SUBNET_V4}" "${OVPN_NETMASK_V4}" \
        > "$(ovpn_link_ccd_dir)/DEFAULT"
}

# Renderiza o link-client do hub spoke: emite o cert dedicado (clientAuth, nome
# ÚNICO por hub) e escreve a config que conecta ao hub core.
# Uso: ovpn_link_render_spoke <host_core> [porta] [nome_cert]
ovpn_link_render_spoke() {
    local remote="$1" port="${2:-${OVPN_LINK_PORT}}" name="${3:-link-spoke}"
    [[ -n "${remote}" ]] || ovpn_die "Informe o host do hub core (ex.: hubA.exemplo.com)."
    ovpn_pki_issue_client "${name}" >/dev/null
    mkdir -p "${OVPN_CLIENT_CONF_DIR}"
    {
        printf 'client\n'
        printf 'dev %s\n' "${OVPN_LINK_IFACE}"
        printf 'dev-type tun\n'
        printf 'proto %s\n' "${OVPN_PROTO}"
        printf 'remote %s %s\n' "${remote}" "${port}"
        printf 'nobind\n'
        printf 'remote-cert-tls server\n'
        printf 'ca %s\n' "$(ovpn_pki_ca_cert)"
        printf 'cert %s/issued/%s.crt\n' "${OVPN_PKI_DIR}" "${name}"
        printf 'key %s/private/%s.key\n' "${OVPN_PKI_DIR}" "${name}"
        printf 'tls-crypt %s\n' "$(ovpn_pki_tls_crypt)"
        printf 'data-ciphers %s\n' "${OVPN_DATA_CIPHERS}"
        printf 'keepalive 10 60\n'
        printf 'persist-key\n'
        printf 'persist-tun\n'
        printf 'verb 3\n'
    } > "$(ovpn_link_conf_path_spoke)"
}
