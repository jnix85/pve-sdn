# Proxmox SDN Scripts

Bash scripts for configuring and managing Software Defined Networking (SDN) on Proxmox VE with optional BGP/EVPN peering to a UniFi Gateway.

## Scripts

| Script | Purpose |
|---|---|
| `setup-sdn.sh` | Create VLAN zone, VNets, and subnets |
| `setup-evpn.sh` | Configure BGP/EVPN overlay for UniFi peering |
| `clean-sdn.sh` | Remove SDN configuration (VLAN, EVPN, or both) |
| `verify-sdn.sh` | Health check — verify SDN components and BGP status |

All scripts are **idempotent** (safe to re-run), support `--dry-run`, and are **resumable** via a checkpoint state file (clear with `--reset`).

---

## Quick Start

```bash
# 1. Set up VLAN zone with subnets
sudo ./scripts/setup-sdn.sh

# 2. (Optional) Set up BGP/EVPN overlay for dynamic routing with UniFi
sudo ./scripts/setup-evpn.sh

# 3. Verify everything is running
sudo ./scripts/verify-sdn.sh
```

---

## setup-sdn.sh

Configures a VLAN zone (`midgard`) and nine VNets on `vmbr0`.

```bash
sudo ./scripts/setup-sdn.sh [OPTIONS]
  --no-subnet   Create VNets without subnets (bridge-only mode)
  --dry-run     Show commands without executing
  --reset       Clear saved checkpoint and start over
```

### VLANs Configured

| VNet | VLAN | Subnet | Gateway |
|---|---|---|---|
| legacy | 1 | 10.1.0.0/23 | 10.1.0.1 |
| mgmt | 19 | 10.19.0.0/24 | 10.19.0.1 |
| iot | 21 | 10.21.0.0/24 | 10.21.0.1 |
| secure | 20 | 10.20.0.0/24 | 10.20.0.1 |
| proxmox | 24 | 10.24.0.0/24 | 10.24.0.1 |
| dmz | 100 | 192.168.100.0/24 | 192.168.100.1 |
| deploy | 2 | 192.168.3.0/24 | 192.168.3.1 |
| secalt | 23 | 10.23.0.0/24 | 10.23.0.1 |
| misc | 27 | 10.27.0.0/24 | 10.27.0.1 |

---

## setup-evpn.sh

Installs FRR and configures a BGP/EVPN overlay for dynamic route advertisement to a UniFi Gateway.

```bash
sudo ./scripts/setup-evpn.sh [OPTIONS]
  --dry-run   Show commands without executing
  --reset     Clear saved checkpoint and start over
```

Override defaults via environment variables:

```bash
ROUTER_IP=10.24.0.1 PROXMOX_ASN=65002 sudo -E ./scripts/setup-evpn.sh
```

| Variable | Default | Description |
|---|---|---|
| `ROUTER_IP` | `10.24.0.1` | UniFi Gateway IP |
| `PROXMOX_ASN` | `65002` | Proxmox BGP ASN |
| `ZONE_ID` | `evpn_int` | SDN Zone name |
| `VNET_ID` | `vnet_int` | VNet name |
| `VNET_TAG` | `1000` | VXLAN VNI |
| `VRF_VXLAN` | `10000` | VRF VXLAN tag |

### UniFi BGP Peer Setup

After running `setup-evpn.sh`, configure the peer in UniFi Network App:

- **Settings → Routing → BGP → Enable BGP**
- **Local ASN:** your UniFi ASN (e.g. `65001`)
- **BGP Router ID:** `10.24.0.1`
- **Neighbor IP:** Proxmox host management IP
- **Remote ASN:** `65002`

---

## clean-sdn.sh

Removes SDN configuration components.

```bash
sudo ./scripts/clean-sdn.sh [OPTIONS]
  --vlan      Remove VLAN zone and VNets only
  --evpn      Remove BGP/EVPN controllers and zone only
  --all       Remove everything (default)
  --force     Skip confirmation prompt
  --dry-run   Show commands without executing
```

---

## verify-sdn.sh

Checks that all SDN components exist and reports BGP session status.

```bash
sudo ./scripts/verify-sdn.sh [OPTIONS]
  --vlan   Check VLAN components only
  --evpn   Check EVPN/BGP components only
```

---

## Verification Commands

| Platform | Command | Purpose |
|---|---|---|
| Proxmox | `vtysh -c "show bgp summary"` | Verify BGP session is **Established** |
| Proxmox | `vtysh -c "show evpn vni"` | Confirm EVPN VNIs are active |
| UniFi | `vtysh -c "show ip bgp summary"` | Check UniFi sees the Proxmox neighbor |
| UniFi | `vtysh -c "show ip route bgp"` | Verify subnets appear in routing table |

---

## Documentation

- [`docs/architecture.md`](docs/architecture.md) — Component overview, data flow, and design decisions
- [`docs/contributing.md`](docs/contributing.md) — Code style and contribution guidelines
- [`CHANGELOG.md`](CHANGELOG.md) — Release history

---

## Resources

- [Proxmox SDN Wiki](https://pve.proxmox.com/wiki/Software-Defined_Network)
- [UniFi BGP Routing Guide](https://help.ui.com/hc/en-us/articles/4405333554455-UniFi-Gateway-BGP-Routing)
- [FRRouting Documentation](https://frrouting.org/)
- [Proxmox IPAM Deep Dive](https://pve.proxmox.com/pve-docs/chapter-pvesdn.html#pvesdn_ipam)
