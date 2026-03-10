MODPATH=${0%/*}
MODDIR="$MODPATH"
PATH=$MODPATH/common/bin:/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH
HIDE_DIR="/data/adb/modules/.TA_enhanced"
TSPA="/data/adb/modules/tsupport-advance"

. "$MODPATH/common/common.sh"
detect_manager

_log "INFO" "Service started (manager=$MANAGER)"

# Denylist merge function (Magisk only)
add_denylist_to_target() {
    local target_file="$TS_DIR/target.txt"
    local tmp_file="${target_file}.tmp"
    local exclamation_target question_target existing denylist

    exclamation_target=$(grep '!' "$target_file" | sed 's/!$//')
    question_target=$(grep '?' "$target_file" | sed 's/?$//')
    existing=$(sed 's/[!?]$//' "$target_file")
    denylist=$(magisk --denylist ls 2>/dev/null | awk -F'|' '{print $1}' | grep -v "isolated")

    if ! printf "%s\n" "$existing" "$denylist" | sort -u > "$tmp_file"; then
        _log "ERROR" "Failed to write target.txt from denylist"
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

# Security patch is handled by the daemon's SecurityPatchTask (with retries + bulletin fetch).
# Running `set` here would overwrite bulletin-fetched dates with stale device props.

# Property Spoofing (background)
_log "INFO" "Prop spoofing started"
sh "$MODPATH/prop.sh" &

# TSupport-A Interop
if [ -d "$TSPA" ]; then
    touch "/storage/emulated/0/stop-tspa-auto-target" 2>/dev/null || true
elif [ ! -d "$TSPA" ] && [ -f "/storage/emulated/0/stop-tspa-auto-target" ]; then
    rm -f "/storage/emulated/0/stop-tspa-auto-target"
fi

# Magisk Module Hiding
# Dot-prefix hides from Magisk's module list scan (stable since Magisk v24+).
# service.sh re-copies on every boot so the hidden copy is always fresh.
if [ -f "$MODPATH/action.sh" ]; then
    if [ "$MODPATH" != "$HIDE_DIR" ]; then
        _log "INFO" "Module hiding (Magisk)"
        rm -rf "$HIDE_DIR"
        mkdir -p "$HIDE_DIR"
        busybox chcon --reference="$MODPATH" "$HIDE_DIR" 2>/dev/null || true
        if ! cp -af "$MODPATH/." "$HIDE_DIR/"; then
            _log "ERROR" "Module hiding copy failed, using original path"
            rm -rf "$HIDE_DIR"
        else
            MODPATH="$HIDE_DIR"
            MODDIR="$MODPATH"
            BIN="$MODPATH/bin/${ABI}/ta-enhanced"
        fi
    fi

    # Merge Magisk denylist into target.txt (flag-file-gated)
    [ -f "$TS_DIR/target_from_denylist" ] && add_denylist_to_target
else
    # KSU/APatch: clean up any stale hidden dir
    [ -d "$HIDE_DIR" ] && rm -rf "$HIDE_DIR"
fi

# Ensure system_app file exists for WebUI system app display
if [ ! -f "$TS_DIR/system_app" ]; then
    : > "$TS_DIR/system_app"
    for app in com.google.android.gms com.google.android.gsf com.android.vending \
               com.oplus.deepthinker com.heytap.speechassist com.coloros.sceneservice; do
        pm list packages -s 2>/dev/null | grep -q "package:$app" && echo "$app" >> "$TS_DIR/system_app"
    done
fi

mkdir -p "/data/adb/tricky_store/ta-enhanced/bin"

cp -f "$MODPATH/bin/${ABI}/resetprop-rs" "/data/adb/tricky_store/ta-enhanced/bin/resetprop-rs" 2>/dev/null
chmod 755 "/data/adb/tricky_store/ta-enhanced/bin/resetprop-rs" 2>/dev/null

# Preserve module.prop for WebUI version display, then hide from manager UI
cp -f "$MODPATH/module.prop" "/data/adb/tricky_store/ta-enhanced/module.prop" 2>/dev/null || true
rm -f "$MODPATH/module.prop"

# Symlink Management
if [ -f "$MODPATH/action.sh" ] && [ ! -e "$TS/action.sh" ]; then
    ln -s "$MODPATH/action.sh" "$TS/action.sh" 2>/dev/null || true
fi
if [ ! -e "$TS/webroot" ]; then
    ln -s "$MODPATH/webui" "$TS/webroot" 2>/dev/null || true
fi
if [ ! -e "$TS/banner.png" ] && [ -f "$MODPATH/banner.png" ]; then
    ln -s "$MODPATH/banner.png" "$TS/banner.png" 2>/dev/null || true
fi
if [ -f "$TS/module.prop" ] && ! grep -q "^banner=" "$TS/module.prop"; then
    sed -i '$ a\banner=banner.png' "$TS/module.prop" 2>/dev/null || true
fi

# Wait for Boot Completion
_log "INFO" "Waiting for boot completion"
# getprop -w blocks until property is set (Android 10+)
# Timeout after 120s to prevent hanging on broken boots
timeout 120 getprop -w sys.boot_completed 2>/dev/null || {
    until [ "$(getprop sys.boot_completed)" = "1" ]; do
        sleep 5
    done
}
_log "INFO" "Boot completed"

_log "INFO" "Running property cleanup"
sh "$MODPATH/propclean.sh" &

pm list packages -s 2>/dev/null | sed 's/^package://' | sort > "/data/adb/tricky_store/ta-enhanced/system_packages.txt"

# VBHash Extraction (config-gated)
vbhash_enabled=$(read_config vbhash.enabled true)
if [ "$vbhash_enabled" = "true" ]; then
    _log "INFO" "Running VBHash extraction"
    "$BIN" vbhash extract 2>/dev/null || _log "WARN" "VBHash extraction failed"
else
    _log "INFO" "VBHash extraction disabled"
fi

# Conflict Check
_log "INFO" "Checking for conflicts at boot"
"$BIN" conflict check 2>/dev/null || _log "WARN" "Conflicts detected, check conflict.log"

# Create tmp directory (needed by action.sh for KSU WebUI APK download)
mkdir -p "$MODPATH/common/tmp"

# Xposed Detection (background)
"$BIN" status xposed-scan >> "$LOG_BASE_DIR/main.log" 2>&1 &

# Magisk: clean up unhidden module dir
[ -f "$MODPATH/action.sh" ] && rm -rf "/data/adb/modules/TA_enhanced"

# Launch Daemon
_log "INFO" "Starting ta-enhanced daemon"
"$BIN" daemon --manager "$MANAGER" &
_log "INFO" "Daemon launched"
