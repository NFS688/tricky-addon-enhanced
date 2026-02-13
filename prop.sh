#!/bin/sh
# prop.sh - Sole authority for ALL property spoofing (Tricky Addon Enhanced)
# Runs early boot (before sys.boot_completed). No other script calls resetprop.

MODPATH="${0%/*}"
. "$MODPATH/common/logging.sh"
log_init "PROP" "boot"

_PROP_SPOOF_COUNT=0
_PROP_FAIL_COUNT=0

# Uses resetprop to read (sees already-spoofed values from prior boot)
check_reset_prop() {
    NAME=$1
    EXPECTED=$2
    VALUE=$(resetprop "$NAME")
    if [ "$VALUE" = "$EXPECTED" ]; then
        return 0
    fi
    # Set even if absent — critical VBMeta props must exist
    if resetprop -n "$NAME" "$EXPECTED" 2>/dev/null; then
        _PROP_SPOOF_COUNT=$((_PROP_SPOOF_COUNT + 1))
        log_debug "Spoofed: $NAME=$EXPECTED"
    else
        _PROP_FAIL_COUNT=$((_PROP_FAIL_COUNT + 1))
        log_error "Failed to spoof: $NAME"
    fi
}

contains_reset_prop() {
    NAME=$1
    CONTAINS=$2
    NEWVAL=$3
    case "$(resetprop "$NAME")" in
        *"$CONTAINS"*)
            if resetprop -n "$NAME" "$NEWVAL" 2>/dev/null; then
                _PROP_SPOOF_COUNT=$((_PROP_SPOOF_COUNT + 1))
                log_debug "Spoofed (contains): $NAME=$NEWVAL"
            else
                _PROP_FAIL_COUNT=$((_PROP_FAIL_COUNT + 1))
                log_error "Failed to spoof (contains): $NAME"
            fi
            ;;
    esac
}

# Uses getprop to read (sees real kernel/init values, not spoofed)
ensure_prop() {
    NAME=$1
    NEWVAL=$2
    VALUE=$(getprop "$NAME")
    if [ -z "$VALUE" ]; then
        if resetprop -n "$NAME" "$NEWVAL" 2>/dev/null; then
            _PROP_SPOOF_COUNT=$((_PROP_SPOOF_COUNT + 1))
            log_debug "Spoofed (ensure): $NAME=$NEWVAL"
        else
            _PROP_FAIL_COUNT=$((_PROP_FAIL_COUNT + 1))
            log_error "Failed to spoof (ensure): $NAME"
        fi
    fi
}

log_info "Property spoofing starting"
if ! resetprop -w sys.boot_completed 0 2>/dev/null; then
    log_warn "resetprop -w sys.boot_completed timeout or failure"
fi

# Core boot verification props
check_reset_prop "ro.boot.vbmeta.device_state" "locked"
check_reset_prop "ro.boot.verifiedbootstate" "green"
check_reset_prop "ro.boot.flash.locked" "1"
check_reset_prop "ro.boot.veritymode" "enforcing"
check_reset_prop "ro.boot.warranty_bit" "0"
check_reset_prop "ro.warranty_bit" "0"
check_reset_prop "ro.debuggable" "0"
check_reset_prop "ro.force.debuggable" "0"
check_reset_prop "ro.secure" "1"
check_reset_prop "ro.adb.secure" "1"
check_reset_prop "ro.build.type" "user"
check_reset_prop "ro.build.tags" "release-keys"
check_reset_prop "ro.vendor.boot.warranty_bit" "0"
check_reset_prop "ro.vendor.warranty_bit" "0"
check_reset_prop "vendor.boot.vbmeta.device_state" "locked"
check_reset_prop "vendor.boot.verifiedbootstate" "green"
check_reset_prop "sys.oem_unlock_allowed" "0"

# MIUI specific
check_reset_prop "ro.secureboot.lockstate" "locked"

# Realme specific
check_reset_prop "ro.boot.realmebootstate" "green"
check_reset_prop "ro.boot.realme.lockstate" "1"

# From TSE: Additional props
check_reset_prop "ro.crypto.state" "encrypted"

# Delete qemu property entirely — some detectors check existence, not value
if [ -n "$(resetprop ro.kernel.qemu)" ]; then
    if resetprop --delete ro.kernel.qemu 2>/dev/null; then
        _PROP_SPOOF_COUNT=$((_PROP_SPOOF_COUNT + 1))
        log_debug "Deleted: ro.kernel.qemu"
    else
        # Fallback: blank it if delete unsupported
        resetprop -n ro.kernel.qemu "" 2>/dev/null
        _PROP_FAIL_COUNT=$((_PROP_FAIL_COUNT + 1))
        log_warn "Could not delete ro.kernel.qemu, blanked instead"
    fi
fi

# Hide that we booted from recovery when magisk is in recovery mode
contains_reset_prop "ro.bootmode" "recovery" "unknown"
contains_reset_prop "ro.boot.bootmode" "recovery" "unknown"
contains_reset_prop "vendor.boot.bootmode" "recovery" "unknown"

# VBMeta digest from persisted boot_hash (written at install by customize.sh)
if [ -f "/data/adb/boot_hash" ]; then
    hash_value=$(grep -v '^#' "/data/adb/boot_hash" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    if echo "$hash_value" | grep -qE '^[a-f0-9]{64}$'; then
        if resetprop -n ro.boot.vbmeta.digest "$hash_value" 2>/dev/null; then
            _PROP_SPOOF_COUNT=$((_PROP_SPOOF_COUNT + 1))
            log_info "VBMeta digest set from boot_hash: $(printf '%.16s' "$hash_value")..."
        else
            _PROP_FAIL_COUNT=$((_PROP_FAIL_COUNT + 1))
            log_error "Failed to set vbmeta.digest from boot_hash"
        fi
    else
        log_warn "boot_hash invalid (not 64-char hex), removing"
        rm -f /data/adb/boot_hash
    fi
else
    log_debug "No boot_hash file found"
fi

# VBMeta metadata props — ensure they exist even if kernel didn't set them
ensure_prop "ro.boot.vbmeta.device_state" "locked"
ensure_prop "ro.boot.vbmeta.invalidate_on_error" "yes"
ensure_prop "ro.boot.vbmeta.avb_version" "1.2"
ensure_prop "ro.boot.vbmeta.hash_alg" "sha256"

# Dynamic vbmeta_size — use partition byte size with A/B slot suffix
slot_suffix=$(getprop ro.boot.slot_suffix 2>/dev/null)
vbmeta_dev="/dev/block/by-name/vbmeta${slot_suffix}"
if [ -b "$vbmeta_dev" ]; then
    VBMETA_SIZE=$(blockdev --getsize64 "$vbmeta_dev" 2>/dev/null)
    if [ -n "$VBMETA_SIZE" ]; then
        ensure_prop "ro.boot.vbmeta.size" "$VBMETA_SIZE"
    else
        log_warn "blockdev failed on $vbmeta_dev, using default size"
        ensure_prop "ro.boot.vbmeta.size" "4096"
    fi
else
    log_debug "vbmeta block device not found ($vbmeta_dev), using default size"
    ensure_prop "ro.boot.vbmeta.size" "4096"
fi

log_info "Property spoofing complete: $_PROP_SPOOF_COUNT spoofed, $_PROP_FAIL_COUNT failed"
