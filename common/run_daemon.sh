#!/system/bin/sh
MODPATH=${0%/common/*}
. "$MODPATH/common/logging.sh"
. "$MODPATH/common/utils.sh"
log_init "DAEMON" "main"

auto_enabled=$(read_config automation_target_enabled 1)
if [ "$auto_enabled" != "1" ]; then
    log_info "Target automation disabled by user config"
    exit 42
fi

exec sh "$MODPATH/common/automation.sh" --start-daemon
