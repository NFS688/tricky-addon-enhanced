#!/system/bin/sh
# VBHash extraction with one-time persistence
# NOTE: This script ONLY extracts and persists the VBHash.
# All resetprop calls live in prop.sh (sole property authority).

MODDIR="${0%/*}/.."
VBHASH_APK="$MODDIR/common/vbhash_extractor.apk"
VBHASH_PKG="com.ceco.gravitybox.unlocker"
BOOT_HASH_FILE="/data/adb/boot_hash"

. "$MODDIR/common/logging.sh"
log_init "VBHASH" "boot"

get_stored_hash() {
    if [ ! -f "$BOOT_HASH_FILE" ]; then
        log_debug "No stored hash file"
        return 1
    fi
    hash=$(grep -v '^#' "$BOOT_HASH_FILE" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    if echo "$hash" | grep -qE '^[a-f0-9]{64}$'; then
        echo "$hash"
        return 0
    fi
    log_warn "Stored hash invalid (length: ${#hash})"
    return 1
}

persist_hash() {
    _hash="$1"
    _source="$2"
    if ! echo "$_hash" > "$BOOT_HASH_FILE"; then
        log_error "Failed to persist hash to $BOOT_HASH_FILE"
        return 1
    fi
    chmod 644 "$BOOT_HASH_FILE"
    log_info "VBHash persisted ($_source): $(printf '%.16s' "$_hash")..."
}

# Bootloader sets ro.boot.vbmeta.digest on AVB-enabled devices — read it
# directly before attempting the heavier APK-based attestation extraction
extract_from_property() {
    prop_hash=$(getprop ro.boot.vbmeta.digest 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    clean_hash=$(echo "$prop_hash" | grep -oE '^[a-f0-9]{64}$')
    if [ -n "$clean_hash" ]; then
        echo "$clean_hash"
        return 0
    fi
    return 1
}

extract_from_apk() {
    if [ ! -f "$VBHASH_APK" ]; then
        log_error "APK not found at $VBHASH_APK"
        return 1
    fi

    log_info "Extracting VBHash via attestation APK..."
    if ! pm install "$VBHASH_APK" >/dev/null 2>&1; then
        log_error "Failed to install extractor APK"
        return 1
    fi

    VBH="$(content call --uri content://Provider --method GET 2>/dev/null)"
    if ! pm uninstall "$VBHASH_PKG" >/dev/null 2>&1; then
        log_warn "Failed to uninstall extractor APK"
    fi

    if [ -z "$VBH" ]; then
        log_error "Content provider returned empty response"
        return 1
    fi

    apk_hash="$(echo "$VBH" | grep -oE '[a-f0-9]{64}=VBHash' | grep -oE '[a-f0-9]{64}')"
    if echo "$apk_hash" | grep -qE '^[a-f0-9]{64}$'; then
        echo "$apk_hash"
        return 0
    fi

    log_error "Failed to extract VBHash (response: $(printf '%.50s' "$VBH")...)"
    return 1
}

pass_vbhash() {
    stored_hash=$(get_stored_hash)
    if [ -n "$stored_hash" ]; then
        log_info "Using persisted hash: $(printf '%.16s' "$stored_hash")..."
        return 0
    fi

    log_info "First boot - extracting VBHash..."

    prop_hash=$(extract_from_property)
    if [ -n "$prop_hash" ]; then
        persist_hash "$prop_hash" "bootloader property"
        return $?
    fi
    log_debug "Bootloader property empty, trying APK extraction"

    apk_hash=$(extract_from_apk)
    if [ -n "$apk_hash" ]; then
        persist_hash "$apk_hash" "attestation APK"
        return $?
    fi

    log_error "All VBHash extraction methods failed"
    return 1
}

case "$1" in
    --extract) pass_vbhash ;;
    *)
        echo "Usage: $0 --extract"
        echo "  --extract  Extract and persist VBHash from device"
        echo "  Property spoofing is handled by prop.sh"
        ;;
esac
