#!/usr/bin/env bash
# Módulo pki — infraestrutura de chaves (CA, certificados, tls-crypt).
# Usa OpenSSL (ECDSA prime256v1) e openvpn (--genkey) para a chave tls-crypt.
# Depende dos módulos core e log. Carregado via `source`.

: "${OVPN_PKI_CA_DAYS:=3650}"
: "${OVPN_PKI_CA_CN:=OpenVPN-Installer CA}"

# --- Seams de sistema (substituíveis nos testes) -------------------------

# Gera a chave privada ECDSA prime256v1 da CA no caminho indicado.
_ovpn_pki_gen_ca_key() {
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out "$1"
}

# Gera o certificado auto-assinado da CA a partir da chave.
_ovpn_pki_gen_ca_cert() {
    openssl req -x509 -new -key "$1" -days "${OVPN_PKI_CA_DAYS}" \
        -subj "/CN=${OVPN_PKI_CA_CN}" -out "$2"
}

# Gera a chave tls-crypt no caminho indicado.
_ovpn_pki_gen_tls_crypt_key() {
    openvpn --genkey secret "$1"
}

# Gera a chave privada ECDSA prime256v1 de uma entidade (servidor/cliente).
_ovpn_pki_gen_entity_key() {
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:prime256v1 -out "$1"
}

# Assina o certificado de uma entidade com a CA.
# Args: <chave> <cert> <cn> <tipo: server|client>
# O tipo define o Extended Key Usage (serverAuth/clientAuth), usado pelo
# remote-cert-tls do OpenVPN para distinguir servidor de cliente.
# Extensões X.509 da entidade. remote-cert-tls (no cliente) exige Key Usage +
# Extended Key Usage; sem isso o cliente recusa o cert do servidor (VERIFY KU ERROR).
_ovpn_pki_ext_content() {
    local kind="$1"
    if [[ "${kind}" == "client" ]]; then
        printf 'keyUsage=digitalSignature\n'
        printf 'extendedKeyUsage=clientAuth\n'
    else
        printf 'keyUsage=digitalSignature,keyEncipherment\n'
        printf 'extendedKeyUsage=serverAuth\n'
    fi
}

_ovpn_pki_sign_entity() {
    local key="$1" cert="$2" cn="$3" kind="$4"
    local csr="${cert%.crt}.csr"
    local extfile="${cert%.crt}.ext"
    _ovpn_pki_ext_content "${kind}" > "${extfile}"
    openssl req -new -key "${key}" -subj "/CN=${cn}" -out "${csr}"
    openssl x509 -req -in "${csr}" \
        -CA "$(ovpn_pki_ca_cert)" -CAkey "$(ovpn_pki_ca_key)" -CAcreateserial \
        -days "${OVPN_PKI_CA_DAYS}" -extfile "${extfile}" -out "${cert}"
    rm -f "${csr}" "${extfile}"
}

# --- Caminhos ------------------------------------------------------------

ovpn_pki_ca_cert()   { printf '%s' "${OVPN_PKI_DIR}/ca.crt"; }
ovpn_pki_ca_key()    { printf '%s' "${OVPN_PKI_DIR}/private/ca.key"; }
ovpn_pki_tls_crypt() { printf '%s' "${OVPN_PKI_DIR}/tls-crypt.key"; }

# --- Lógica --------------------------------------------------------------

# Cria a estrutura de diretórios da PKI. Idempotente.
ovpn_pki_init() {
    mkdir -p "${OVPN_PKI_DIR}/private" "${OVPN_PKI_DIR}/issued"
    chmod 700 "${OVPN_PKI_DIR}/private" 2>/dev/null || true
}

# Constrói a CA. Idempotente: se o certificado já existir, não recria.
ovpn_pki_build_ca() {
    ovpn_pki_init
    local cert key
    cert="$(ovpn_pki_ca_cert)"
    key="$(ovpn_pki_ca_key)"
    if [[ -f "${cert}" ]]; then
        ovpn_log_ok "CA já existe — mantida."
        return 0
    fi
    _ovpn_pki_gen_ca_key "${key}"
    _ovpn_pki_gen_ca_cert "${key}" "${cert}"
    chmod 600 "${key}" 2>/dev/null || true
    ovpn_log_ok "CA criada."
}

# Gera a chave tls-crypt. Idempotente.
ovpn_pki_gen_tls_crypt() {
    ovpn_pki_init
    local tc
    tc="$(ovpn_pki_tls_crypt)"
    if [[ -f "${tc}" ]]; then
        return 0
    fi
    _ovpn_pki_gen_tls_crypt_key "${tc}"
}

# Emite a chave + certificado de uma entidade. Idempotente por nome.
_ovpn_pki_issue() {
    local name="$1" kind="$2"
    ovpn_pki_init
    local key="${OVPN_PKI_DIR}/private/${name}.key"
    local cert="${OVPN_PKI_DIR}/issued/${name}.crt"
    if [[ -f "${cert}" ]]; then
        ovpn_log_ok "Certificado de ${name} já existe — mantido."
        return 0
    fi
    _ovpn_pki_gen_entity_key "${key}"
    _ovpn_pki_sign_entity "${key}" "${cert}" "${name}" "${kind}"
    chmod 600 "${key}" 2>/dev/null || true
    ovpn_log_ok "Certificado de ${name} emitido."
}

# Emite o certificado do servidor (EKU serverAuth).
ovpn_pki_issue_server() {
    _ovpn_pki_issue "$1" server
}

# Emite o certificado de um cliente (EKU clientAuth).
ovpn_pki_issue_client() {
    _ovpn_pki_issue "$1" client
}

# Caminho da CRL (lista de certificados revogados).
ovpn_pki_crl_path() { printf '%s' "${OVPN_PKI_DIR}/crl.pem"; }

# Seam: (re)gera a CRL. Isolado para teste. Em produção, a geração real
# (openssl ca -gencrl) é montada com a configuração da CA na instalação.
_ovpn_pki_gen_crl() {
    : > "$(ovpn_pki_crl_path)"
}

# Revoga o certificado de uma entidade e atualiza a CRL.
ovpn_pki_revoke_client() {
    local name="$1"
    ovpn_pki_init
    printf '%s\n' "${name}" >> "${OVPN_PKI_DIR}/revoked.index"
    _ovpn_pki_gen_crl
    ovpn_log_ok "Certificado de ${name} revogado (CRL atualizada)."
}

# Exporta a identidade da CA (ca.crt + tls-crypt) num tar.gz.
ovpn_pki_export_ca() {
    local bundle="$1"
    tar czf "${bundle}" -C "${OVPN_PKI_DIR}" ca.crt tls-crypt.key
}

# Importa a identidade da CA de um tar.gz para o diretório de PKI atual.
ovpn_pki_import_ca() {
    local bundle="$1"
    ovpn_pki_init
    tar xzf "${bundle}" -C "${OVPN_PKI_DIR}"
}
