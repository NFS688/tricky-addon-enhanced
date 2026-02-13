MODPATH=${0%/*}
PATH=$MODPATH/common/bin:/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH
HIDE_DIR="/data/adb/modules/.TA_utl"
TS="/data/adb/modules/tricky_store"
TSPA="/data/adb/modules/tsupport-advance"
TS_DIR="/data/adb/tricky_store"

. "$MODPATH/common/logging.sh"
log_init "BOOT" "boot"

. "$MODPATH/common/utils.sh"

log_info "Service started"

add_denylist_to_target() {
    target_file="/data/adb/tricky_store/target.txt"
    tmp_file="${target_file}.tmp"
    exclamation_target=$(grep '!' "$target_file" | sed 's/!$//')
    question_target=$(grep '?' "$target_file" | sed 's/?$//')
    existing=$(sed 's/[!?]$//' "$target_file")
    denylist=$(magisk --denylist ls 2>/dev/null | awk -F'|' '{print $1}' | grep -v "isolated")

    if ! printf "%s\n" "$existing" "$denylist" | sort -u > "$tmp_file"; then
        log_error "Failed to write target.txt from denylist"
        rm -f "$tmp_file"
        return 1
    fi

    for pkg in $exclamation_target; do
        sed -i "s/^${pkg}$/${pkg}!/" "$tmp_file"
    done

    for pkg in $question_target; do
        sed -i "s/^${pkg}$/${pkg}?/" "$tmp_file"
    done

    mv "$tmp_file" "$target_file"
}

# Spoof security patch
if [ -f "/data/adb/tricky_store/security_patch_auto_config" ]; then
    if ! sh "$MODPATH/common/get_extra.sh" --security-patch; then
        log_warn "Security patch spoof via get_extra failed"
    fi
fi

# Handle sensitive prop in background
log_info "Prop spoofing started"
sh "$MODPATH/prop.sh" &

# Disable TSupport-A auto update target to prevent overwrite
if [ -d "$TSPA" ]; then
    if ! touch "/storage/emulated/0/stop-tspa-auto-target" 2>/dev/null; then
        log_warn "Failed to create TSPA stop file (storage not ready)"
    fi
elif [ ! -d "$TSPA" ] && [ -f "/storage/emulated/0/stop-tspa-auto-target" ]; then
    rm -f "/storage/emulated/0/stop-tspa-auto-target"
fi

# Magisk operation
if [ -f "$MODPATH/action.sh" ]; then
    # Hide module from Magisk manager
    if [ "$MODPATH" != "$HIDE_DIR" ]; then
        log_info "Module hiding (Magisk)"
        rm -rf "$HIDE_DIR"
        if ! mkdir -p "$HIDE_DIR"; then
            log_error "Failed to create hide directory: $HIDE_DIR"
        fi
        if ! busybox chcon --reference="$MODPATH" "$HIDE_DIR" 2>/dev/null; then
            log_warn "chcon failed on hide directory (selinux may be permissive)"
        fi
        if ! cp -af "$MODPATH/." "$HIDE_DIR/"; then
            log_error "Failed to copy module to hide directory"
        fi
    fi
    MODPATH="$HIDE_DIR"

    # Add target from denylist
    [ -f "/data/adb/tricky_store/target_from_denylist" ] && add_denylist_to_target
else
    [ -d "$HIDE_DIR" ] && rm -rf "$HIDE_DIR"
fi

# Hide module from APatch, KernelSU, KSUWebUIStandalone, MMRL
rm -f "$MODPATH/module.prop"

# Symlink tricky store
if [ -f "$MODPATH/action.sh" ] && [ ! -e "$TS/action.sh" ]; then
    if ln -s "$MODPATH/action.sh" "$TS/action.sh" 2>/dev/null; then
        log_info "Symlink created: action.sh"
    else
        log_warn "Failed to create action.sh symlink"
    fi
fi
if [ ! -e "$TS/webroot" ]; then
    if ln -s "$MODPATH/webui" "$TS/webroot" 2>/dev/null; then
        log_info "Symlink created: webroot"
    else
        log_warn "Failed to create webroot symlink"
    fi
fi

log_info "Waiting for boot completion"
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 1
done
log_info "Boot completed detected"

# VBHash extraction (prop.sh handles all property spoofing)
vbhash_enabled=$(read_config vbhash_enabled 1)
if [ "$vbhash_enabled" = "1" ] && [ -f "$MODPATH/common/vbhash_manager.sh" ]; then
    log_info "Running VBHash extraction..."
    if ! sh "$MODPATH/common/vbhash_manager.sh" --extract; then
        log_warn "VBHash extraction returned non-zero"
    fi
elif [ "$vbhash_enabled" != "1" ]; then
    log_info "VBHash extraction disabled by config"
fi

# Check for module conflicts at boot
if [ -f "$MODPATH/common/conflict_manager.sh" ]; then
    . "$MODPATH/common/conflict_manager.sh"
    log_info "Checking for conflicts at boot..."
    if ! check_module_conflicts; then
        log_warn "Conflicts detected, check conflict.log"
    fi
fi

# Create temporary directory
if ! mkdir -p "$MODPATH/common/tmp"; then
    log_warn "Failed to create tmp directory"
fi

sh "$MODPATH/common/get_extra.sh" --xposed >> "$LOG_BASE_DIR/main.log" 2>&1 &

[ -f "$MODPATH/action.sh" ] && rm -rf "/data/adb/modules/TA_utl"

# Native fork/wait supervisor — all background processes under one watchdog
# Exit 42 = uninstall (don't respawn), other exits = crash (respawn with backoff)
log_info "Starting native supervisor for all background processes"
"$MODPATH/common/bin/supervisor" \
    "$MODPATH/common/run_keybox.sh" \
    "$MODPATH/common/run_secpatch.sh" \
    "$MODPATH/common/run_daemon.sh" \
    "$MODPATH/common/run_health.sh" \
    "$MODPATH/common/run_status.sh" &
sup_pid=$!
mkdir -p "/data/adb/tricky_store/.automation"
echo "$sup_pid" > "/data/adb/tricky_store/.automation/supervisor.pid"
log_info "Supervisor started (pid=$sup_pid)"
