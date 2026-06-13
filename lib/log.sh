#!/usr/bin/env bash
# Módulo log — mensagens para o operador.
# Mensagens de erro/aviso vão para o stderr; as demais, para o stdout.
# Cores só são usadas quando a saída é um terminal e NO_COLOR não está definido.

# Uso interno: _ovpn_log_color <fd> retorna 0 se devemos colorir aquele fd.
_ovpn_log_color() {
    [[ -z "${NO_COLOR:-}" ]] && [[ -t "$1" ]]
}

# Informação comum (stdout).
ovpn_log_info() {
    printf '%s\n' "$*"
}

# Sucesso (stdout, verde quando há terminal).
ovpn_log_ok() {
    if _ovpn_log_color 1; then
        printf '\033[0;32m  OK\033[0m  %s\n' "$*"
    else
        printf '  OK  %s\n' "$*"
    fi
}

# Início de uma etapa (stdout, azul quando há terminal).
ovpn_log_step() {
    if _ovpn_log_color 1; then
        printf '\033[0;34m==>\033[0m %s\n' "$*"
    else
        printf '==> %s\n' "$*"
    fi
}

# Aviso (stderr, amarelo quando há terminal).
ovpn_log_warn() {
    if _ovpn_log_color 2; then
        printf '\033[1;33mAVISO\033[0m %s\n' "$*" >&2
    else
        printf 'AVISO %s\n' "$*" >&2
    fi
}

# Erro (stderr, vermelho quando há terminal).
ovpn_log_error() {
    if _ovpn_log_color 2; then
        printf '\033[0;31mERRO\033[0m  %s\n' "$*" >&2
    else
        printf 'ERRO  %s\n' "$*" >&2
    fi
}
