#!/system/bin/sh
MODPATH=${0%/common/*}
. "$MODPATH/common/logging.sh"
log_init "SECPATCH" "main"
. "$MODPATH/common/utils.sh"
. "$MODPATH/common/security_patch_manager.sh"

enabled=$(read_config security_patch_auto 1)
[ "$enabled" != "1" ] && exit $EXIT_UNINSTALL

log_info "Waiting for network before security patch fetch..."
if wait_for_network; then
    log_info "Network ready, starting aggressive security patch fetch"
    for attempt in $(seq 1 10); do
        if auto_update_security_patch; then
            log_info "Boot security patch fetch successful (attempt $attempt)"
            break
        fi
        log_warn "Boot security patch attempt $attempt failed, retrying..."
        sleep 3
    done
else
    log_warn "Network not available, trying security patch fetch anyway"
    auto_update_security_patch || log_warn "Security patch fetch failed (no network)"
fi

interval=$(read_config security_patch_interval 86400)
while true; do
    sleep "$interval"
    is_uninstall_pending && exit $EXIT_UNINSTALL

    enabled=$(read_config security_patch_auto 1)
    [ "$enabled" != "1" ] && continue

    interval=$(read_config security_patch_interval 86400)

    if auto_update_security_patch; then
        log_info "Security patch auto-update successful"
    else
        log_warn "Security patch auto-update failed"
    fi
done
