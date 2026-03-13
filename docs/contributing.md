# Contributing

## Code Style

- Keep functions small and focused.
- Use meaningful variable and function names.
- Prefer self-documenting code; add comments only for non-obvious logic.
- All scripts must include `set -euo pipefail`.
- New operations must check for existing resources before creating them (idempotency).

## Script Conventions

- Support `--dry-run` to preview changes without applying them.
- Use the step-state pattern (`step_done` / `mark_done`) for any multi-step setup scripts so runs are resumable.
- Print structured output with `[STEP]`, `[ OK ]`, `[WARN]`, and `[ERROR]` prefixes.
- Always include a usage block comment at the top of the file.

## Validating Changes

- Run `bash -n <script>` to syntax-check before committing.
- Test with `--dry-run` on a Proxmox host before running for real.
- Run `verify-sdn.sh` after any setup change to confirm the expected state.
