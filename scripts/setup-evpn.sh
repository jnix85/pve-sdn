#!/bin/bash
# setup-evpn.sh — Configure Proxmox BGP/EVPN overlay for UniFi peering
#
# Usage: setup-evpn.sh [OPTIONS]
#   --dry-run   Print commands without executing them
#   --reset     Clear saved progress and start from the beginning
#
# Override defaults via environment variables before running:
#   ROUTER_IP=10.24.0.1 PROXMOX_ASN=65002 ./setup-evpn.sh

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
ROUTER_IP="${ROUTER_IP:-10.24.0.1}"      # UniFi Gateway IP
PROXMOX_ASN="${PROXMOX_ASN:-65002}"      # Proxmox Local ASN
BGP_CTRL_ID="${BGP_CTRL_ID:-unifi-peer}" # BGP controller name
EVPN_CTRL_ID="${EVPN_CTRL_ID:-evpn-ctrl}" # EVPN controller name
ZONE_ID="${ZONE_ID:-evpnint}"           # SDN Zone name
VNET_ID="${VNET_ID:-vnetint}"           # VNet name
VNET_TAG="${VNET_TAG:-1000}"             # VXLAN VNI/Tag
VRF_VXLAN="${VRF_VXLAN:-10000}"          # VRF VXLAN tag for the zone
STATE_FILE="/tmp/proxmox-sdn-evpn.state"

# ── Flags ─────────────────────────────────────────────────────────────────────
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --reset)   rm -f "$STATE_FILE"; echo "State cleared. Re-run to start from the beginning."; exit 0 ;;
        --help|-h)
            grep '^#' "$0" | head -10 | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown option: $arg  (use --help)" >&2; exit 1 ;;
    esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
ok()   { echo -e "${GREEN}[  OK ]${NC} $*"; }
warn() { echo -e "${YELLOW}[ WARN]${NC} $*"; }
step() { echo -e "\n${CYAN}[STEP ]${NC} $*"; }

step_done() { grep -qxF "$1" "$STATE_FILE" 2>/dev/null; }
mark_done() { echo "$1" >> "$STATE_FILE"; }

run() {
    if $DRY_RUN; then
        echo "  [dry-run] $*"
    else
        "$@" || die "Command failed: $*"
    fi
}

# ── Pre-flight checks ─────────────────────────────────────────────────────────
command -v pvesh >/dev/null 2>&1 || die "pvesh not found — run this on a Proxmox VE host."
[[ "$EUID" -eq 0 ]]              || die "This script must be run as root."

# BGP controllers are node-scoped; detect the local node name.
# Use hostname first (Proxmox node name == hostname), validate against cluster.
PVE_NODE="${PVE_NODE:-$(hostname -s)}"
# If hostname doesn't match a known cluster node, fall back to cluster API local node
if ! pvesh get /nodes/"$PVE_NODE"/status --output-format json &>/dev/null; then
    _api_node=$(pvesh get /cluster/status --output-format json 2>/dev/null \
        | python3 -c "import sys,json; nodes=[n for n in json.load(sys.stdin) if n.get('local')]; print(nodes[0]['name'] if nodes else '')" 2>/dev/null)
    PVE_NODE="${_api_node:-$PVE_NODE}"
fi

$DRY_RUN && warn "Dry-run mode — no changes will be made."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Proxmox BGP/EVPN Setup"
echo "  Proxmox ASN : ${PROXMOX_ASN}"
echo "  Router Peer : ${ROUTER_IP}"
echo "  Node        : ${PVE_NODE}"
echo "  Zone        : ${ZONE_ID}  |  VNet: ${VNET_ID}  |  VNI: ${VNET_TAG}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Step 1: Ensure FRR is installed ──────────────────────────────────────────
STEP_ID="frr_installed"
step "FRR package"
if step_done "$STEP_ID"; then
    ok "Already completed — skipping."
else
    if dpkg -s frr >/dev/null 2>&1; then
        ok "FRR is already installed."
    else
        warn "FRR not found — installing..."
        run apt-get update -qq
        run apt-get install -y frr
        ok "FRR installed."
    fi
    mark_done "$STEP_ID"
fi

# ── Step 2: BGP Controller ────────────────────────────────────────────────────
STEP_ID="bgp_ctrl_${BGP_CTRL_ID}"
step "BGP Controller: ${BGP_CTRL_ID}"
if step_done "$STEP_ID"; then
    ok "Already completed — skipping."
else
    # Check if target controller exists, or if any BGP controller already exists
    # on this node pointing to the same peer (avoid duplicates)
    _existing_bgp=$(pvesh get /cluster/sdn/controllers --output-format json 2>/dev/null \
        | python3 -c "
import sys, json
ctrls = json.load(sys.stdin)
match = [c['controller'] for c in ctrls
         if c.get('type') == 'bgp'
         and c.get('node') == '${PVE_NODE}'
         and '${ROUTER_IP}' in c.get('peers','')]
print(match[0] if match else '')
" 2>/dev/null)

    if [[ -n "$_existing_bgp" ]]; then
        ok "BGP controller '${_existing_bgp}' already exists on node ${PVE_NODE}."
        BGP_CTRL_ID="$_existing_bgp"
    elif pvesh get "/cluster/sdn/controllers/${BGP_CTRL_ID}" >/dev/null 2>&1; then
        ok "BGP controller '${BGP_CTRL_ID}' already exists."
    else
        run pvesh create /cluster/sdn/controllers \
            --controller "$BGP_CTRL_ID" \
            --type bgp \
            --asn "$PROXMOX_ASN" \
            --peers "$ROUTER_IP" \
            --node "$PVE_NODE"
        ok "BGP controller '${BGP_CTRL_ID}' created."
    fi
    mark_done "$STEP_ID"
fi

# ── Step 3: EVPN Controller ───────────────────────────────────────────────────
STEP_ID="evpn_ctrl_${EVPN_CTRL_ID}"
step "EVPN Controller: ${EVPN_CTRL_ID}"
if step_done "$STEP_ID"; then
    ok "Already completed — skipping."
else
    if pvesh get "/cluster/sdn/controllers/${EVPN_CTRL_ID}" >/dev/null 2>&1; then
        ok "EVPN controller '${EVPN_CTRL_ID}' already exists."
    else
        run pvesh create /cluster/sdn/controllers \
            --controller "$EVPN_CTRL_ID" \
            --type evpn \
            --asn "$PROXMOX_ASN" \
            --peers "$ROUTER_IP"
        ok "EVPN controller '${EVPN_CTRL_ID}' created."
    fi
    mark_done "$STEP_ID"
fi

# ── Step 4: EVPN Zone ─────────────────────────────────────────────────────────
STEP_ID="evpn_zone_${ZONE_ID}"
step "EVPN Zone: ${ZONE_ID}"
if step_done "$STEP_ID"; then
    ok "Already completed — skipping."
else
    if pvesh get "/cluster/sdn/zones/${ZONE_ID}" >/dev/null 2>&1; then
        ok "Zone '${ZONE_ID}' already exists."
    else
        run pvesh create /cluster/sdn/zones \
            --zone "$ZONE_ID" \
            --type evpn \
            --controller "$EVPN_CTRL_ID" \
            --vrf-vxlan "$VRF_VXLAN" \
            --advertise-subnets 1 \
            --ipam pve
        ok "Zone '${ZONE_ID}' created."
    fi
    mark_done "$STEP_ID"
fi

# ── Step 5: VNet ──────────────────────────────────────────────────────────────
STEP_ID="evpn_vnet_${VNET_ID}"
step "VNet: ${VNET_ID}"
if step_done "$STEP_ID"; then
    ok "Already completed — skipping."
else
    if pvesh get "/cluster/sdn/vnets/${VNET_ID}" >/dev/null 2>&1; then
        ok "VNet '${VNET_ID}' already exists."
    else
        run pvesh create /cluster/sdn/vnets \
            --vnet "$VNET_ID" \
            --zone "$ZONE_ID" \
            --tag "$VNET_TAG"
        ok "VNet '${VNET_ID}' created."
    fi
    mark_done "$STEP_ID"
fi

# ── Step 6: Apply ─────────────────────────────────────────────────────────────
STEP_ID="apply_evpn"
step "Applying SDN configuration"
if step_done "$STEP_ID"; then
    ok "Already completed — skipping."
else
    run pvesh set /cluster/sdn
    ok "SDN applied and reloaded."
    mark_done "$STEP_ID"
fi

# ── Step 7: Patch FRR for eBGP to peer ───────────────────────────────────────
# Proxmox SDN generates FRR config with remote-as = local ASN (iBGP).
# If the router peer uses a different ASN (eBGP), patch FRR after SDN reload.
PEER_ASN="${PEER_ASN:-65001}"  # Peer (UniFi) ASN — override if different
STEP_ID="frr_ebgp_patch"
step "FRR eBGP patch: ${ROUTER_IP} → AS ${PEER_ASN}"
if step_done "$STEP_ID"; then
    ok "Already completed — skipping."
else
    # Read current FRR remote-as for this peer (from running config)
    _cur_as=$(vtysh -c "show bgp neighbor ${ROUTER_IP}" 2>/dev/null \
        | grep "remote AS" | awk '{print $NF}' || echo "")
    if [[ "$_cur_as" == "$PEER_ASN" ]]; then
        ok "FRR already configured with remote-as ${PEER_ASN} for ${ROUTER_IP}."
    elif ! $DRY_RUN; then
        # Remove peer from both peer-groups, configure as standalone eBGP neighbor
        vtysh <<VTYSH_EOF
configure terminal
router bgp ${PROXMOX_ASN}
no neighbor ${ROUTER_IP} peer-group BGP
no neighbor ${ROUTER_IP} peer-group VTEP
neighbor ${ROUTER_IP} remote-as ${PEER_ASN}
address-family ipv4 unicast
 neighbor ${ROUTER_IP} activate
 neighbor ${ROUTER_IP} soft-reconfiguration inbound
exit-address-family
address-family l2vpn evpn
 neighbor ${ROUTER_IP} activate
exit-address-family
exit
VTYSH_EOF
        # Save config (must be outside configure terminal)
        vtysh -c "write memory"
        ok "FRR patched: ${ROUTER_IP} configured as eBGP (remote-as ${PEER_ASN})."
        warn "Note: This patch will need re-applying if 'pvesh set /cluster/sdn' is run again."
    else
        echo "  [dry-run] Would patch FRR: neighbor ${ROUTER_IP} remote-as ${PEER_ASN}"
    fi
    mark_done "$STEP_ID"
fi


echo "  BGP/EVPN setup complete."
echo "  Proxmox ASN ${PROXMOX_ASN} → Peer ${ROUTER_IP}"
echo ""
echo "  Next steps:"
echo "    1. Enable BGP in UniFi Network App → Settings → Routing → BGP"
echo "       Local ASN: <UniFi ASN>  |  Neighbor IP: <this host's mgmt IP>"
echo "    2. Run: verify-sdn.sh to confirm BGP session is established."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
