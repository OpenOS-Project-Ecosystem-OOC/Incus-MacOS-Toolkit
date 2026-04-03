# AGENTS.md — Incus-MacOS-Toolkit (imt)

Architecture decisions, conventions, and patterns for this project.
Read this before making changes.

---

## Repository layout

```
macos-vm/
  cli/
    imt.sh          Main CLI — all commands implemented here
    lib.sh          Shared library (colors, logging, config, arch detection)
  image-pipeline/
    fetch-macos.py  Fetch macOS recovery image from Apple CDN
    convert-image.sh  Convert .dmg to raw image
    build-image.sh  Create QCOW2 disk and stage firmware
  incus/
    profile.yaml    Incus profile for macOS VMs (QEMU overrides, network)
    setup.sh        One-line shim delegating to imt vm
  guest-tools/      Scripts run inside the macOS guest
  docs/
    example-assemble.yaml  Example fleet file for imt vm assemble
  Makefile          All targets delegate to imt vm
```

---

## CLI structure (imt.sh)

All commands are implemented as `cmd_*` functions in `imt.sh`.
The dispatch table at the bottom routes `imt <command>` to the right function.

```
imt image  firmware | opencore | fetch | build
imt vm     create | start | stop | status | console | shell |
           snapshot | backup | restore | assemble | delete | list
imt doctor
imt config show | init | edit
imt version
```

---

## VM storage model

Each VM uses **three custom Incus storage volumes** (not the Incus root disk):

| Volume | Contents | Boot priority |
|---|---|---|
| `<name>-opencore` | OpenCore bootloader QCOW2 | 10 (highest) |
| `<name>-installer` | macOS recovery image | 5 |
| `<name>-disk` | macOS system disk QCOW2 | 1 |

The Incus profile (`incus/profile.yaml`) carries **no disk devices** — disks
are attached per-instance by `imt vm create`. This allows multiple VMs with
different macOS versions to coexist on the same host.

---

## Backup and restore

`imt vm backup` exports each storage volume separately using
`incus storage volume export`, producing one `.tar.gz` per volume plus an
optional instance metadata archive. This is necessary because `incus export`
only covers the instance root disk, not custom volumes.

`imt vm restore` imports volumes with `incus storage volume import` and the
instance with `incus import`. Existing volumes are skipped (not overwritten).

---

## Declarative assembly (imt vm assemble)

`imt vm assemble --file FILE` reads a YAML file listing VMs and creates any
that don't already exist.

- Uses a minimal `awk`-based YAML parser (no external deps beyond bash + awk)
- `--dry-run` prints `[dry-run]` lines without executing
- `--replace` stops and deletes existing VMs before recreating
- See `docs/example-assemble.yaml` for the full schema

YAML schema:
```yaml
vms:
  - name: macos-sonoma     # required
    version: sonoma        # macOS version (default: sonoma)
    ram: 4GiB              # default: 4GiB
    cpus: 4                # default: 4
    disk: 128GiB           # default: 128GiB
```

---

## Shared library (cli/lib.sh)

Provides: color variables (`GREEN`, `RED`, `YELLOW`, `NC`, `BOLD`), logging
helpers (`info`, `ok`, `warn`, `err`, `die`, `bold`), `require_cmd`,
`require_incus`, `retry`, config loading (`load_config`, `init_config`),
and architecture detection (`detect_arch`).

Config file: `~/.config/imt/imt.conf` (or `$IMT_CONFIG_FILE`).

---

## CI

No dedicated CI workflow yet. Shell syntax is validated by running
`bash -n macos-vm/cli/imt.sh` and `bash -n macos-vm/cli/lib.sh`.

When adding CI:
- Add shellcheck on `cli/imt.sh` and `cli/lib.sh`
- Add a dry-run test for `imt vm assemble`
- Add a syntax check for `incus/profile.yaml`

---

## Intentional divergence from other Incus projects

The following features exist in other projects in this suite but are
**intentionally absent** from imt because they are VM-specific or
macOS-specific concepts with no container equivalent:

| Feature | Reason absent |
|---|---|
| `upgrade` (package manager) | macOS updates via System Preferences, not a CLI package manager |
| `export` (app/binary to host) | Linux namespace sharing — not applicable to VMs |
| `setup-rootless` | `incus-user` daemon — container-specific concept |
| `enter` / shell integration | `imt vm shell` covers this; no distrobox-style integration needed |
| Android extensions (GApps, Magisk) | Android-specific; imt targets macOS VMs |
| Waydroid session management | Android-specific |
| OpenCore / OVMF firmware pipeline | macOS-specific boot chain; not needed for Linux containers |
| VFIO/SR-IOV GPU passthrough | Planned but not yet implemented; macOS needs specific VFIO config |

These are not gaps — they are correct omissions for a macOS VM manager.

---

## Adding a new vm subcommand

1. Add `cmd_vm_<name>()` function to `cli/imt.sh`
2. Add the case entry in `cmd_vm()` dispatch
3. Add the subcommand to the `cmd_vm` help text
4. Update `usage_global` if it affects the top-level summary
