# install_func.sh - Installation functions for Tricky Addon (Enhanced)
# This file is sourced by customize.sh (logging.sh already sourced there)

AUTOMATION_DIR="/data/adb/tricky_store/.automation"
EXCLUDE_FILE="$AUTOMATION_DIR/exclude_patterns.txt"
KNOWN_PACKAGES="$AUTOMATION_DIR/known_packages.txt"
TARGET_FILE="/data/adb/tricky_store/target.txt"

initialize() {
    log_info "Initializing module structure"

    # Cleanup leftover from previous installs
    if [ -d "/data/adb/modules/$NEW_MODID" ]; then
        rm -rf "/data/adb/modules/$NEW_MODID"
        log_debug "Removed leftover module directory"
    fi

    set_perm "$COMPATH/get_extra.sh" 0 2000 0755
    set_perm "$COMPATH/automation.sh" 0 2000 0755

    if [ "$ACTION" = "false" ]; then
        rm -f "$MODPATH/action.sh"
        NEW_MODID="$MODID"
        log_debug "Non-Magisk mode: removed action.sh"
    else
        mkdir -p "$COMPATH/update/common"
        if ! cp "$COMPATH/.default" "$COMPATH/update/common/.default"; then
            log_warn "Failed to copy .default to update directory"
        fi
        if ! cp "$MODPATH/uninstall.sh" "$COMPATH/update/uninstall.sh"; then
            log_warn "Failed to copy uninstall.sh to update directory"
        fi
        log_debug "Magisk mode: prepared update structure"
    fi

    cp "$MODPATH/module.prop" "$COMPATH/update/module.prop"
    mkdir -p "$COMPATH/bin"

    local abi
    abi=$(getprop ro.product.cpu.abi)
    if [ -d "$MODPATH/bin/$abi" ]; then
        mv "$MODPATH/bin/$abi/"* "$COMPATH/bin/"
        set_perm_recursive "$COMPATH/bin" 0 2000 0755 0755
        log_info "Installed binaries for $abi"
    else
        log_warn "No binaries found for ABI: $abi"
    fi
    rm -rf "$MODPATH/bin"

    mkdir -p "$AUTOMATION_DIR"
}

find_config() {
    # Remove legacy setup
    [ -f "$SCRIPT_DIR/UpdateTargetList.sh" ] && rm -f "$SCRIPT_DIR/UpdateTargetList.sh"
    [ -d "$CONFIG_DIR" ] && rm -rf "$CONFIG_DIR"
}

migrate_config() {
    # Validate boot_hash: must be exactly 64 lowercase hex chars
    if [ -f "/data/adb/boot_hash" ]; then
        hash_value=$(grep -v '^#' "/data/adb/boot_hash" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
        if echo "$hash_value" | grep -qE '^[a-f0-9]{64}$'; then
            echo "$hash_value" > /data/adb/boot_hash
        else
            log_warn "boot_hash invalid (${#hash_value} chars), removing"
            rm -f /data/adb/boot_hash
        fi
    fi

    # Migrate security_patch config
    if [ -f "/data/adb/security_patch" ]; then
        if grep -q "^auto_config=1" "/data/adb/security_patch"; then
            touch "/data/adb/tricky_store/security_patch_auto_config"
        fi
        rm -f "/data/adb/security_patch"
    fi

    # Additional system app
    if [ ! -f "/data/adb/tricky_store/system_app" ]; then
        SYSTEM_APP="
        com.google.android.gms
        com.google.android.gsf
        com.android.vending
        com.oplus.deepthinker
        com.heytap.speechassist
        com.coloros.sceneservice"
        touch "/data/adb/tricky_store/system_app"
        for app in $SYSTEM_APP; do
            if pm list packages -s | sed 's/^package://' | grep -qxF "$app"; then
                echo "$app" >> "/data/adb/tricky_store/system_app"
            fi
        done
    fi
}

# Volume key detection with timeout (adapted from SFS reference)
choose_automation() {
    local vol_tmp="$TMPDIR/vol_key"
    local seconds=10
    local ge_pid=""

    : > "$vol_tmp"
    getevent -qlc 1 > "$vol_tmp" 2>/dev/null &
    ge_pid=$!

    while [ "$seconds" -gt 0 ]; do
        sleep 1
        if ! kill -0 "$ge_pid" 2>/dev/null; then
            local key
            key=$(awk '/KEY_/{print $3}' "$vol_tmp" 2>/dev/null)
            case "$key" in
                KEY_VOLUMEUP)
                    rm -f "$vol_tmp"
                    return 0
                    ;;
                KEY_VOLUMEDOWN)
                    rm -f "$vol_tmp"
                    return 1
                    ;;
            esac
            # Unrecognized key — restart listener
            : > "$vol_tmp"
            getevent -qlc 1 > "$vol_tmp" 2>/dev/null &
            ge_pid=$!
        fi
        seconds=$((seconds - 1))
    done

    kill "$ge_pid" 2>/dev/null
    wait "$ge_pid" 2>/dev/null
    rm -f "$vol_tmp"
    return 0
}

# System-apps-only target.txt for manual mode
generate_minimal_target() {
    log_info "Generating minimal target.txt (system apps only)"

    local system_apps="com.google.android.gms
com.google.android.gsf
com.android.vending"

    if [ "$(getprop ro.product.brand)" = "OnePlus" ]; then
        system_apps="$system_apps
com.oplus.engineermode"
        log_debug "Added OnePlus engineermode to system apps"
    fi

    echo "$system_apps" | sort -u > "$TARGET_FILE"

    # Seed known_packages so daemon works if re-enabled later
    pm list packages -3 2>/dev/null | sed 's/^package://' | sort > "$KNOWN_PACKAGES"

    local count
    count=$(wc -l < "$TARGET_FILE" 2>/dev/null || echo 0)
    log_info "Minimal target.txt generated: $count system apps"
    ui_print "  📝 Target.txt: $count system apps"
}

# Build exclude list from more-exclude.json
build_exclude_list() {
    log_info "Building exclude list"
    mkdir -p "$AUTOMATION_DIR"

    if [ -f "$MODPATH/more-exclude.json" ]; then
        grep '"package-name"' "$MODPATH/more-exclude.json" | sed 's/.*"package-name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' > "$EXCLUDE_FILE"
        log_debug "Extracted patterns from more-exclude.json"
    else
        log_warn "more-exclude.json not found"
        : > "$EXCLUDE_FILE"
    fi

    # Add hardcoded root manager packages that might not be in the JSON
    # These are from TSE's usr.txt concept
    cat >> "$EXCLUDE_FILE" << 'EOF'
com.topjohnwu.magisk
io.github.vvb2060.magisk
io.github.huskydg.magisk
me.weishu.kernelsu
com.rifsxd.ksunext
com.sukisu.ultra
me.bmax.apatch
me.garfieldhan.apatch.next
com.android.patch
org.lsposed.manager
EOF

    ui_print "  🔎 Scanning for Xposed modules..."
    local xposed_tmp="$AUTOMATION_DIR/xposed_detected.tmp"
    : > "$xposed_tmp"

    for pkg in $(pm list packages -3 2>/dev/null | sed 's/^package://'); do
        [ -z "$pkg" ] && continue
        apk_path=$(pm path "$pkg" 2>/dev/null | head -n1 | cut -d: -f2)
        [ -z "$apk_path" ] && continue

        if unzip -l "$apk_path" 2>/dev/null | grep -q "assets/xposed_init"; then
            echo "$pkg" >> "$xposed_tmp"
            log_debug "Excluded Xposed module (xposed_init): $pkg"
        elif unzip -p "$apk_path" AndroidManifest.xml 2>/dev/null | tr -d '\0' | grep -q "xposedmodule"; then
            echo "$pkg" >> "$xposed_tmp"
            log_debug "Excluded Xposed module (manifest): $pkg"
        fi
    done

    [ -s "$xposed_tmp" ] && cat "$xposed_tmp" >> "$EXCLUDE_FILE"
    local xposed_count
    xposed_count=$(wc -l < "$xposed_tmp" 2>/dev/null || echo 0)
    ui_print "  🔎 Found $xposed_count Xposed modules"
    rm -f "$xposed_tmp"

    sort -u "$EXCLUDE_FILE" -o "$EXCLUDE_FILE"

    local count
    count=$(wc -l < "$EXCLUDE_FILE" 2>/dev/null || echo 0)
    log_info "Exclude list built: $count patterns ($xposed_count Xposed)"
    ui_print "  📋 Exclude list: $count patterns"
}

# Generate initial target.txt from installed packages
generate_initial_target() {
    log_info "Generating initial target.txt"

    local user_packages
    user_packages=$(pm list packages -3 2>/dev/null | sed 's/^package://' | sort)

    if [ -z "$user_packages" ]; then
        log_warn "No user packages found (pm list failed?)"
    fi

    local system_apps="com.google.android.gms
com.google.android.gsf
com.android.vending"

    if [ "$(getprop ro.product.brand)" = "OnePlus" ]; then
        system_apps="$system_apps
com.oplus.engineermode"
        log_debug "Added OnePlus engineermode to system apps"
    fi

    {
        if [ -s "$EXCLUDE_FILE" ]; then
            echo "$user_packages" | grep -vxFf "$EXCLUDE_FILE" 2>/dev/null
        else
            echo "$user_packages"
        fi
        echo "$system_apps"
    } | sort -u > "$TARGET_FILE"

    if [ ! -s "$TARGET_FILE" ]; then
        log_warn "target.txt may be empty or generation failed"
    fi

    echo "$user_packages" > "$KNOWN_PACKAGES"

    local count
    count=$(wc -l < "$TARGET_FILE" 2>/dev/null || echo 0)
    log_info "Target.txt generated: $count apps"
    ui_print "  📝 Target.txt: $count apps"
}

