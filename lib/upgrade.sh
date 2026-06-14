#!/usr/bin/env bash
# Módulo upgrade — aplica correções (migrações) numa instalação já existente,
# SEM NUNCA quebrar clientes. Cada migração é idempotente e detecta antes de agir.
#
# Invariantes (ver issue/PRD): nunca tocar na CA nem em certs/.ovpn de cliente;
# só reemitir o cert do SERVIDOR (mesma CA) e ACRESCENTAR diretivas faltantes ao
# server.conf (nunca re-renderizar). Mudanças de rota/comportamento são só
# reportadas (ovpn_upgrade_report), nunca aplicadas automaticamente.
# Depende de core, log, ui, pki, server_config e firewall.

# Versão do "schema" da instalação. Bumpar ao adicionar migrações.
OVPN_SCHEMA_VERSION=3

# --- Carimbo de versão ----------------------------------------------------

ovpn_upgrade_stamp_path() { printf '%s' "${OVPN_ETC}/.installer-version"; }

# Lê o carimbo; 0 se ausente, ilegível ou não-numérico (corruption-safe).
_ovpn_upgrade_read_stamp() {
    local n
    n="$(cat "$(ovpn_upgrade_stamp_path)" 2>/dev/null)"
    if [[ "${n}" =~ ^[0-9]+$ ]]; then
        printf '%s' "${n}"
    else
        printf '0'
    fi
}

_ovpn_upgrade_write_stamp() {
    mkdir -p "${OVPN_ETC}"
    printf '%s\n' "$1" > "$(ovpn_upgrade_stamp_path)"
}

# --- Detecção / seams -----------------------------------------------------

# Há uma instalação? (server.conf presente)
_ovpn_upgrade_has_install() {
    [[ -f "$(ovpn_server_conf_path)" ]]
}

# Deve oferecer upgrade? há instalação E carimbo < versão atual.
_ovpn_upgrade_should_offer() {
    _ovpn_upgrade_has_install || return 1
    [[ "$(_ovpn_upgrade_read_stamp)" -lt "${OVPN_SCHEMA_VERSION}" ]]
}

# Marca que houve mudança nesta execução.
_ovpn_upgrade_mark_changed() {
    OVPN_UPGRADE_CHANGED=$(( ${OVPN_UPGRADE_CHANGED:-0} + 1 ))
}

# Seam: reinicia o serviço.
_ovpn_upgrade_restart() {
    systemctl restart "openvpn-server@${OVPN_SERVER_NAME}"
}

# Seam: o cert tem Key Usage + EKU serverAuth? 0=sim, 1=não, 2=indeterminado.
# Retorna 2 só quando não dá para verificar (openssl ausente ou cert ilegível);
# extensão ausente conta como "não tem" (1), não como indeterminado.
_ovpn_upgrade_cert_has_ku() {
    local cert="$1" out
    command -v openssl >/dev/null 2>&1 || return 2
    [[ -r "${cert}" ]] || return 2
    out="$(openssl x509 -in "${cert}" -noout -ext keyUsage,extendedKeyUsage 2>/dev/null)"
    [[ "${out}" == *"Key Usage"* && "${out}" == *"TLS Web Server Authentication"* ]]
}

# Lê a porta do server.conf (default 1194).
_ovpn_upgrade_conf_port() {
    local p
    p="$(awk '/^port /{print $2; exit}' "$1" 2>/dev/null)"
    [[ -n "${p}" ]] && printf '%s' "${p}" || printf '1194'
}

# Lê o proto base do server.conf (tira o sufixo 6; default udp).
_ovpn_upgrade_conf_proto() {
    local p
    p="$(awk '/^proto /{print $2; exit}' "$1" 2>/dev/null)"
    p="${p%6}"
    [[ -n "${p}" ]] && printf '%s' "${p}" || printf 'udp'
}

# Seam: a porta já está aberta no firewall ativo?
_ovpn_upgrade_port_is_open() {
    local port="$1" proto="$2"
    case "$(_ovpn_firewall_backend)" in
        ufw)
            ufw status 2>/dev/null | awk -v p="${port}/${proto}" 'index($0,p){f=1} END{exit !f}'
            ;;
        nft)
            nft list ruleset 2>/dev/null | awk -v p="dport ${port}" 'index($0,p){f=1} END{exit !f}'
            ;;
        *)
            iptables -C INPUT -p "${proto}" --dport "${port}" -j ACCEPT 2>/dev/null
            ;;
    esac
}

# --- Migrações (idempotentes) ---------------------------------------------

# Cert do servidor sem Key Usage/EKU -> reemite (mesma CA).
_ovpn_mig_server_cert_ku() {
    local cert="${OVPN_PKI_DIR}/issued/${OVPN_SERVER_NAME}.crt"
    [[ -f "${cert}" ]] || { ovpn_log_warn "Cert do servidor não encontrado — pulando."; return 0; }
    _ovpn_upgrade_cert_has_ku "${cert}"
    local rc=$?
    if [[ "${rc}" -eq 0 ]]; then
        return 0
    elif [[ "${rc}" -eq 2 ]]; then
        ovpn_log_warn "Não deu para verificar o Key Usage do cert (openssl ausente?) — pulando."
        return 0
    fi
    ovpn_pki_reissue_server "${OVPN_SERVER_NAME}" || return 1
    _ovpn_upgrade_mark_changed
    ovpn_log_ok "Cert do servidor reemitido (Key Usage/EKU corrigidos) — mesma CA, clientes seguem confiando."
}

# server.conf sem mssfix -> acrescenta (append cirúrgico).
_ovpn_mig_mssfix() {
    local conf
    conf="$(ovpn_server_conf_path)"
    if awk '/^mssfix /{f=1} END{exit !f}' "${conf}"; then
        return 0
    fi
    printf 'mssfix %s\n' "${OVPN_MSSFIX}" >> "${conf}"
    _ovpn_upgrade_mark_changed
    ovpn_log_ok "server.conf: mssfix ${OVPN_MSSFIX} adicionado."
}

# Porta de escuta não liberada no firewall -> abre (lendo porta/proto do conf).
_ovpn_mig_firewall_port() {
    local conf port proto
    conf="$(ovpn_server_conf_path)"
    port="$(_ovpn_upgrade_conf_port "${conf}")"
    proto="$(_ovpn_upgrade_conf_proto "${conf}")"
    if _ovpn_upgrade_port_is_open "${port}" "${proto}"; then
        return 0
    fi
    ovpn_firewall_open_port "${port}" "${proto}"
    _ovpn_upgrade_mark_changed
}

# Registro ordenado das migrações.
_ovpn_upgrade_migrations() {
    printf '%s\n' \
        _ovpn_mig_server_cert_ku \
        _ovpn_mig_mssfix \
        _ovpn_mig_firewall_port
}

# --- Orquestração ---------------------------------------------------------

# Aplica as migrações pendentes; reinicia o serviço só se algo mudou; carimba.
ovpn_upgrade_run() {
    ovpn_require_root

    if ! _ovpn_upgrade_has_install; then
        ovpn_log_info "Nenhuma instalação detectada — nada a migrar."
        return 0
    fi

    OVPN_UPGRADE_CHANGED=0
    local mig
    while read -r mig; do
        [[ -n "${mig}" ]] || continue
        if ! "${mig}"; then
            ovpn_log_error "Migração ${mig} falhou — abortando (nada carimbado)."
            return 1
        fi
    done < <(_ovpn_upgrade_migrations)

    if [[ "${OVPN_UPGRADE_CHANGED:-0}" -gt 0 ]]; then
        ovpn_log_step "Reiniciando o serviço para aplicar as mudanças..."
        _ovpn_upgrade_restart
        ovpn_log_ok "Migração concluída. ${OVPN_UPGRADE_CHANGED} correção(ões) aplicada(s)."
    else
        ovpn_log_ok "Instalação já está atualizada — nada a corrigir."
    fi

    _ovpn_upgrade_write_stamp "${OVPN_SCHEMA_VERSION}"
}

# Reporta (só leitura) achados que mexem em rota/comportamento — NÃO altera nada.
ovpn_upgrade_report() {
    local conf
    conf="$(ovpn_server_conf_path)"
    [[ -f "${conf}" ]] || return 0

    if awk '/redirect-gateway/{f=1} END{exit !f}' "${conf}"; then
        ovpn_log_warn "Detectado 'redirect-gateway' global no server.conf: força TODOS os clientes pela internet do hub. O modelo atual é por-cliente (ccd). NÃO alterado automaticamente."
    fi

    local count
    count="$(find "${OVPN_SERVER_DIR}" -maxdepth 1 -name '*.conf' 2>/dev/null | wc -l)"
    if [[ "${count}" -gt 1 ]]; then
        ovpn_log_warn "Detectadas ${count} instâncias de servidor; a migração tratou apenas '${OVPN_SERVER_NAME}'. Rode de novo com OVPN_SERVER_NAME=<outra>."
    fi
}
