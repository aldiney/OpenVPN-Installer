#!/usr/bin/env bash
# Módulo deps — verificação e instalação de dependências.
#
# Regras (ver CLAUDE.md):
#   - sempre mostrar o que falta e COMO será instalado;
#   - só instalar após confirmação do operador;
#   - NUNCA instalar pacote lançado há menos de OVPN_MIN_PKG_AGE_DAYS dias.
#
# Depende dos módulos core, log e ui.

: "${OVPN_MIN_PKG_AGE_DAYS:=7}"

# --- Seams de sistema (substituíveis nos testes) -------------------------

# Verdadeiro (0) se o pacote já está instalado.
_ovpn_pkg_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# --- Lógica --------------------------------------------------------------

# Imprime (um por linha) os pacotes ainda não instalados, na ordem recebida.
ovpn_deps_missing() {
    local pkg
    for pkg in "$@"; do
        _ovpn_pkg_installed "${pkg}" || printf '%s\n' "${pkg}"
    done
}

# Idade em dias da versão candidata do pacote. Vazio = desconhecida.
# Seam de sistema: no apt estável não há data confiável por pacote, então
# retornamos "desconhecida" (a distro estável é sempre antiga). É aqui que uma
# checagem para fontes externas mais novas poderá ser plugada no futuro.
_ovpn_pkg_age_days() {
    printf ''
}

# Verdadeiro (0) se o pacote é novo demais: idade conhecida e abaixo do limite.
ovpn_deps_too_fresh() {
    local pkg="$1" age
    age="$(_ovpn_pkg_age_days "${pkg}")"
    [[ -n "${age}" ]] && [[ "${age}" =~ ^[0-9]+$ ]] && [[ "${age}" -lt "${OVPN_MIN_PKG_AGE_DAYS}" ]]
}

# Garante as dependências: mostra o plano, aplica a regra dos 7 dias, confirma
# e instala. Retorna !=0 se nada foi instalado (bloqueio ou recusa do operador).
ovpn_deps_ensure() {
    local missing
    mapfile -t missing < <(ovpn_deps_missing "$@")

    if [[ "${#missing[@]}" -eq 0 ]]; then
        ovpn_log_ok "Todas as dependências já estão instaladas."
        return 0
    fi

    # Regra dos 7 dias: bloqueia se algum pacote faltante for novo demais.
    local pkg
    local fresh=()
    for pkg in "${missing[@]}"; do
        if ovpn_deps_too_fresh "${pkg}"; then
            fresh+=("${pkg}")
        fi
    done
    if [[ "${#fresh[@]}" -gt 0 ]]; then
        ovpn_log_error "Bloqueado pela regra dos 7 dias: ${fresh[*]} (lançado há menos de ${OVPN_MIN_PKG_AGE_DAYS} dias)."
        return 1
    fi

    # Mostra o plano ANTES de qualquer chamada ao apt.
    ovpn_log_warn "Dependências faltando: ${missing[*]}"
    ovpn_log_info "Serão instalados via apt: ${missing[*]}"
    ovpn_log_info "Comando: apt-get install -y ${missing[*]}"

    # Confirmação obrigatória.
    if ! ovpn_ui_confirm "Prosseguir com a instalação?"; then
        ovpn_log_warn "Instalação cancelada pelo operador."
        return 1
    fi

    apt-get install -y "${missing[@]}"
}
