#!/usr/bin/env bash
# Módulo os_detect — identifica o sistema operacional e valida o suporte.
# Alvos suportados: Debian 12+ e Ubuntu 24.04+.
# Carregado via `source`; não é executado diretamente.

: "${OVPN_OS_RELEASE_FILE:=/etc/os-release}"

# Lê um campo do os-release (ex.: ID, VERSION_ID) sem usar `source`
# (evita efeitos colaterais de um arquivo arbitrário). Stdout = valor sem aspas.
_ovpn_os_field() {
    local key="$1" line
    [[ -r "${OVPN_OS_RELEASE_FILE}" ]] || return 1
    line="$(grep -E "^${key}=" "${OVPN_OS_RELEASE_FILE}" | head -1)" || return 1
    line="${line#*=}"
    line="${line%\"}"
    line="${line#\"}"
    printf '%s' "${line}"
}

# ID da distribuição (ex.: debian, ubuntu).
ovpn_os_id() {
    _ovpn_os_field ID
}

# Versão da distribuição (ex.: 12, 24.04).
ovpn_os_version_id() {
    _ovpn_os_field VERSION_ID
}

# Verdadeiro (0) se o sistema é um alvo suportado (Debian 12+ ou Ubuntu 24.04+).
ovpn_os_is_supported() {
    local id version major minor
    id="$(ovpn_os_id)" || return 1
    version="$(ovpn_os_version_id)" || return 1
    major="${version%%.*}"
    [[ "${major}" =~ ^[0-9]+$ ]] || return 1

    case "${id}" in
        debian)
            [[ "${major}" -ge 12 ]]
            ;;
        ubuntu)
            minor="${version#*.}"
            [[ "${minor}" =~ ^[0-9]+$ ]] || minor=0
            minor="$((10#${minor}))"
            if [[ "${major}" -gt 24 ]]; then
                return 0
            fi
            [[ "${major}" -eq 24 ]] && [[ "${minor}" -ge 4 ]]
            ;;
        *)
            return 1
            ;;
    esac
}

# Aborta com mensagem clara se o sistema não for suportado.
ovpn_os_assert_supported() {
    if ! ovpn_os_is_supported; then
        ovpn_die "Sistema não suportado: $(ovpn_os_id) $(ovpn_os_version_id). Suportados: Debian 12+ e Ubuntu 24.04+."
    fi
}
