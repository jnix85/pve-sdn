#!/bin/bash
# setup-sdn.sh — Configure Proxmox VLAN SDN zone and VNets
#
# Usage: setup-sdn.sh [OPTIONS]
#   --no-subnet   Create VNets without subnets (bridge-only mode)
#   --dry-run     Print commands without executing them
#   --reset       Clear saved progress and start from the beginning

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
ZONE="midgard"
BRIDGE="vmbr0"
STATE_FILE="/tmp/proxmox-sdn-vlan.state"

# Format: "vnet_name:vlan_tag:alias:cidr:gateway"
NETWORKS=(
    "legacy:1:vlan1:10.1.0.0/23:10.1.0.1"
    "mgmt:19:vlan19:10.19.0.0/24:10.19.0.1"
    "iot:21:vlan21:10.21.0.0/24:10.21.0.1"
    "secure:20:vlan20:10.20.0.0/24:10.20.0.1"
    "proxmox:24:vlan24:10.24.0.0/24:10.24.0.1"
    "dmz:100:vlan100:192.168.100.0/24:192.168.100.1"
    "deploy:2:vlan2:192.168.3.0/24:192.168.3.1"
    "secalt:23:vlan23:10.23.0.0/24:10.23.0.1"
    "misc:27:vlan27:10.27.0.0/24:10.27.0.1"
)

# ── Flags ─────────────────────────────────────────────────────────────────────
NO_SUBNET=false
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --no-subnet) NO_SUBNET=true ;;
        --dry-run)   DRY_RUN=true ;;
        --reset)     rm -f "$STATE_FILE"; echo "State cleared. Re-run to start from the beginning." ; exit 0 ;;
        --help|-h)
            grep '^#' "$0" | head -8 | sed 's/^# \?//'
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

$DRY_RUN && warn "Dry-run mode — no changes will be made."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Proxmox SDN VLAN Setup  |  Zone: ${ZONE}  |  Bridge: ${BRIDGE}"
$NO_SUBNET && echo "  Mode: bridge-only (no subnets)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Step 1: Create Zone ───────────────────────────────────────────────────────
STEP_ID="zone_${ZONE}"
step "Zone: ${ZONE}"
if step_done "$STEP_ID"; then
    ok "Already completed — skipping."
else
    if pvesh get "/cluster/sdn/zones/${ZONE}" >/dev/null 2>&1; then
        ok "Zone '${ZONE}' already exists."
    else
        run pvesh create /cluster/sdn/zones --type vlan --zone "$ZONE" --bridge "$BRIDGE"
        ok "Zone '${ZONE}' created."
    fi
    mark_done "$STEP_ID"
fi

# ── Step 2: Create VNets (and optional Subnets) ───────────────────────────────
for net in "${NETWORKS[@]}"; do
    IFS=":" read -r VNET TAG ALIAS CIDR GW <<< "$net"
    STEP_ID="vnet_${VNET}"

    step "VNet: ${VNET} (VLAN ${TAG})"
    if step_done "$STEP_ID"; then
        ok "Already completed — skipping."
        continue
    fi

    if pvesh get "/cluster/sdn/vnets/${VNET}" >/dev/null 2>&1; then
        ok "VNet '${VNET}' already exists."
    else
        run pvesh create /cluster/sdn/vnets \
            --vnet "$VNET" --zone "$ZONE" --tag "$TAG" --alias "$ALIAS"
        ok "VNet '${VNET}' created."
    fi

    if ! $NO_SUBNET; then
        if pvesh get "/cluster/sdn/vnets/${VNET}/subnets/${CIDR/\//%2F}" >/dev/null 2>&1; then
            ok "Subnet '${CIDR}' already exists."
        else
            run pvesh create "/cluster/sdn/vnets/${VNET}/subnets" \
                --type subnet --subnet "$CIDR" --gateway "$GW"
            ok "Subnet '${CIDR}' added."
        fi
    fi

    mark_done "$STEP_ID"
done

# ── Step 3: Apply ─────────────────────────────────────────────────────────────
STEP_ID="apply_sdn"
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
echo "  SDN VLAN setup complete."
echo "  Run verify-sdn.sh to confirm all components are active."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
