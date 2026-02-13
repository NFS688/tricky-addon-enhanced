MODPATH=${0%/*}
TS="/data/adb/modules/tricky_store"
SCRIPT_DIR="/data/adb/tricky_store"
AUTOMATION_DIR="$SCRIPT_DIR/.automation"
LOG_DIR="/data/adb/Tricky-addon-enhanced/logs"
TARGET_FILE="$SCRIPT_DIR/target.txt"
DAEMON_PID="$AUTOMATION_DIR/daemon.pid"
UNINSTALL_LOG="$LOG_DIR/uninstall.log"

# Minimal logging for uninstall (logging.sh may not be available)
_uninstall_log() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
    msg="[$timestamp] [UNINSTALL] $1"
    echo "$msg" >> "$UNINSTALL_LOG" 2>/dev/null || echo "$msg" >&2
}

_uninstall_log "Uninstall started"

# Stop native supervisor — SIGTERM cascades to all children via signal handler
SUPERVISOR_PID="$AUTOMATION_DIR/supervisor.pid"
if [ -f "$SUPERVISOR_PID" ]; then
    sup_pid=$(cat "$SUPERVISOR_PID" 2>/dev/null)
    if [ -n "$sup_pid" ] && kill -0 "$sup_pid" 2>/dev/null; then
        kill "$sup_pid" 2>/dev/null && _uninstall_log "Stopped supervisor (pid=$sup_pid)"
        # Wait briefly for children to exit
        sleep 1
    fi
    rm -f "$SUPERVISOR_PID"
fi

# Fallback: kill by name if PID file was stale or missing
sup_pid=$(pidof supervisor 2>/dev/null)
if [ -n "$sup_pid" ]; then
    kill "$sup_pid" 2>/dev/null && _uninstall_log "Stopped supervisor via pidof fallback (pid=$sup_pid)"
fi

# Stop automation daemon if running (belt-and-suspenders)
if [ -f "$DAEMON_PID" ]; then
    pid=$(cat "$DAEMON_PID" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null && _uninstall_log "Stopped daemon (pid=$pid)"
    fi
    rm -f "$DAEMON_PID"
fi

# Enable back TSupport-A auto update
if [ -f "/storage/emulated/0/stop-tspa-auto-target" ]; then
    rm -f "/storage/emulated/0/stop-tspa-auto-target"
    _uninstall_log "Re-enabled TSupport-A auto update"
fi

# Remove module residue
_uninstall_log "Removing module files"
rm -rf "/data/adb/modules/.TA_utl" && _uninstall_log "Removed .TA_utl"
rm -f "/data/adb/boot_hash"
rm -f "/data/adb/tricky_store/security_patch_auto_config"
rm -f "/data/adb/tricky_store/target_from_denylist"
rm -f "/data/adb/tricky_store/system_app"
rm -f "/data/adb/tricky_store/enhanced.conf"

# Restore original module.prop description
if [ -f "$SCRIPT_DIR/.original_description" ] && [ -f "$TS/module.prop" ]; then
    orig=$(cat "$SCRIPT_DIR/.original_description" 2>/dev/null)
    if [ -n "$orig" ]; then
        sed -i "s|^description=.*|description=${orig}|" "$TS/module.prop" 2>/dev/null
        _uninstall_log "Restored original module.prop description"
    fi
fi

# Clean up symlinks
if [ -d "$TS" ]; then
    [ -L "$TS/webroot" ] && rm -f "$TS/webroot" && _uninstall_log "Removed webroot symlink"
    [ -L "$TS/action.sh" ] && rm -f "$TS/action.sh" && _uninstall_log "Removed action.sh symlink"
fi

# Clean up status files
rm -f "$SCRIPT_DIR/.health_state" && _uninstall_log "Removed health state"
rm -f "$SCRIPT_DIR/.original_description" && _uninstall_log "Removed description backup"
rm -f "$SCRIPT_DIR/.status_installed" "$SCRIPT_DIR/.status_targets" && _uninstall_log "Removed status temp files"

# Leave user's keybox untouched — don't overwrite with AOSP default
_uninstall_log "Keybox preserved (user-selected)"

_uninstall_log "Uninstall completed"

# Remove automation and log directories last
rm -rf "$AUTOMATION_DIR"
rm -rf "$LOG_DIR"
rmdir "/data/adb/Tricky-addon-enhanced" 2>/dev/null
