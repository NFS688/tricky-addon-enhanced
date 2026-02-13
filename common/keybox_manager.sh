#!/bin/sh
# Unified keybox fetching with 4-source intelligent failover

TS_DIR="/data/adb/tricky_store"
AUTOMATION_DIR="$TS_DIR/.automation"
TARGET_KEYBOX="$TS_DIR/keybox.xml"
BACKUP_KEYBOX="$TS_DIR/keybox.xml.bak"

YURIKEY_URL="https://raw.githubusercontent.com/Yurii0307/yurikey/main/key"
UPSTREAM_URL="https://raw.githubusercontent.com/KOWX712/Tricky-Addon-Update-Target-List/main/.extra"
INTEGRITYBOX_URL="https://raw.githubusercontent.com/MeowDump/MeowDump/refs/heads/main/NullVoid/ShockWave.tar"
INTEGRITYBOX_MIRROR="https://raw.gitmirror.com/MeowDump/MeowDump/refs/heads/main/NullVoid/ShockWave.tar"

MODPATH="${MODPATH:-${0%/*}/..}"

# Per-invocation temp file to avoid TOCTOU with concurrent fetch (BUG-K16)
TMP_KEYBOX="$AUTOMATION_DIR/keybox_tmp.$$.xml"

download() {
    url="$1"
    _dl_out=""
    if command -v curl >/dev/null 2>&1; then
        _dl_out=$(curl --connect-timeout 10 -fsSL "$url" 2>/dev/null) || {
            log_debug "curl failed for: $url"
            return 1
        }
    else
        _dl_out=$(busybox wget -T 10 --no-check-certificate -qO- "$url" 2>/dev/null) || {
            log_debug "wget failed for: $url"
            return 1
        }
    fi

    # Reject HTML error pages from CDN/proxy (BUG-K3/K4)
    case "$_dl_out" in
        *"<html"*|*"<HTML"*|*"<!DOCTYPE"*|*"<!doctype"*)
            log_warn "Response is HTML (likely error page): $url"
            return 1
            ;;
    esac

    printf '%s' "$_dl_out"
}

fetch_yurikey() {
    log_info "Fetching from Yurikey..."
    raw=$(download "$YURIKEY_URL")
    if [ -z "$raw" ]; then
        log_warn "Yurikey returned empty response"
        return 1
    fi

    mkdir -p "$AUTOMATION_DIR"
    if ! echo "$raw" | busybox base64 -d > "$TMP_KEYBOX" 2>/dev/null || [ ! -s "$TMP_KEYBOX" ]; then
        log_warn "Yurikey base64 decode failed"
        rm -f "$TMP_KEYBOX" 2>/dev/null
        return 1
    fi
    return 0
}

fetch_upstream() {
    log_info "Fetching from upstream..."

    if ! command -v xxd >/dev/null 2>&1; then
        log_warn "xxd not found, upstream source unavailable"
        return 1
    fi

    hex=$(download "$UPSTREAM_URL")
    if [ -z "$hex" ]; then
        log_warn "Upstream returned empty response"
        return 1
    fi

    mkdir -p "$AUTOMATION_DIR"

    # Stage through intermediate variable to check each step (BUG-K5)
    raw_bin=$(echo "$hex" | xxd -r -p 2>/dev/null)
    if [ -z "$raw_bin" ]; then
        log_warn "Upstream hex decode failed"
        return 1
    fi
    if ! echo "$raw_bin" | busybox base64 -d > "$TMP_KEYBOX" 2>/dev/null || [ ! -s "$TMP_KEYBOX" ]; then
        log_warn "Upstream base64 decode failed"
        rm -f "$TMP_KEYBOX" 2>/dev/null
        return 1
    fi
    return 0
}

fetch_integritybox() {
    log_info "Fetching from IntegrityBox..."

    if ! command -v xxd >/dev/null 2>&1; then
        log_warn "xxd not found, IntegrityBox source unavailable"
        return 1
    fi

    raw=$(download "$INTEGRITYBOX_URL")
    if [ -z "$raw" ]; then
        log_debug "Primary IntegrityBox URL failed, trying mirror..."
        raw=$(download "$INTEGRITYBOX_MIRROR")
    fi
    if [ -z "$raw" ]; then
        log_warn "IntegrityBox all URLs returned empty"
        return 1
    fi

    mkdir -p "$AUTOMATION_DIR"

    # Decode: 10x base64 -> hex -> ROT13 -> word filter
    # Stage through intermediate files to catch pipeline failures (BUG-K6)
    _ib_stage="$AUTOMATION_DIR/ib_stage.$$"
    echo "$raw" > "$_ib_stage.0"

    _ib_i=0
    while [ "$_ib_i" -lt 10 ]; do
        _ib_next=$((_ib_i + 1))
        if ! busybox base64 -d < "$_ib_stage.$_ib_i" > "$_ib_stage.$_ib_next" 2>/dev/null || [ ! -s "$_ib_stage.$_ib_next" ]; then
            log_warn "IntegrityBox base64 stage $((_ib_i + 1)) failed"
            rm -f "$_ib_stage".* 2>/dev/null
            return 1
        fi
        _ib_i=$_ib_next
    done

    # hex decode
    if ! xxd -r -p < "$_ib_stage.10" > "$_ib_stage.hex" 2>/dev/null || [ ! -s "$_ib_stage.hex" ]; then
        log_warn "IntegrityBox hex decode failed"
        rm -f "$_ib_stage".* 2>/dev/null
        return 1
    fi

    # ROT13
    decoded=$(tr 'A-Za-z' 'N-ZA-Mn-za-m' < "$_ib_stage.hex")
    rm -f "$_ib_stage".* 2>/dev/null

    if [ -z "$decoded" ]; then
        log_warn "IntegrityBox ROT13 produced empty output"
        return 1
    fi

    # Word filter (BUG-K7: use fixed-string sed where possible)
    for word in every soul will taste death; do
        decoded=$(printf '%s' "$decoded" | sed "s/${word}//g")
    done

    printf '%s' "$decoded" > "$TMP_KEYBOX"
    if [ ! -s "$TMP_KEYBOX" ]; then
        log_warn "IntegrityBox decode produced empty file"
        return 1
    fi
    log_info "IntegrityBox decode successful"
    return 0
}

fetch_bundled_fallback() {
    log_info "All remote sources failed, using bundled fallback..."

    # Check xxd availability (BUG-K11)
    if ! command -v xxd >/dev/null 2>&1; then
        log_error "xxd not found, bundled fallback unavailable"
        return 1
    fi

    # Check both module paths (BUG-K10)
    default_file="${MODPATH}/common/.default"
    if [ ! -f "$default_file" ]; then
        default_file="/data/adb/modules/TA_utl/common/.default"
    fi
    if [ ! -f "$default_file" ]; then
        default_file="/data/adb/modules/.TA_utl/common/.default"
    fi
    if [ ! -f "$default_file" ]; then
        log_error "Bundled fallback not found"
        return 1
    fi

    mkdir -p "$AUTOMATION_DIR"

    # Decode: hex -> base64 -> XML
    if ! xxd -r -p "$default_file" 2>/dev/null | busybox base64 -d > "$TMP_KEYBOX" 2>/dev/null || [ ! -s "$TMP_KEYBOX" ]; then
        log_warn "Bundled fallback decode failed"
        rm -f "$TMP_KEYBOX" 2>/dev/null
        return 1
    fi
    log_info "Bundled fallback decoded successfully"
    return 0
}

validate_keybox() {
    file="$1"
    if [ ! -f "$file" ]; then
        log_debug "Validation failed: file not found"
        return 1
    fi
    if [ ! -s "$file" ]; then
        log_debug "Validation failed: file empty"
        return 1
    fi

    # Structural checks (BUG-K12/K13)
    if ! grep -q "<AndroidAttestation>" "$file"; then
        log_debug "Validation failed: missing opening AndroidAttestation tag"
        return 1
    fi
    if ! grep -q "</AndroidAttestation>" "$file"; then
        log_debug "Validation failed: missing closing AndroidAttestation tag"
        return 1
    fi
    if ! grep -q "<Keybox" "$file"; then
        log_debug "Validation failed: missing Keybox element"
        return 1
    fi
    if ! grep -q "<Key algorithm=" "$file"; then
        log_debug "Validation failed: missing Key algorithm element"
        return 1
    fi
    if ! grep -q "<PrivateKey" "$file"; then
        log_debug "Validation failed: missing PrivateKey element"
        return 1
    fi
    if ! grep -q "BEGIN CERTIFICATE" "$file"; then
        log_debug "Validation failed: missing certificate"
        return 1
    fi
    return 0
}

backup_keybox() {
    if [ -f "$TARGET_KEYBOX" ]; then
        # Rotate backup: keep previous as .bak.1 (BUG-K15)
        if [ -f "$BACKUP_KEYBOX" ]; then
            cp -f "$BACKUP_KEYBOX" "${BACKUP_KEYBOX}.1" 2>/dev/null
        fi
        if ! cp -f "$TARGET_KEYBOX" "$BACKUP_KEYBOX"; then
            log_warn "Failed to backup keybox"
            return 1
        fi
        log_debug "Existing keybox backed up"
    fi
}

install_keybox() {
    src="$1"
    # Abort install if backup fails on existing keybox (BUG-K14)
    if [ -f "$TARGET_KEYBOX" ]; then
        if ! backup_keybox; then
            log_error "Backup failed, aborting install to preserve existing keybox"
            return 1
        fi
    fi
    if ! mv -f "$src" "$TARGET_KEYBOX"; then
        log_error "Failed to install keybox (mv failed)"
        return 1
    fi
    if ! chmod 644 "$TARGET_KEYBOX"; then
        log_warn "chmod failed on keybox (non-fatal)"
    fi
    log_info "Keybox installed successfully"
}

fetch_keybox() {
    kb_source=$(read_config keybox_source yurikey)
    fallback_enabled=$(read_config keybox_fallback_enabled 1)

    if [ "$kb_source" = "custom" ]; then
        log_info "Custom keybox configured, skipping fetch"
        return 0
    fi

    log_info "Starting keybox fetch (source: $kb_source, fallback: $fallback_enabled)"

    # Determine source order based on config
    case "$kb_source" in
        yurikey)      primary="fetch_yurikey"; secondary="fetch_upstream"; tertiary="fetch_integritybox" ;;
        upstream)     primary="fetch_upstream"; secondary="fetch_yurikey"; tertiary="fetch_integritybox" ;;
        integritybox) primary="fetch_integritybox"; secondary="fetch_yurikey"; tertiary="fetch_upstream" ;;
        *)            primary="fetch_yurikey"; secondary="fetch_upstream"; tertiary="fetch_integritybox" ;;
    esac

    # Try primary source
    if $primary && validate_keybox "$TMP_KEYBOX"; then
        install_keybox "$TMP_KEYBOX"
        log_info "Keybox installed from $kb_source (primary)"
        return 0
    fi
    rm -f "$TMP_KEYBOX" 2>/dev/null

    # Failover gated by keybox_fallback_enabled (BUG-K17)
    if [ "$fallback_enabled" != "1" ]; then
        log_warn "Primary failed and fallback disabled, aborting"
        return 1
    fi

    # Instant failover to secondary
    log_info "Primary failed, trying secondary..."
    if $secondary && validate_keybox "$TMP_KEYBOX"; then
        install_keybox "$TMP_KEYBOX"
        log_info "Keybox installed from secondary (failover)"
        return 0
    fi
    rm -f "$TMP_KEYBOX" 2>/dev/null

    # Try tertiary
    log_info "Secondary failed, trying tertiary..."
    if $tertiary && validate_keybox "$TMP_KEYBOX"; then
        install_keybox "$TMP_KEYBOX"
        log_info "Keybox installed from tertiary (failover)"
        return 0
    fi
    rm -f "$TMP_KEYBOX" 2>/dev/null

    # Never overwrite a valid keybox with the generic bundled one
    if [ -f "$TARGET_KEYBOX" ] && validate_keybox "$TARGET_KEYBOX"; then
        log_warn "All remote sources failed, keeping existing keybox"
        rm -f "$TMP_KEYBOX" 2>/dev/null
        return 1
    fi

    # Final fallback: bundled .default (fresh install only)
    if fetch_bundled_fallback && validate_keybox "$TMP_KEYBOX"; then
        install_keybox "$TMP_KEYBOX"
        log_info "Keybox installed from bundled fallback"
        return 0
    fi

    log_error "All keybox sources failed"
    rm -f "$TMP_KEYBOX" 2>/dev/null
    return 1
}

# CLI entry point when run directly
case "$1" in
    --fetch)
        . "$MODPATH/common/logging.sh"
        log_init "KEYBOX" "main"
        . "$MODPATH/common/utils.sh"
        fetch_keybox
        exit $?
        ;;
    --validate)
        . "$MODPATH/common/logging.sh"
        log_init "KEYBOX" "main"
        if [ -n "$2" ]; then
            validate_keybox "$2" && echo "valid" || echo "invalid"
        else
            validate_keybox "$TARGET_KEYBOX" && echo "valid" || echo "invalid"
        fi
        exit
        ;;
    --backup)
        . "$MODPATH/common/logging.sh"
        log_init "KEYBOX" "main"
        backup_keybox
        exit
        ;;
    --source)
        . "$MODPATH/common/utils.sh"
        read_config keybox_source "yurikey"
        exit
        ;;
esac
