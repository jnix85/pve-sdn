#!/bin/bash
# verify-sdn.sh — Health check for Proxmox SDN configuration
#
# Usage: verify-sdn.sh [OPTIONS]
#   --vlan    Check VLAN zone and VNets only
#   --evpn    Check BGP/EVPN components only
#   (default: check everything)

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
VLAN_ZONE="midgard"
VLAN_VNETS=("legacy" "mgmt" "iot" "secure" "proxmox" "dmz" "deploy" "secalt" "misc")

EVPN_ZONE="${ZONE_ID:-evpn_int}"
EVPN_VNET="${VNET_ID:-vnet_int}"
BGP_CTRL="${BGP_CTRL_ID:-unifi-peer}"
EVPN_CTRL="${EVPN_CTRL_ID:-evpn-ctrl}"

# ── Flags ─────────────────────────────────────────────────────────────────────
CHECK_VLAN=true
CHECK_EVPN=true

for arg in "$@"; do
    case "$arg" in
        --vlan)   CHECK_EVPN=false ;;
        --evpn)   CHECK_VLAN=false ;;
        --help|-h)
            grep '^#' "$0" | head -8 | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown option: $arg  (use --help)" >&2; exit 1 ;;
    esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✔${NC}  $*"; }
fail() { echo -e "  ${RED}✘${NC}  $*"; FAILURES=$((FAILURES + 1)); }
warn() { echo -e "  ${YELLOW}!${NC}  $*"; }
section() { echo -e "\n${CYAN}▶ $*${NC}"; }

FAILURES=0

exists() { pvesh get "$1" >/dev/null 2>&1; }

# ── Pre-flight ────────────────────────────────────────────────────────────────
command -v pvesh >/dev/null 2>&1 || { echo "pvesh not found — run this on a Proxmox VE host." >&2; exit 1; }
[[ "$EUID" -eq 0 ]]              || { echo "This script must be run as root." >&2; exit 1; }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Proxmox SDN Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── VLAN checks ───────────────────────────────────────────────────────────────
if $CHECK_VLAN; then
    section "VLAN Zone: ${VLAN_ZONE}"
    if exists "/cluster/sdn/zones/${VLAN_ZONE}"; then
        ok "Zone '${VLAN_ZONE}' exists."
    else
        fail "Zone '${VLAN_ZONE}' NOT found. Run: setup-sdn.sh"
    fi

    section "VLAN VNets"
    for VNET in "${VLAN_VNETS[@]}"; do
        if exists "/cluster/sdn/vnets/${VNET}"; then
            ok "VNet '${VNET}'"
        else
            fail "VNet '${VNET}' NOT found."
        fi
    done
fi

# ── EVPN checks ───────────────────────────────────────────────────────────────
if $CHECK_EVPN; then
    section "EVPN Controllers"
    if exists "/cluster/sdn/controllers/${BGP_CTRL}"; then
        ok "BGP controller '${BGP_CTRL}' exists."
    else
        fail "BGP controller '${BGP_CTRL}' NOT found. Run: setup-evpn.sh"
    fi

    if exists "/cluster/sdn/controllers/${EVPN_CTRL}"; then
        ok "EVPN controller '${EVPN_CTRL}' exists."
    else
        fail "EVPN controller '${EVPN_CTRL}' NOT found. Run: setup-evpn.sh"
    fi

    section "EVPN Zone & VNet"
    if exists "/cluster/sdn/zones/${EVPN_ZONE}"; then
        ok "Zone '${EVPN_ZONE}' exists."
    else
        fail "Zone '${EVPN_ZONE}' NOT found. Run: setup-evpn.sh"
    fi

    if exists "/cluster/sdn/vnets/${EVPN_VNET}"; then
        ok "VNet '${EVPN_VNET}' exists."
    else
        fail "VNet '${EVPN_VNET}' NOT found. Run: setup-evpn.sh"
    fi

    section "FRR / BGP Status"
    if command -v vtysh >/dev/null 2>&1; then
        BGP_SUMMARY=$(vtysh -c "show bgp summary" 2>/dev/null || true)
        if echo "$BGP_SUMMARY" | grep -q "Established"; then
            ok "BGP session is Established."
        else
            warn "BGP session not yet Established (peer may need to be configured)."
            echo ""
            echo "$BGP_SUMMARY" | head -20 | sed 's/^/    /'
        fi

        EVPN_STATUS=$(vtysh -c "show evpn vni" 2>/dev/null || true)
        if [[ -n "$EVPN_STATUS" ]]; then
            ok "EVPN VNIs are active:"
            echo "$EVPN_STATUS" | sed 's/^/    /'
        else
            warn "No active EVPN VNIs found."
        fi
    else
        warn "vtysh not found — skipping live BGP check (FRR may not be installed)."
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$FAILURES" -eq 0 ]]; then
    echo -e "  ${GREEN}All checks passed.${NC}"
else
    echo -e "  ${RED}${FAILURES} check(s) failed.${NC}  Review output above."
    exit 1
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
