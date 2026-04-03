#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# imt-tui.sh — interactive terminal UI for the Incus macOS Toolkit
#
# Menu-driven interface for common imt operations.
# Requires: dialog (or whiptail as fallback)
#
# Usage:
#   imt tui
#   imt-tui.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMT_ROOT="$(dirname "$SCRIPT_DIR")"
IMT_CMD="$IMT_ROOT/cli/imt.sh"
# shellcheck source=../cli/lib.sh disable=SC1091
source "$IMT_ROOT/cli/lib.sh"
load_config

# ── dialog backend ────────────────────────────────────────────────────────────

DIALOG=""

_detect_dialog() {
    if command -v dialog &>/dev/null; then
        DIALOG="dialog"
    elif command -v whiptail &>/dev/null; then
        DIALOG="whiptail"
    else
        die "Neither dialog nor whiptail found. Install: sudo apt install dialog"
    fi
}

_dlg() {
    "$DIALOG" --backtitle "imt — Incus macOS Toolkit" "$@" 3>&1 1>&2 2>&3
}

_dlg_menu() {
    local title="$1" text="$2"; shift 2
    _dlg --title "$title" --menu "$text" 0 0 0 "$@"
}

_dlg_input() {
    local title="$1" text="$2" default="${3:-}"
    _dlg --title "$title" --inputbox "$text" 0 60 "$default"
}

_dlg_yesno() {
    local title="$1" text="$2"
    "$DIALOG" --backtitle "imt — Incus macOS Toolkit" \
        --title "$title" --yesno "$text" 0 0
}

_dlg_msgbox() {
    local title="$1" text="$2"
    "$DIALOG" --backtitle "imt — Incus macOS Toolkit" \
        --title "$title" --msgbox "$text" 0 0
}

_run_cmd() {
    local title="$1"; shift
    local output
    output=$("$@" 2>&1) || true
    output=$(printf '%s' "$output" | sed 's/\x1b\[[0-9;]*m//g')
    _dlg_msgbox "$title" "${output:-Done.}"
}

_pick_vm() {
    local default="${IMT_VERSION:-sonoma}"
    local vms
    vms=$(incus list --format csv -c n --columns nstL 2>/dev/null \
          | awk -F, '/macos-kvm/{print $1}' | head -20 || true)
    if [ -z "$vms" ]; then
        _dlg_input "Select VM" "VM name:" "macos-${default}"
        return
    fi
    local items=()
    while IFS= read -r vm; do
        items+=("$vm" "")
    done <<< "$vms"
    _dlg_menu "Select VM" "Choose a VM:" "${items[@]}"
}

# ── main menu ─────────────────────────────────────────────────────────────────

menu_main() {
    while true; do
        local choice
        choice=$(_dlg_menu "imt" "Select an action:" \
            "vm"       "Manage macOS VMs" \
            "image"    "Manage macOS disk images" \
            "profiles" "Manage Incus profiles" \
            "doctor"   "Check prerequisites" \
            "config"   "Configuration" \
            "update"   "Check for updates" \
            "quit"     "Exit") || break

        case "$choice" in
            vm)       menu_vm ;;
            image)    menu_image ;;
            profiles) menu_profiles ;;
            doctor)   _run_cmd "Doctor" "$IMT_CMD" doctor ;;
            config)   menu_config ;;
            update)   _run_cmd "Update Check" "$IMT_CMD" update check ;;
            quit)     break ;;
        esac
    done
}

# ── vm menu ───────────────────────────────────────────────────────────────────

menu_vm() {
    while true; do
        local choice
        choice=$(_dlg_menu "VM Management" "Select an action:" \
            "list"     "List macOS VMs" \
            "status"   "Show VM status" \
            "start"    "Start a VM" \
            "stop"     "Stop a VM" \
            "create"   "Create a new VM" \
            "shell"    "Open shell in VM" \
            "upgrade"  "Run macOS Software Update" \
            "snapshot" "Manage snapshots" \
            "backup"   "Backup and restore" \
            "disk"     "Disk resize" \
            "delete"   "Delete a VM" \
            "back"     "Back") || break

        case "$choice" in
            list)     _run_cmd "VMs" "$IMT_CMD" vm list ;;
            status)   menu_vm_status ;;
            start)    menu_vm_action "start" ;;
            stop)     menu_vm_action "stop" ;;
            create)   menu_vm_create ;;
            shell)    menu_vm_shell ;;
            upgrade)  menu_vm_upgrade ;;
            snapshot) menu_vm_snapshot ;;
            backup)   menu_vm_backup ;;
            disk)     menu_vm_disk ;;
            delete)   menu_vm_delete ;;
            back)     break ;;
        esac
    done
}

menu_vm_status() {
    local vm
    vm=$(_pick_vm) || return
    _run_cmd "Status: ${vm}" "$IMT_CMD" vm status --name "$vm"
}

menu_vm_action() {
    local action="$1"
    local vm
    vm=$(_pick_vm) || return
    _run_cmd "VM ${action}: ${vm}" "$IMT_CMD" vm "$action" --name "$vm"
}

menu_vm_create() {
    local name version
    version=$(_dlg_input "Create VM" "macOS version (sonoma/ventura/monterey):" \
        "${IMT_VERSION:-sonoma}") || return
    name=$(_dlg_input "Create VM" "VM name:" "macos-${version}") || return
    _run_cmd "Creating ${name}" "$IMT_CMD" vm create --version "$version" --name "$name"
}

menu_vm_shell() {
    local vm
    vm=$(_pick_vm) || return
    clear
    "$IMT_CMD" vm shell --name "$vm" || true
}

menu_vm_upgrade() {
    local vm
    vm=$(_pick_vm) || return
    local choice
    choice=$(_dlg_menu "Upgrade" "Select action:" \
        "list"    "List available updates" \
        "install" "Install all updates") || return
    case "$choice" in
        list)    _run_cmd "Available Updates" "$IMT_CMD" vm upgrade --name "$vm" --list ;;
        install) _run_cmd "Installing Updates" "$IMT_CMD" vm upgrade --name "$vm" ;;
    esac
}

menu_vm_snapshot() {
    local vm
    vm=$(_pick_vm) || return
    local choice
    choice=$(_dlg_menu "Snapshots: ${vm}" "Select action:" \
        "list"    "List snapshots" \
        "create"  "Create snapshot" \
        "restore" "Restore snapshot" \
        "delete"  "Delete snapshot") || return
    case "$choice" in
        list)
            _run_cmd "Snapshots: ${vm}" "$IMT_CMD" vm snapshot list --name "$vm"
            ;;
        create)
            local snap_name
            snap_name=$(_dlg_input "Create Snapshot" "Snapshot name:" "") || return
            _run_cmd "Creating Snapshot" "$IMT_CMD" vm snapshot create \
                --name "$vm" --snapshot "$snap_name"
            ;;
        restore)
            local snap_name
            snap_name=$(_dlg_input "Restore Snapshot" "Snapshot name:" "") || return
            if _dlg_yesno "Restore" "Restore '${vm}' to snapshot '${snap_name}'?"; then
                _run_cmd "Restoring" "$IMT_CMD" vm snapshot restore \
                    --name "$vm" --snapshot "$snap_name"
            fi
            ;;
        delete)
            local snap_name
            snap_name=$(_dlg_input "Delete Snapshot" "Snapshot name:" "") || return
            if _dlg_yesno "Delete Snapshot" "Delete snapshot '${snap_name}' from '${vm}'?"; then
                _run_cmd "Deleting Snapshot" "$IMT_CMD" vm snapshot delete \
                    --name "$vm" --snapshot "$snap_name"
            fi
            ;;
    esac
}

menu_vm_backup() {
    local vm
    vm=$(_pick_vm) || return
    local choice
    choice=$(_dlg_menu "Backup: ${vm}" "Select action:" \
        "create"  "Create backup" \
        "restore" "Restore from backup") || return
    case "$choice" in
        create)
            local dest
            dest=$(_dlg_input "Backup" "Destination directory (or blank for default):" "") || return
            local args=("$IMT_CMD" vm backup --name "$vm")
            [ -n "$dest" ] && args+=(--dest "$dest")
            _run_cmd "Backing up ${vm}" "${args[@]}"
            ;;
        restore)
            local src
            src=$(_dlg_input "Restore" "Backup directory path:" "") || return
            _run_cmd "Restoring ${vm}" "$IMT_CMD" vm restore --from "$src"
            ;;
    esac
}

menu_vm_disk() {
    local vm
    vm=$(_pick_vm) || return
    local choice
    choice=$(_dlg_menu "Disk: ${vm}" "Select action:" \
        "info"   "Show disk info" \
        "resize" "Resize disk") || return
    case "$choice" in
        info)
            _run_cmd "Disk Info: ${vm}" "$IMT_CMD" vm disk info --name "$vm"
            ;;
        resize)
            local size
            size=$(_dlg_input "Resize Disk" "New size (e.g. 256G):" "") || return
            _run_cmd "Resizing ${vm}" "$IMT_CMD" vm disk resize --name "$vm" --size "$size"
            ;;
    esac
}

menu_vm_delete() {
    local vm
    vm=$(_pick_vm) || return
    if _dlg_yesno "Delete VM" "Delete VM '${vm}'? This cannot be undone."; then
        _run_cmd "Deleting ${vm}" "$IMT_CMD" vm delete --name "$vm"
    fi
}

# ── image menu ────────────────────────────────────────────────────────────────

menu_image() {
    while true; do
        local choice
        choice=$(_dlg_menu "Images" "Select an action:" \
            "fetch" "Fetch macOS installer" \
            "build" "Build disk image" \
            "back"  "Back") || break

        case "$choice" in
            fetch)
                local version
                version=$(_dlg_input "Fetch" "macOS version:" \
                    "${IMT_VERSION:-sonoma}") || continue
                _run_cmd "Fetching ${version}" "$IMT_CMD" image fetch --version "$version"
                ;;
            build)
                _run_cmd "Build Image" "$IMT_CMD" image build --help
                _dlg_msgbox "Build Image" \
                    "Run 'imt image build' from the terminal for full options."
                ;;
            back) break ;;
        esac
    done
}

# ── profiles menu ─────────────────────────────────────────────────────────────

menu_profiles() {
    while true; do
        local choice
        choice=$(_dlg_menu "Profiles" "Select an action:" \
            "list"    "List available profiles" \
            "install" "Install profiles into Incus" \
            "diff"    "Compare local vs Incus" \
            "back"    "Back") || break

        case "$choice" in
            list)    _run_cmd "Profiles" "$IMT_CMD" profiles list ;;
            install) _run_cmd "Installing Profiles" "$IMT_CMD" profiles install --all ;;
            diff)    _run_cmd "Profile Diff" "$IMT_CMD" profiles diff ;;
            back)    break ;;
        esac
    done
}

# ── config menu ───────────────────────────────────────────────────────────────

menu_config() {
    while true; do
        local choice
        choice=$(_dlg_menu "Configuration" "Select an action:" \
            "show" "Show current config" \
            "edit" "Edit config file" \
            "init" "Create default config" \
            "back" "Back") || break

        case "$choice" in
            show) _run_cmd "Config" "$IMT_CMD" config show ;;
            edit)
                clear
                "$IMT_CMD" config edit || true
                ;;
            init) _run_cmd "Init Config" "$IMT_CMD" config init ;;
            back) break ;;
        esac
    done
}

# ── main ──────────────────────────────────────────────────────────────────────

_detect_dialog
menu_main
clear
