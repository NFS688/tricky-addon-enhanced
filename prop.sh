#!/bin/sh
# prop.sh - Early boot property spoofing (Tricky Addon Enhanced)
# Runs pre-boot via resetprop. Post-boot cleanup in propclean.sh (hexpatch + normalization).

MODPATH="${0%/*}"
MODDIR="$MODPATH"
. "$MODPATH/common/common.sh"

_PROP_SPOOF_COUNT=0
_PROP_FAIL_COUNT=0

ensure_prop() {
    NAME=$1
    NEWVAL=$2
    VALUE=$(getprop "$NAME")
    if [ -z "$VALUE" ]; then
        if resetprop -n "$NAME" "$NEWVAL" 2>/dev/null; then
            _PROP_SPOOF_COUNT=$((_PROP_SPOOF_COUNT + 1))
        else
            _PROP_FAIL_COUNT=$((_PROP_FAIL_COUNT + 1))
            _log "ERROR" "Failed to spoof (ensure): $NAME"
        fi
    fi
}

_log "INFO" "Property spoofing starting"
if ! resetprop -w sys.boot_completed 0 2>/dev/null; then
    _log "WARN" "resetprop -w sys.boot_completed timeout or failure"
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

check_reset_prop "ro.crypto.state" "encrypted"
check_reset_prop "ro.is_ever_orange" "0"
check_reset_prop "ro.oem_unlock_supported" "0"
check_reset_prop "ro.secureboot.devicelock" "1"

# MIUI cross-region flash (CN → GLOBAL)
contains_reset_prop "ro.boot.hwc" "CN" "GLOBAL"
contains_reset_prop "ro.boot.hwcountry" "CN" "GLOBAL"

# Delete qemu property entirely -- some detectors check existence, not value
if [ -n "$(resetprop ro.kernel.qemu)" ]; then
    if resetprop --delete ro.kernel.qemu 2>/dev/null; then
        _PROP_SPOOF_COUNT=$((_PROP_SPOOF_COUNT + 1))
    else
        resetprop -n ro.kernel.qemu "" 2>/dev/null
        _PROP_FAIL_COUNT=$((_PROP_FAIL_COUNT + 1))
        _log "WARN" "Could not delete ro.kernel.qemu, blanked instead"
    fi
fi

# Hide recovery boot mode
contains_reset_prop "ro.bootmode" "recovery" "unknown"
contains_reset_prop "ro.boot.bootmode" "recovery" "unknown"
contains_reset_prop "ro.boot.mode" "recovery" "unknown"
contains_reset_prop "vendor.bootmode" "recovery" "unknown"
contains_reset_prop "vendor.boot.bootmode" "recovery" "unknown"
contains_reset_prop "vendor.boot.mode" "recovery" "unknown"

# VBMeta digest from persisted boot_hash (written at install by customize.sh)
if [ -f "/data/adb/boot_hash" ]; then
    hash_value=$(grep -v '^#' "/data/adb/boot_hash" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    if echo "$hash_value" | grep -qE '^[a-f0-9]{64}$'; then
        if resetprop -n ro.boot.vbmeta.digest "$hash_value" 2>/dev/null; then
            _PROP_SPOOF_COUNT=$((_PROP_SPOOF_COUNT + 1))
            _log "INFO" "VBMeta digest set from boot_hash: $(printf '%.16s' "$hash_value")..."
        else
            _PROP_FAIL_COUNT=$((_PROP_FAIL_COUNT + 1))
            _log "ERROR" "Failed to set vbmeta.digest from boot_hash"
        fi
    else
        _log "WARN" "boot_hash invalid (not 64-char hex), removing"
        rm -f /data/adb/boot_hash
    fi
fi

# VBMeta metadata props -- ensure they exist even if kernel didn't set them
ensure_prop "ro.boot.vbmeta.device_state" "locked"
ensure_prop "ro.boot.vbmeta.invalidate_on_error" "yes"
ensure_prop "ro.boot.vbmeta.avb_version" "1.2"
ensure_prop "ro.boot.vbmeta.hash_alg" "sha256"

# Dynamic vbmeta_size -- use partition byte size with A/B slot suffix + multi-path fallback
slot_suffix=$(getprop ro.boot.slot_suffix 2>/dev/null)
VBMETA_SIZE=""
for candidate in \
    "/dev/block/by-name/vbmeta${slot_suffix}" \
    "/dev/block/by-name/vbmeta" \
    "/dev/block/by-name/vbmeta_a" \
    "/dev/block/by-name/vbmeta_b"; do
    if [ -b "$candidate" ]; then
        VBMETA_SIZE=$(blockdev --getsize64 "$candidate" 2>/dev/null)
        [ -n "$VBMETA_SIZE" ] && [ "$VBMETA_SIZE" -gt 0 ] 2>/dev/null && break
        VBMETA_SIZE=""
    fi
done
ensure_prop "ro.boot.vbmeta.size" "${VBMETA_SIZE:-4096}"

_log "INFO" "Property spoofing complete: $_PROP_SPOOF_COUNT spoofed, $_PROP_FAIL_COUNT failed"
