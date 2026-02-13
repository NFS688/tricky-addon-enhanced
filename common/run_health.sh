#!/system/bin/sh
MODPATH=${0%/common/*}
. "$MODPATH/common/logging.sh"
log_init "HEALTH" "main"
. "$MODPATH/common/utils.sh"
EXIT_UNINSTALL=${EXIT_UNINSTALL:-42}
. "$MODPATH/common/health_check.sh"
monitor_tee_health
is_uninstall_pending && exit $EXIT_UNINSTALL
