#!/bin/sh
# security_patch_manager.sh - Automated security patch date synchronization

TS_DIR="/data/adb/tricky_store"
AUTOMATION_DIR="$TS_DIR/.automation"
ENHANCED_CONF="$TS_DIR/enhanced.conf"
SECURITY_PATCH_FILE="$TS_DIR/security_patch.txt"

MODPATH="${MODPATH:-${0%/*}/..}"
PATH="$MODPATH/common/bin:/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH"

. "$MODPATH/common/logging.sh"
log_init "PATCH" "boot"
. "$MODPATH/common/utils.sh"

download() {
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl --connect-timeout 10 -Ls "$url"
    else
        busybox wget -T 10 --no-check-certificate -qO- "$url"
    fi
}

ensure_dirs() {
    if ! mkdir -p "$AUTOMATION_DIR" 2>/dev/null; then
        log_warn "Failed to create automation directory"
    fi
}

get_system_patch_date() {
    date=$(getprop ro.build.version.security_patch 2>/dev/null)
    if [ -z "$date" ]; then
        log_debug "System patch date not found"
    fi
    echo "$date"
}

get_boot_patch_date() {
    date=$(getprop ro.bootimage.build.date.security_patch 2>/dev/null)
    [ -z "$date" ] && date=$(getprop ro.vendor.build.security_patch 2>/dev/null)
    [ -z "$date" ] && date=$(get_system_patch_date)
    echo "$date"
}

get_vendor_patch_date() {
    date=$(getprop ro.vendor.build.security_patch 2>/dev/null)
    [ -z "$date" ] && date=$(get_system_patch_date)
    echo "$date"
}

fetch_latest_patch() {
    log_debug "Fetching latest patch from source.android.com..."

    page=$(download "https://source.android.com/docs/security/bulletin/pixel")

    if [ -z "$page" ]; then
        log_warn "Failed to download security bulletin page"
        return 1
    fi

    # Primary: <td>YYYY-MM-DD</td> format
    patch=$(echo "$page" | \
            sed -n 's/.*<td>\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)<\/td>.*/\1/p' | \
            head -n 1)

    # Fallback: any YYYY-MM-DD date in the page (broader match)
    if [ -z "$patch" ]; then
        log_debug "Primary parse failed, trying fallback regex"
        patch=$(echo "$page" | \
                grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | \
                head -n 1)
    fi

    if [ -n "$patch" ] && echo "$patch" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
        log_info "Fetched latest patch: $patch"
        echo "$patch"
        return 0
    fi

    log_warn "Failed to parse security patch date from Google bulletin"
    return 1
}

detect_tricky_store_variant() {
    ts_prop="/data/adb/modules/tricky_store/module.prop"
    if [ ! -f "$ts_prop" ]; then
        log_warn "TrickyStore module.prop not found"
        echo "legacy"
        return 0
    fi

    # James Clef's fork uses devconfig.toml
    if grep -q "James" "$ts_prop" 2>/dev/null; then
        if ! grep -q "beakthoven" "$ts_prop" 2>/dev/null; then
            log_debug "Detected TrickyStore variant: james"
            echo "james"
            return 0
        fi
    fi

    # TEESimulator and standard TrickyStore both use security_patch.txt
    version=$(grep "versionCode=" "$ts_prop" 2>/dev/null | cut -d'=' -f2)
    # Validate numeric before -ge comparison
    case "$version" in ''|*[!0-9]*) version=0 ;; esac
    if grep -q "TEESimulator" "$ts_prop" 2>/dev/null || [ "$version" -ge 158 ] 2>/dev/null || grep -q "beakthoven" "$ts_prop" 2>/dev/null; then
        log_debug "Detected TrickyStore variant: standard"
        echo "standard"
        return 0
    fi

    log_debug "Detected TrickyStore variant: legacy"
    echo "legacy"
}

set_security_patch() {
    ensure_dirs

    system_date=$(get_system_patch_date)
    boot_date=$(get_boot_patch_date)
    vendor_date=$(get_vendor_patch_date)

    if [ -z "$system_date" ]; then
        log_error "Could not read system security patch"
        return 1
    fi

    variant=$(detect_tricky_store_variant)

    case "$variant" in
        james)
            config_file="$TS_DIR/devconfig.toml"
            if grep -q "^securityPatch" "$config_file" 2>/dev/null; then
                if ! sed -i "s/^securityPatch .*/securityPatch = \"$system_date\"/" "$config_file"; then
                    log_error "sed failed on devconfig.toml"
                    return 1
                fi
            else
                if ! grep -q "^\[deviceProps\]" "$config_file" 2>/dev/null; then
                    if ! echo "securityPatch = \"$system_date\"" >> "$config_file"; then
                        log_error "Failed to append to devconfig.toml"
                        return 1
                    fi
                else
                    if ! sed -i "/^\[deviceProps\]/i securityPatch = \"$system_date\"" "$config_file"; then
                        log_error "sed insert failed on devconfig.toml"
                        return 1
                    fi
                fi
            fi
            log_info "Set (james): $system_date"
            ;;
        standard)
            # Write actual dates — TrickyStore/TEESimulator reads these values directly.
            # "prop" directive is redundant when we also resetprop the same property.
            if ! cat > "$SECURITY_PATCH_FILE" << EOF
system=$system_date
boot=$boot_date
vendor=$vendor_date
EOF
            then
                log_error "Failed to write security_patch.txt"
                return 1
            fi
            chmod 644 "$SECURITY_PATCH_FILE"
            log_info "Set (standard): system=$system_date, boot=$boot_date, vendor=$vendor_date"
            ;;
        legacy)
            _patch_fail=0
            resetprop ro.vendor.build.security_patch "$vendor_date" 2>/dev/null || _patch_fail=$((_patch_fail + 1))
            resetprop ro.build.version.security_patch "$system_date" 2>/dev/null || _patch_fail=$((_patch_fail + 1))
            if [ "$_patch_fail" -gt 0 ]; then
                log_warn "Set (legacy): $_patch_fail resetprop failures"
            else
                log_info "Set (legacy/resetprop): system=$system_date, vendor=$vendor_date"
            fi
            ;;
    esac

    return 0
}

set_security_patch_custom() {
    system_date="$1"
    boot_date="$2"
    vendor_date="$3"

    [ -z "$system_date" ] && system_date="prop"
    [ -z "$boot_date" ] && boot_date=$(get_boot_patch_date)
    [ -z "$vendor_date" ] && vendor_date=$(get_vendor_patch_date)

    ensure_dirs

    variant=$(detect_tricky_store_variant)

    case "$variant" in
        james)
            config_file="$TS_DIR/devconfig.toml"
            [ "$system_date" = "prop" ] && date_value=$(get_system_patch_date) || date_value="$system_date"
            if grep -q "^securityPatch" "$config_file" 2>/dev/null; then
                if ! sed -i "s/^securityPatch .*/securityPatch = \"$date_value\"/" "$config_file"; then
                    log_error "sed failed on devconfig.toml (custom)"
                    return 1
                fi
            else
                if ! echo "securityPatch = \"$date_value\"" >> "$config_file"; then
                    log_error "Failed to append to devconfig.toml (custom)"
                    return 1
                fi
            fi
            log_info "Custom (james): $date_value"
            ;;
        standard)
            if ! cat > "$SECURITY_PATCH_FILE" << EOF
system=$system_date
boot=$boot_date
vendor=$vendor_date
EOF
            then
                log_error "Failed to write security_patch.txt (custom)"
                return 1
            fi
            chmod 644 "$SECURITY_PATCH_FILE"
            log_info "Custom: system=$system_date, boot=$boot_date, vendor=$vendor_date"
            ;;
        legacy)
            _patch_fail=0
            resetprop ro.build.version.security_patch "$system_date" 2>/dev/null || _patch_fail=$((_patch_fail + 1))
            resetprop ro.vendor.build.security_patch "$vendor_date" 2>/dev/null || _patch_fail=$((_patch_fail + 1))
            if [ "$_patch_fail" -gt 0 ]; then
                log_warn "Custom (legacy): $_patch_fail resetprop failures"
            else
                log_info "Custom (legacy/resetprop): system=$system_date, vendor=$vendor_date"
            fi
            ;;
    esac

    return 0
}

auto_update_security_patch() {
    auto_enabled=$(read_config "security_patch_auto" "1")

    if [ "$auto_enabled" != "1" ]; then
        log_debug "Auto-update disabled, skipping"
        return 0
    fi

    log_info "Auto-update triggered"

    latest_patch=$(fetch_latest_patch)
    if [ -n "$latest_patch" ]; then
        set_security_patch_custom "prop" "$latest_patch" "$latest_patch"
    else
        log_warn "Google fetch failed, keeping current patch level"
        return 1
    fi
}

show_current() {
    echo "=== Security Patch Dates ==="
    echo "System: $(get_system_patch_date)"
    echo "Boot:   $(get_boot_patch_date)"
    echo "Vendor: $(get_vendor_patch_date)"
    echo ""
    echo "Tricky Store variant: $(detect_tricky_store_variant)"
    if [ -f "$SECURITY_PATCH_FILE" ]; then
        echo ""
        echo "Current config ($SECURITY_PATCH_FILE):"
        cat "$SECURITY_PATCH_FILE"
    fi
}

case "$1" in
    --set)
        set_security_patch
        ;;
    --set-custom)
        set_security_patch_custom "$2" "$3" "$4"
        ;;
    --auto)
        auto_update_security_patch
        ;;
    --show)
        show_current
        ;;
    *)
        # When sourced, functions are available; when run directly with no args, show help
        # Check if script name matches (run directly) vs being sourced
        case "$(basename "$0" 2>/dev/null)" in
            security_patch_manager.sh)
                echo "Usage: $0 {--set|--set-custom SYSTEM BOOT VENDOR|--auto|--show}"
                echo ""
                echo "  --set          Read device props and set security patch dates"
                echo "  --set-custom   Set custom dates (use 'prop' for system to use device value)"
                echo "  --auto         Check config and set if auto-update enabled"
                echo "  --show         Display current security patch information"
                exit 1
                ;;
        esac
        ;;
esac
