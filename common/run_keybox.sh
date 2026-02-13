#!/system/bin/sh
MODPATH=${0%/common/*}
. "$MODPATH/common/logging.sh"
log_init "KEYBOX" "main"
. "$MODPATH/common/utils.sh"
. "$MODPATH/common/keybox_manager.sh"

enabled=$(read_config keybox_enabled 1)
[ "$enabled" != "1" ] && exit $EXIT_UNINSTALL

log_info "Waiting for network before keybox fetch..."
boot_ok=0
if wait_for_network; then
    log_info "Network ready, starting aggressive keybox fetch"
    for attempt in $(seq 1 10); do
        if fetch_keybox; then
            log_info "Boot keybox fetch successful (attempt $attempt)"
            boot_ok=1
            break
        fi
        log_warn "Boot keybox attempt $attempt failed, retrying..."
        sleep 3
    done
    # Log if all boot attempts exhausted (BUG-K20)
    if [ "$boot_ok" = "0" ]; then
        log_error "All 10 boot keybox attempts failed"
    fi
else
    if [ -f "$TARGET_KEYBOX" ] && validate_keybox "$TARGET_KEYBOX"; then
        log_info "No network at boot, keeping existing keybox"
    else
        log_warn "No network and no keybox, trying bundled fallback"
        fetch_keybox || log_warn "Keybox fetch failed (no network)"
    fi
fi

# Validate interval: must be numeric and >= 60 (BUG-K22)
validate_interval() {
    _val="$1"
    case "$_val" in
        ''|*[!0-9]*) echo 300; return ;;
    esac
    if [ "$_val" -lt 60 ]; then
        echo 300
    else
        echo "$_val"
    fi
}

interval=$(validate_interval "$(read_config keybox_interval 300)")
while true; do
    sleep "$interval"
    is_uninstall_pending && exit $EXIT_UNINSTALL

    enabled=$(read_config keybox_enabled 1)
    [ "$enabled" != "1" ] && continue

    interval=$(validate_interval "$(read_config keybox_interval 300)")

    if fetch_keybox; then
        log_info "Keybox refresh successful"
    else
        log_warn "Keybox refresh failed"
    fi
done
