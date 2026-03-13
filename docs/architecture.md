# System Architecture

## Overview
Four Bash scripts manage the full lifecycle of Proxmox VE Software Defined Networking (SDN), including a VLAN overlay and optional BGP/EVPN dynamic routing integration with a UniFi Gateway.

## Scripts

| Script | Role |
|---|---|
| `setup-sdn.sh` | Day-1 provisioning: VLAN zone, VNets, subnets |
| `setup-evpn.sh` | Day-1 provisioning: BGP/EVPN controllers and zone |
| `verify-sdn.sh` | Day-2 operations: health check and BGP status |
| `clean-sdn.sh` | Teardown: remove VLAN and/or EVPN components |

## Core Components

- **VLAN Zone (`midgard`)**: Bridges Proxmox VNets to physical VLANs on `vmbr0`. Nine VNets map to UniFi VLAN tags.
- **BGP Controller (`unifi-peer`)**: eBGP session between Proxmox (AS 65002) and UniFi Gateway (AS 65001).
- **EVPN Controller (`evpn-ctrl`)**: Manages MAC/IP learning across the EVPN fabric.
- **EVPN Zone (`evpn_int`)**: VRF instance with VXLAN tag 10000. Advertises subnets into BGP.
- **VNet (`vnet_int`)**: Virtual bridge attached to VMs for EVPN-routed traffic (VNI 1000).

## Data Flow

```
VM (vnet_int) ──► EVPN Zone (evpn_int) ──► FRR / BGP ──► UniFi Gateway
                                                │
                                         Route advertisement
                                         of internal subnets
```

VLAN traffic:
```
VM (vmbr0.VLAN) ──► VNet (midgard zone) ──► Physical switch trunk port
```

## Design Decisions

- **Idempotency**: Every `pvesh` operation checks for existing resources before creating. Scripts are safe to re-run at any time.
- **Resumability**: A state file (`/tmp/proxmox-sdn-*.state`) tracks completed steps. A failed or interrupted run resumes from the last checkpoint. Use `--reset` to restart from scratch.
- **Dry-run**: All scripts accept `--dry-run` to preview changes without affecting the system.
- **Environment overrides**: `setup-evpn.sh` reads configuration from environment variables, so the same script works across different ASNs, IPs, and zone names without editing the file.
