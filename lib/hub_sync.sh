#!/usr/bin/env bash
# Módulo hub_sync — bundle verificável para compartilhar a CA entre hubs.
# O bundle leva ca.crt + tls-crypt.key + um manifest e um checksum sha256.
# No modo MESTRA, leva também a ca.key (chave privada da CA), para o hub B
# poder emitir os próprios certificados sob a mesma CA.
# A importação recusa o bundle se o checksum não bater (adulterado/corrompido).
# Depende dos módulos core, log e pki.

: "${OVPN_HUB_BUNDLE_VERSION:=openvpn-installer hub bundle v1}"

# Monta o bundle. mode=public (só identidade pública) ou master (inclui ca.key).
_ovpn_hub_export() {
    local bundle="$1" mode="${2:-public}"
    local work
    local -a files=(ca.crt tls-crypt.key)
    work="$(mktemp -d)"

    cp "$(ovpn_pki_ca_cert)" "${work}/ca.crt"
    cp "$(ovpn_pki_tls_crypt)" "${work}/tls-crypt.key"
    if [[ "${mode}" == "master" ]]; then
        cp "$(ovpn_pki_ca_key)" "${work}/ca.key"
        files=(ca.crt ca.key tls-crypt.key)
    fi

    {
        printf '%s\n' "${OVPN_HUB_BUNDLE_VERSION}"
        printf 'mode=%s\n' "${mode}"
    } > "${work}/manifest"
    ( cd "${work}" && sha256sum "${files[@]}" manifest > checksum.sha256 )

    tar czf "${bundle}" -C "${work}" "${files[@]}" manifest checksum.sha256
    rm -rf "${work}"

    if [[ "${mode}" == "master" ]]; then
        ovpn_log_warn "Bundle de CA MESTRA exportado (inclui a chave privada da CA): ${bundle}"
    else
        ovpn_log_ok "Bundle exportado: ${bundle}"
    fi
}

# Exporta só a identidade PÚBLICA da CA (ca.crt + tls-crypt), sem a chave privada.
ovpn_hub_export() {
    _ovpn_hub_export "$1" public
}

# Exporta a CA MESTRA (inclui a ca.key) para o hub B emitir os próprios
# certificados sob a mesma CA. Compartilhe só com um hub plenamente confiável.
ovpn_hub_export_master() {
    _ovpn_hub_export "$1" master
}

# Importa o bundle no diretório de PKI atual, validando o checksum primeiro.
# Se o bundle for mestra (contém ca.key), instala também a chave privada.
ovpn_hub_import() {
    local bundle="$1"
    local work
    work="$(mktemp -d)"
    tar xzf "${bundle}" -C "${work}"

    if ! ( cd "${work}" && sha256sum -c checksum.sha256 >/dev/null 2>&1 ); then
        rm -rf "${work}"
        ovpn_die "Bundle adulterado ou corrompido (checksum inválido)."
    fi

    ovpn_pki_init
    cp "${work}/ca.crt" "$(ovpn_pki_ca_cert)"
    cp "${work}/tls-crypt.key" "$(ovpn_pki_tls_crypt)"

    if [[ -f "${work}/ca.key" ]]; then
        mkdir -p "$(dirname "$(ovpn_pki_ca_key)")"
        cp "${work}/ca.key" "$(ovpn_pki_ca_key)"
        chmod 600 "$(ovpn_pki_ca_key)" 2>/dev/null || true
        rm -rf "${work}"
        ovpn_log_ok "Bundle de CA MESTRA importado (este hub pode emitir certificados): ${bundle}"
        return 0
    fi

    rm -rf "${work}"
    ovpn_log_ok "Bundle importado de ${bundle}."
}
