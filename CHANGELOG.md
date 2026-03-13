# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- `setup-sdn.sh` — Consolidated VLAN zone/VNet/subnet provisioning with `--no-subnet`, `--dry-run`, and `--reset` flags. Resumable via `/tmp/proxmox-sdn-vlan.state`.
- `setup-evpn.sh` — Consolidated BGP/EVPN overlay setup with environment-variable overrides, `--dry-run`, and `--reset` flags. Resumable via `/tmp/proxmox-sdn-evpn.state`.
- `verify-sdn.sh` — Health check for all SDN components (VLAN zone, VNets, EVPN controllers, BGP session status via `vtysh`). Accepts `--vlan` / `--evpn` scope flags.
- `clean-sdn.sh` — Extended teardown to cover both VLAN and EVPN components with `--vlan`, `--evpn`, `--all`, `--force`, and `--dry-run` flags. Prompts for confirmation unless `--force` is passed.

### Changed
- Replaced `sdn.sh`, `sdn-no-subnet.sh` with `setup-sdn.sh` (unified with `--no-subnet` flag).
- Replaced `evpn-sdn.sh`, `bgpscript.sh` with `setup-evpn.sh` (adds resumability and env-var config).

### Removed
- `sdn.sh` (superseded by `setup-sdn.sh`)
- `sdn-no-subnet.sh` (superseded by `setup-sdn.sh --no-subnet`)
- `bgpscript.sh` (superseded by `setup-evpn.sh`)
- `evpn-sdn.sh` (superseded by `setup-evpn.sh`)
