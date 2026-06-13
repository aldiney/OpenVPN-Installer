#!/usr/bin/env bash
# Módulo hub_sync — bundle verificável para compartilhar a CA entre hubs.
# O bundle leva ca.crt + tls-crypt.key + um manifest e um checksum sha256.
# A importação recusa o bundle se o checksum não bater (adulterado/corrompido).
# Depende dos módulos core, log e pki.

: "${OVPN_HUB_BUNDLE_VERSION:=openvpn-installer hub bundle v1}"

# Exporta a identidade da CA num bundle .tar.gz verificável.
ovpn_hub_export() {
    local bundle="$1"
    local work
    work="$(mktemp -d)"

    cp "$(ovpn_pki_ca_cert)" "${work}/ca.crt"
    cp "$(ovpn_pki_tls_crypt)" "${work}/tls-crypt.key"
    printf '%s\n' "${OVPN_HUB_BUNDLE_VERSION}" > "${work}/manifest"
    ( cd "${work}" && sha256sum ca.crt tls-crypt.key manifest > checksum.sha256 )

    tar czf "${bundle}" -C "${work}" ca.crt tls-crypt.key manifest checksum.sha256
    rm -rf "${work}"
    ovpn_log_ok "Bundle exportado: ${bundle}"
}

# Importa o bundle no diretório de PKI atual, validando o checksum primeiro.
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
    rm -rf "${work}"
    ovpn_log_ok "Bundle importado de ${bundle}."
}
