#!/system/bin/sh

TS_MODULE="/data/adb/modules/tricky_store"
TS_DIR="/data/adb/tricky_store"
TARGET_FILE="$TS_DIR/target.txt"
ENHANCED_CONF="$TS_DIR/enhanced.conf"
BOOT_HASH_FILE="/data/adb/boot_hash"
PROP_FILE="$TS_MODULE/module.prop"
ORIGINAL_DESC_FILE="$TS_DIR/.original_description"
TA_MODULE="/data/adb/modules/TA_utl"
TA_HIDDEN="/data/adb/modules/.TA_utl"
POLL_INTERVAL=30

count_active_apps() {
    [ ! -f "$TARGET_FILE" ] && echo 0 && return

    tmp_installed="$TS_DIR/.status_installed.$$"
    tmp_targets="$TS_DIR/.status_targets.$$"

    pm list packages 2>/dev/null | cut -d: -f2 | tr -d '\r ' > "$tmp_installed"
    [ ! -s "$tmp_installed" ] && echo 0 && rm -f "$tmp_installed" && return

    sed '/^$/d; s/[!?]$//' "$TARGET_FILE" | tr -d '\r ' > "$tmp_targets"

    count=$(grep -cxFf "$tmp_targets" "$tmp_installed" 2>/dev/null)
    count=${count:-0}

    rm -f "$tmp_installed" "$tmp_targets"
    echo "$count"
}

get_keybox_label() {
    case "$(read_config keybox_source yurikey)" in
        yurikey)      echo "Yurikey" ;;
        upstream)     echo "Upstream" ;;
        integritybox) echo "IntegrityBox" ;;
        custom)       echo "Custom" ;;
        *)            echo "Unknown" ;;
    esac
}

get_patch_level() {
    # Read configured value first — that's what the attestation engine uses
    if [ -f "$TS_DIR/security_patch.txt" ]; then
        patch=$(grep "^boot=" "$TS_DIR/security_patch.txt" 2>/dev/null | cut -d= -f2)
        [ -n "$patch" ] && echo "$patch" && return
    fi
    patch=$(getprop ro.build.version.security_patch 2>/dev/null)
    echo "${patch:-unknown}"
}

get_vbhash_active() {
    [ -f "$BOOT_HASH_FILE" ] || return 1
    hash=$(grep -v '^#' "$BOOT_HASH_FILE" 2>/dev/null | tr -d '[:space:]')
    [ ${#hash} -eq 64 ]
}

build_description() {
    apps=$(count_active_apps)
    kb=$(get_keybox_label)
    patch=$(get_patch_level)
    get_vbhash_active && vb="🔒 VBHash" || vb="⚠️ No VBHash"

    if [ "$apps" -gt 0 ] 2>/dev/null; then
        echo "⚡ ${apps} Apps │ 🔑 ${kb} │ 🛡️ ${patch} │ ${vb}"
    else
        echo "😴 No targets │ 🔑 ${kb} │ 🛡️ ${patch} │ ${vb}"
    fi
}

save_original_description() {
    [ -f "$ORIGINAL_DESC_FILE" ] && return 0
    [ ! -f "$PROP_FILE" ] && return 1
    grep "^description=" "$PROP_FILE" 2>/dev/null | cut -d= -f2- > "$ORIGINAL_DESC_FILE"
}

update_prop_description() {
    [ ! -f "$PROP_FILE" ] && return 1
    sed -i "s|^description=.*|description=${1}|" "$PROP_FILE" 2>/dev/null
}

monitor_status() {
    log_info "Status monitor started (interval=${POLL_INTERVAL}s)"

    save_original_description

    if is_uninstall_pending; then
        log_info "Uninstall already pending, exiting"
        return
    fi

    last=""

    desc=$(build_description)
    update_prop_description "$desc" && last="$desc"
    log_info "Initial: $desc"

    while true; do
        sleep "$POLL_INTERVAL"

        [ ! -d "$TS_MODULE" ] && continue
        [ -f "$TS_MODULE/disable" ] && continue
        [ ! -f "$PROP_FILE" ] && continue

        if is_uninstall_pending; then
            log_info "Uninstall detected, restoring description"
            if [ -f "$ORIGINAL_DESC_FILE" ]; then
                orig=$(cat "$ORIGINAL_DESC_FILE" 2>/dev/null)
                [ -n "$orig" ] && update_prop_description "$orig"
            fi
            break
        fi

        desc=$(build_description)
        [ "$desc" = "$last" ] && continue

        update_prop_description "$desc"
        last="$desc"
        log_info "Updated: $desc"
    done
}
