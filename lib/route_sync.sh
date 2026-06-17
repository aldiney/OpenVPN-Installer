#!/usr/bin/env bash
# Módulo route_sync — sincroniza o mapa cliente->IP entre os hubs do domínio.
#
# Para o IP estável global, todos os hubs precisam atribuir o MESMO IP ao mesmo
# cliente. A fonte de verdade é o hub primário (que aloca); este módulo exporta
# o mapa (linhas ifconfig-push do ccd) num bundle verificável (estilo hub_sync,
# com checksum) marcado pelo DOMAIN_ID, e o importa nos demais hubs — recusando
# bundle de outro domínio (protege implantações isoladas). Ver ADR 0005.
# Depende dos módulos core, log e ccd.

: "${OVPN_ROUTE_BUNDLE_VERSION:=openvpn-installer client-map v1}"
: "${OVPN_DOMAIN_ID:=default}"
: "${OVPN_SUBNET_V4:=10.8.0.0}"
: "${OVPN_NETMASK_V4:=255.255.255.0}"

# Exporta o mapa cliente->IP (só as linhas ifconfig-push) num bundle .tar.gz
# verificável, marcado pelo domínio e pelo espaço.
ovpn_route_sync_export() {
    local bundle="$1" work dir f name line
    work="$(mktemp -d)"
    dir="$(ovpn_ccd_dir)"
    : > "${work}/clients.map"
    if [[ -d "${dir}" ]]; then
        for f in "${dir}"/*; do
            [[ -e "${f}" ]] || continue
            name="$(basename "${f}")"
            line="$(awk '/ifconfig-push/ {print $2, $3; exit}' "${f}")"
            if [[ -n "${line}" ]]; then
                printf '%s %s\n' "${name}" "${line}" >> "${work}/clients.map"
            fi
        done
    fi
    {
        printf '%s\n' "${OVPN_ROUTE_BUNDLE_VERSION}"
        printf 'domain=%s\n' "${OVPN_DOMAIN_ID}"
        printf 'space=%s\n' "${OVPN_SUBNET_V4}"
        printf 'mask=%s\n' "${OVPN_NETMASK_V4}"
    } > "${work}/manifest"
    ( cd "${work}" && sha256sum clients.map manifest > checksum.sha256 )
    tar czf "${bundle}" -C "${work}" clients.map manifest checksum.sha256
    rm -rf "${work}"
    ovpn_log_ok "Mapa de clientes exportado: ${bundle}"
}

# Aplica o ifconfig-push de um cliente no ccd local, preservando as demais
# linhas (iroute, push). Idempotente.
_ovpn_route_sync_apply_one() {
    local file="$1" ip="$2" mask="$3" tmp
    if [[ -f "${file}" ]]; then
        tmp="$(mktemp)"
        awk '!/ifconfig-push/' "${file}" > "${tmp}"
        printf 'ifconfig-push %s %s\n' "${ip}" "${mask}" >> "${tmp}"
        mv "${tmp}" "${file}"
    else
        printf 'ifconfig-push %s %s\n' "${ip}" "${mask}" > "${file}"
    fi
}

# Importa o mapa, validando o checksum e o domínio. Recusa bundle de outro
# domínio (protege implantações isoladas). Idempotente.
ovpn_route_sync_import() {
    local bundle="$1" work dom dir name ip mask
    work="$(mktemp -d)"
    tar xzf "${bundle}" -C "${work}"
    if ! ( cd "${work}" && sha256sum -c checksum.sha256 >/dev/null 2>&1 ); then
        rm -rf "${work}"
        ovpn_die "Bundle de mapa adulterado ou corrompido (checksum inválido)."
    fi
    dom="$(awk -F= '/^domain=/{print $2}' "${work}/manifest")"
    if [[ "${dom}" != "${OVPN_DOMAIN_ID}" ]]; then
        rm -rf "${work}"
        ovpn_die "Bundle de outro domínio (${dom} != ${OVPN_DOMAIN_ID}) — recusado."
    fi
    dir="$(ovpn_ccd_dir)"
    mkdir -p "${dir}"
    while read -r name ip mask; do
        [[ -n "${name}" ]] || continue
        _ovpn_route_sync_apply_one "${dir}/${name}" "${ip}" "${mask}"
    done < "${work}/clients.map"
    rm -rf "${work}"
    ovpn_log_ok "Mapa de clientes importado de ${bundle}."
}
