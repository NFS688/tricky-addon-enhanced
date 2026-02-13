#!/system/bin/sh
MODPATH=${0%/common/*}
. "$MODPATH/common/logging.sh"
log_init "STATUS" "main"
. "$MODPATH/common/utils.sh"
EXIT_UNINSTALL=${EXIT_UNINSTALL:-42}
. "$MODPATH/common/status_monitor.sh"
monitor_status
is_uninstall_pending && exit $EXIT_UNINSTALL
