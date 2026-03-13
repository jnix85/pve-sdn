#!/bin/bash
# clean-sdn.sh — Tear down Proxmox SDN configuration
#
# Usage: clean-sdn.sh [OPTIONS]
#   --vlan    Remove VLAN zone, VNets, and subnets only
#   --evpn    Remove BGP/EVPN controllers, zone, and VNet only
#   --all     Remove everything (default)
#   --force   Skip confirmation prompt
#   --dry-run Print commands without executing them

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
VLAN_ZONE="midgard"
VLAN_VNETS=("legacy" "mgmt" "iot" "secure" "proxmox" "dmz" "deploy" "secalt" "misc")

EVPN_ZONE="${ZONE_ID:-evpnint}"
EVPN_VNET="${VNET_ID:-vnetint}"
BGP_CTRL="${BGP_CTRL_ID:-unifi-peer}"
EVPN_CTRL="${EVPN_CTRL_ID:-evpn-ctrl}"

# ── Flags ─────────────────────────────────────────────────────────────────────
CLEAN_VLAN=false
CLEAN_EVPN=false
DRY_RUN=false
FORCE=false

for arg in "$@"; do
    case "$arg" in
        --vlan)    CLEAN_VLAN=true ;;
        --evpn)    CLEAN_EVPN=true ;;
        --all)     CLEAN_VLAN=true; CLEAN_EVPN=true ;;
        --force|-f) FORCE=true ;;
        --dry-run) DRY_RUN=true ;;
        --help|-h)
            grep '^#' "$0" | head -9 | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown option: $arg  (use --help)" >&2; exit 1 ;;
    esac
done

# Default: remove everything if no scope flag given
if ! $CLEAN_VLAN && ! $CLEAN_EVPN; then
    CLEAN_VLAN=true
    CLEAN_EVPN=true
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
ok()   { echo -e "${GREEN}[  OK ]${NC} $*"; }
warn() { echo -e "${YELLOW}[ WARN]${NC} $*"; }
step() { echo -e "\n${CYAN}[STEP ]${NC} $*"; }

run() {
    if $DRY_RUN; then
        echo "  [dry-run] $*"
    else
        "$@" || warn "Command returned non-zero (may already be removed): $*"
    fi
}

exists() { pvesh get "$1" >/dev/null 2>&1; }

# ── Pre-flight ────────────────────────────────────────────────────────────────
command -v pvesh >/dev/null 2>&1 || die "pvesh not found — run this on a Proxmox VE host."
[[ "$EUID" -eq 0 ]]              || die "This script must be run as root."

$DRY_RUN && warn "Dry-run mode — no changes will be made."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Proxmox SDN Teardown"
$CLEAN_VLAN && echo "  Scope: VLAN (zone: ${VLAN_ZONE})"
$CLEAN_EVPN && echo "  Scope: EVPN (zone: ${EVPN_ZONE})"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Confirmation prompt (skip in dry-run or when --force is set)
if ! $DRY_RUN && ! $FORCE; then
    echo ""
    warn "This will permanently delete SDN configuration. This cannot be undone."
    read -r -p "  Type 'yes' to continue: " CONFIRM
    [[ "$CONFIRM" == "yes" ]] || { echo "Aborted."; exit 0; }
fi

# ── VLAN Teardown ─────────────────────────────────────────────────────────────
if $CLEAN_VLAN; then
    step "Removing VLAN subnets"
    for VNET in "${VLAN_VNETS[@]}"; do
        if ! exists "/cluster/sdn/vnets/${VNET}"; then
            continue
        fi

        if command -v jq >/dev/null 2>&1; then
            SUB_LIST=$(pvesh get "/cluster/sdn/vnets/${VNET}/subnets" \
                --output-format json 2>/dev/null | jq -r '.[].subnet' 2>/dev/null || true)
        else
            SUB_LIST=$(pvesh get "/cluster/sdn/vnets/${VNET}/subnets" \
                --output-format json 2>/dev/null \
                | awk -F'"subnet":"' '{print $2}' | awk -F'"' '{print $1}' || true)
        fi

        for SUB in $SUB_LIST; do
            [[ -z "$SUB" ]] && continue
            echo "  Deleting subnet ${SUB} from ${VNET}..."
            run pvesh delete "/cluster/sdn/vnets/${VNET}/subnets/${SUB/\//%2F}"
        done
    done

    step "Removing VLAN VNets"
    for VNET in "${VLAN_VNETS[@]}"; do
        if exists "/cluster/sdn/vnets/${VNET}"; then
            echo "  Deleting VNet: ${VNET}..."
            run pvesh delete "/cluster/sdn/vnets/${VNET}"
            ok "Deleted VNet '${VNET}'."
        fi
    done

    step "Removing VLAN zone: ${VLAN_ZONE}"
    if exists "/cluster/sdn/zones/${VLAN_ZONE}"; then
        run pvesh delete "/cluster/sdn/zones/${VLAN_ZONE}"
        ok "Deleted zone '${VLAN_ZONE}'."
    else
        ok "Zone '${VLAN_ZONE}' not found — already removed."
    fi
fi

# ── EVPN Teardown ─────────────────────────────────────────────────────────────
if $CLEAN_EVPN; then
    step "Removing EVPN VNet: ${EVPN_VNET}"
    if exists "/cluster/sdn/vnets/${EVPN_VNET}"; then
        run pvesh delete "/cluster/sdn/vnets/${EVPN_VNET}"
        ok "Deleted VNet '${EVPN_VNET}'."
    else
        ok "VNet '${EVPN_VNET}' not found — already removed."
    fi

    step "Removing EVPN zone: ${EVPN_ZONE}"
    if exists "/cluster/sdn/zones/${EVPN_ZONE}"; then
        run pvesh delete "/cluster/sdn/zones/${EVPN_ZONE}"
        ok "Deleted zone '${EVPN_ZONE}'."
    else
        ok "Zone '${EVPN_ZONE}' not found — already removed."
    fi

    step "Removing EVPN controllers"
    for CTRL in "$EVPN_CTRL" "$BGP_CTRL"; do
        if exists "/cluster/sdn/controllers/${CTRL}"; then
            run pvesh delete "/cluster/sdn/controllers/${CTRL}"
            ok "Deleted controller '${CTRL}'."
        else
            ok "Controller '${CTRL}' not found — already removed."
        fi
    done
fi

# ── Apply ─────────────────────────────────────────────────────────────────────
step "Applying SDN configuration"
run pvesh set /cluster/sdn
ok "SDN reloaded."

# Also clear any setup state files so the setup scripts can be re-run cleanly
rm -f /tmp/proxmox-sdn-vlan.state /tmp/proxmox-sdn-evpn.state 2>/dev/null || true

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SDN teardown complete."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
