#!/usr/bin/env bash
# Módulo frr — roteamento dinâmico OSPF via FRR, para o IP estável global.
#
# Cada hub anuncia no OSPF SÓ os /32 dos clientes conectados a ele (mantidos
# pelo reconciliador — ver lib/route_reconcile.sh, redistribute kernel). O /22
# conectado do tun NÃO é redistribuído (filtrado por prefix-list/route-map), e o
# /32 (mais específico) vence o /22 nos outros hubs → o tráfego segue o cliente
# que migrou. OSPF roda SÓ sobre a interface do enlace (passive-interface
# default). Sem autenticação na v1 (o túnel já cifra). Ver ADR 0005.
# Depende dos módulos core, log e deps. Comando externo: systemctl, vtysh (seam).

: "${OVPN_FRR_DIR:=/etc/frr}"
: "${OVPN_FRR_DAEMONS:=${OVPN_FRR_DIR}/daemons}"
: "${OVPN_FRR_OSPF_CONF:=${OVPN_FRR_DIR}/ospfd.conf}"
: "${OVPN_FRR_VTYSH_CONF:=${OVPN_FRR_DIR}/vtysh.conf}"

# Garante o FRR instalado, passando pelo gate de dependências (regra dos 7 dias
# + confirmação [s/N]).
ovpn_frr_ensure() {
    ovpn_deps_ensure frr
}

# Desliga o integrated-vtysh-config. O padrão do FRR no Debian/Ubuntu é
# `service integrated-vtysh-config`, que faz o FRR ler SÓ o /etc/frr/frr.conf e
# IGNORAR os arquivos por-daemon — inclusive o nosso ospfd.conf. Sem isto, a
# config OSPF nunca é carregada (o ospfd sobe sem `router ospf`).
ovpn_frr_render_vtysh() {
    mkdir -p "${OVPN_FRR_DIR}"
    printf 'no service integrated-vtysh-config\n' > "${OVPN_FRR_VTYSH_CONF}"
}

# Escreve /etc/frr/daemons habilitando só o ospfd (+ zebra, exigido).
ovpn_frr_render_daemons() {
    mkdir -p "${OVPN_FRR_DIR}"
    cat > "${OVPN_FRR_DAEMONS}" <<'DAEMONS'
# Gerado pelo OpenVPN-Installer — habilita só o ospfd (zebra é exigido).
zebra=yes
bgpd=no
ospfd=yes
ospf6d=no
ripd=no
ripngd=no
isisd=no
pimd=no
ldpd=no
nhrpd=no
eigrpd=no
babeld=no
sharpd=no
pbrd=no
bfdd=no
fabricd=no
vrrpd=no
pathd=no

vtysh_enable=yes
zebra_options="  -A 127.0.0.1 -s 90000000"
ospfd_options="  -A 127.0.0.1"
DAEMONS
}

# Escreve /etc/frr/ospfd.conf. Redistribui SÓ os /32 dos clientes (route-map
# ONLY-CLIENT-32 + prefix-list que casa <espaço>/<plen> ge 32 le 32); nunca o
# /22 conectado (sem `redistribute connected`). OSPF só no enlace.
# Uso: ovpn_frr_render_ospf <router_id> <espaço> <plen> <rede_transporte> <area> <iface_enlace>
ovpn_frr_render_ospf() {
    local router_id="$1" space="$2" plen="$3" transport="$4" area="$5" link="$6"
    mkdir -p "${OVPN_FRR_DIR}"
    cat > "${OVPN_FRR_OSPF_CONF}" <<OSPF
! Gerado pelo OpenVPN-Installer — IP estável global (ADR 0005).
router ospf
 ospf router-id ${router_id}
 redistribute kernel route-map ONLY-CLIENT-32
 network ${transport} area ${area}
 passive-interface default
!
ip prefix-list CLIENT32 seq 5 permit ${space}/${plen} ge 32 le 32
!
route-map ONLY-CLIENT-32 permit 10
 match ip address prefix-list CLIENT32
route-map ONLY-CLIENT-32 deny 20
!
interface ${link}
 ip ospf network point-to-multipoint
 no ip ospf passive
!
OSPF
}

# Habilita e (RE)inicia o FRR. Precisa de restart (não `enable --now`): se o frr
# já estiver rodando (o apt o inicia ao instalar), `enable --now` é no-op e o
# /etc/frr/daemons recém-escrito (ospfd=yes) nunca é aplicado — o ospfd não sobe.
ovpn_frr_enable() {
    systemctl enable frr
    systemctl restart frr
}

# Recarrega o FRR para aplicar mudanças de config (idempotente).
ovpn_frr_reload() {
    systemctl reload frr 2>/dev/null || systemctl restart frr
}

# Aplica o ospfd.conf no daemon em execução (vtysh -f) e persiste (write memory).
# Necessário porque, com o daemon já no ar, o FRR nem sempre recarrega o arquivo
# por-daemon sozinho; o vtysh -f garante o load e o write memory normaliza o
# arquivo (dono frr:frr) para sobreviver ao reboot.
ovpn_frr_apply() {
    vtysh -f "${OVPN_FRR_OSPF_CONF}"
    vtysh -c "write memory" >/dev/null 2>&1 || true
}

# Mostra as rotas OSPF aprendidas (diagnóstico/HITL).
ovpn_frr_show_routes() {
    vtysh -c "show ip route ospf"
}
