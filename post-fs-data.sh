MODPATH=${0%/*}
TS="/data/adb/modules/tricky_store"
LOG_BASE_DIR="/data/adb/Tricky-addon-enhanced/logs"
BOOT_LOG="$LOG_BASE_DIR/boot.log"

# Defensive logging - /data may not be decrypted yet
_pfd_log() {
    local timestamp msg
    timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
    msg="[$timestamp] [POST-FS-DATA] $1"

    # Try file logging first
    if [ -d "$LOG_BASE_DIR" ] && [ -w "$LOG_BASE_DIR" ]; then
        echo "$msg" >> "$BOOT_LOG" 2>/dev/null && return 0
    fi

    # Fallback to stderr (captured by logcat on some systems)
    echo "$msg" >&2
}

_pfd_log "post-fs-data started"

# Wait for modules directory to be populated (max ~15s)
_wait_count=0
while [ -z "$(ls -A /data/adb/modules/ 2>/dev/null)" ]; do
    _wait_count=$((_wait_count + 1))
    if [ "$_wait_count" -ge 30 ]; then
        _pfd_log "WARN: modules dir still empty after 30 iterations"
        break
    fi
    sleep 0.5
done
_pfd_log "Modules directory ready (waited ${_wait_count} iterations)"

# Self-remove if TrickyStore is missing or marked for removal
if [ ! -d "$TS" ] || [ -f "$TS/remove" ]; then
    _pfd_log "TrickyStore missing or removing - marking self for removal"
    if [ -f "$MODPATH/action.sh" ]; then
        rm -rf "/data/adb/modules/TA_utl" 2>/dev/null
        if ! mkdir -p "/data/adb/modules/TA_utl"; then
            _pfd_log "ERROR: Failed to create TA_utl stub for self-removal"
        fi
        if ! touch "/data/adb/modules/TA_utl/remove"; then
            _pfd_log "ERROR: Failed to mark TA_utl for removal"
        fi
    else
        touch "$MODPATH/remove"
    fi
fi

# Clean up stale symlinks
[ -L "$TS/webroot" ] && rm -f "$TS/webroot"
[ -L "$TS/action.sh" ] && rm -f "$TS/action.sh"

# Detect root manager (consistent with customize.sh: non-empty check)
if [ -n "$APATCH" ]; then
    MANAGER="APATCH"
elif [ -n "$KSU" ]; then
    MANAGER="KSU"
else
    MANAGER="MAGISK"
fi

if ! echo "MANAGER=$MANAGER" > "$MODPATH/common/manager.sh"; then
    _pfd_log "ERROR: Failed to write manager.sh"
fi
chmod 755 "$MODPATH/common/manager.sh"
_pfd_log "Root manager detected: $MANAGER"

_pfd_log "post-fs-data completed"
