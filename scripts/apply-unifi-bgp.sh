#!/bin/bash
# apply-unifi-bgp.sh — Apply BGP config to UniFi gateway and make it persistent
#
# Usage: apply-unifi-bgp.sh <gateway-ip> [--dry-run]
#
# Run this from your workstation (not the Proxmox host).
# Requires: ssh access to the UniFi gateway as root or ubnt.
set -x 

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BGP_CONF="${SCRIPT_DIR}/../proxmox-bgp.conf"
REMOTE_PATH="/etc/frr/bgp-proxmox.conf"
HOOK_PATH="/etc/network/if-up.d/bgp-proxmox"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
ok()   { echo -e "${GREEN}[  OK ]${NC} $*"; }
step() { echo -e "\n${CYAN}[STEP ]${NC} $*"; }

GW_IP="${1:-}"
DRY_RUN=false
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=true

[[ -n "$GW_IP" ]] || die "Usage: $0 <gateway-ip> [--dry-run]"
[[ -f "$BGP_CONF" ]] || die "BGP config not found: $BGP_CONF"

SSH="ssh unifinetwork@${GW_IP}"
SCP="scp"

$DRY_RUN && echo -e "${YELLOW}[DRY-RUN]${NC} No changes will be made."

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Applying BGP config to UniFi gateway: ${GW_IP}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Step 1: Copy config to gateway ────────────────────────────────────────────
step "Copying proxmox-bgp.conf → ${GW_IP}:${REMOTE_PATH}"
if ! $DRY_RUN; then
    $SCP "$BGP_CONF" "root@${GW_IP}:${REMOTE_PATH}"
    ok "Config copied."
else
    echo "  [dry-run] scp $BGP_CONF root@${GW_IP}:${REMOTE_PATH}"
fi

# ── Step 2: Apply via vtysh ────────────────────────────────────────────────────
step "Applying config via vtysh"
if ! $DRY_RUN; then
    $SSH "vtysh -f ${REMOTE_PATH} && vtysh -c 'write memory'"
    ok "Config applied and saved."
else
    echo "  [dry-run] ssh root@${GW_IP} 'vtysh -f ${REMOTE_PATH} && vtysh -c write memory'"
fi

# ── Step 3: Install persistence hook ──────────────────────────────────────────
# UniFi can overwrite FRR config on restart; this hook re-applies after
# the network interface comes up.
step "Installing persistence hook at ${HOOK_PATH}"
HOOK_SCRIPT="#!/bin/sh
# Re-apply BGP config after network restart (survives controller restarts)
vtysh -f ${REMOTE_PATH} && vtysh -c 'write memory'
"
if ! $DRY_RUN; then
    $SSH "cat > ${HOOK_PATH} << 'EOF'
${HOOK_SCRIPT}
EOF
chmod +x ${HOOK_PATH}"
    ok "Persistence hook installed."
else
    echo "  [dry-run] Would install hook at root@${GW_IP}:${HOOK_PATH}"
fi

# ── Step 4: Verify ────────────────────────────────────────────────────────────
step "Verifying BGP session"
if ! $DRY_RUN; then
    echo ""
    $SSH "vtysh -c 'show bgp summary'" || true
else
    echo "  [dry-run] ssh root@${GW_IP} 'vtysh -c show bgp summary'"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "Done. Neighbors should show 'Established' above."
echo "  If not yet established, ensure setup-evpn.sh has been run on"
echo "  each Proxmox node and BGP is up on the Proxmox side:"
echo "    vtysh -c 'show bgp summary'  (run on each Proxmox host)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
