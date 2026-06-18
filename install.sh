#!/usr/bin/env bash
# install.sh — assistente principal (menu interativo) do OpenVPN-Installer.
#
# Carrega os módulos de lib/, exige root, valida o sistema operacional e abre
# o menu. Execute como root:
#   sudo ./install.sh
set -euo pipefail

# Resolve o caminho real do script (pode ser chamado por um symlink em
# /usr/local/bin/openvpn-installer — daí precisamos do alvo, não do symlink).
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
export OVPN_INSTALL_SH="${SCRIPT_DIR}/install.sh"

# Ordem importa: módulos básicos primeiro, depois os de domínio e o controller.
for module in core log ui config os_detect deps pki wizard_ipproto server_config ccd client_profile mikrotik_profile firewall gateway frr route_reconcile route_sync mapsync link hub_identity hub_sync dualhub lifecycle upgrade syscmd controller; do
    # shellcheck source=/dev/null
    source "${LIB_DIR}/${module}.sh"
done

ovpn_require_root
ovpn_os_assert_supported

# Move um installer.conf legado para fora de /etc/openvpn (evita o openvpn@installer
# em loop) e carrega as preferências persistidas no ambiente.
ovpn_config_relocate_legacy
ovpn_config_apply

# Subcomando "status": mostra o resumo e sai (sem abrir o menu nem ofertar upgrade).
# Uso: sudo openvpn-installer status
if [[ "${1:-}" == "status" ]]; then
    ovpn_action_status
    exit 0
fi

# Se a instalação é de uma versão anterior, oferece aplicar as correções.
if _ovpn_upgrade_should_offer; then
    ovpn_log_warn "Esta instalação foi feita por uma versão anterior. Há correções disponíveis."
    if ovpn_ui_confirm "Aplicar as correções agora?"; then
        ovpn_upgrade_run
        ovpn_upgrade_report
    fi
fi

ovpn_menu_main
