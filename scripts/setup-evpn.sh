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

# BGP controllers are node-scoped; detect the local node name from the cluster
PVE_NODE="${PVE_NODE:-$(pvesh get /cluster/status --output-format json 2>/dev/null \
    | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)}"
# Fallback to hostname if cluster API doesn't return a node name
PVE_NODE="${PVE_NODE:-$(hostname -s)}"

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
    if pvesh get "/cluster/sdn/controllers/${BGP_CTRL_ID}" >/dev/null 2>&1; then
        ok "BGP controller '${BGP_CTRL_ID}' already exists."
    else
        run pvesh create /cluster/sdn/controllers \
            --controller "$BGP_CTRL_ID" \
            --type bgp \
            --asn "$PROXMOX_ASN" \
            --peers "$ROUTER_IP" \
            --ebgp 1 \
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

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  BGP/EVPN setup complete."
echo "  Proxmox ASN ${PROXMOX_ASN} → Peer ${ROUTER_IP}"
echo ""
echo "  Next steps:"
echo "    1. Enable BGP in UniFi Network App → Settings → Routing → BGP"
echo "       Local ASN: <UniFi ASN>  |  Neighbor IP: <this host's mgmt IP>"
echo "    2. Run: verify-sdn.sh to confirm BGP session is established."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
