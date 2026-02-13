#!/bin/sh
# Module conflict detection for Tricky Addon Enhanced

MODULESDIR="/data/adb/modules"
TS_DIR="/data/adb/tricky_store"
AUTOMATION_DIR="$TS_DIR/.automation"
CONFLICT_LOG="/data/adb/Tricky-addon-enhanced/logs/conflict.log"

# Hardcoded list — must be updated manually when new conflicting modules appear.
# No capability-based detection; module renames evade this check.
CONFLICT_MODULES="Yurikey xiaocaiye safetynet-fix vbmeta-fixer playintegrity integrity_box SukiSU_module Reset_BootHash Tricky_store-bm Hide_Bootloader ShamikoManager extreme_hide_root Tricky_Store-xiaoyi tricky_store_assistant extreme_hide_bootloader wjw_hiderootauxiliarymod"
AGGRESSIVE_MODULES="Yamabukiko"
CONFLICT_APPS="com.lingqian.appbl com.topmiaohan.hidebllist"

MODPATH="${MODPATH:-${0%/*}/..}"
. "$MODPATH/common/logging.sh"
log_init "CONFLICT" "boot"

log_to_conflict_file() {
    if ! mkdir -p "$(dirname "$CONFLICT_LOG")" 2>/dev/null; then
        log_warn "Failed to create log directory for conflict log"
    fi
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [CONFLICT] $1" >> "$CONFLICT_LOG" 2>/dev/null || log_warn "Failed to write to conflict.log"
}

detect_boot_manager() {
    if [ -f "/data/adb/ap/modules.img" ] || [ -f "/data/adb/ksu/modules.img" ]; then
        echo "OverlayFS"
    else
        echo "MagicMount"
    fi
}

tag_module_for_removal() {
    module="$1"
    module_path="$MODULESDIR/$module"
    if [ ! -d "$module_path" ]; then
        log_debug "Module not found for tagging: $module"
        return 1
    fi

    if ! touch "$module_path/disable" 2>/dev/null; then
        log_warn "Failed to create disable marker for: $module"
    fi
    if ! touch "$module_path/remove" 2>/dev/null; then
        log_warn "Failed to create remove marker for: $module"
    fi
    log_info "Tagged for removal: $module"
    log_to_conflict_file "Tagged for removal: $module"
    return 0
}

check_module_conflicts() {
    found_regular=0
    found_aggressive=0

    for module in $AGGRESSIVE_MODULES; do
        if [ -d "$MODULESDIR/$module" ]; then
            log_error "AGGRESSIVE: $module found - install must abort"
            log_to_conflict_file "AGGRESSIVE: $module found - install must abort"
            found_aggressive=1
        fi
    done

    if [ "$found_aggressive" = "1" ]; then
        return 1
    fi

    for module in $CONFLICT_MODULES; do
        if [ -d "$MODULESDIR/$module" ]; then
            tag_module_for_removal "$module"
            found_regular=1
        fi
    done

    if [ "$found_regular" = "1" ]; then
        log_info "Regular conflicts tagged for removal"
        log_to_conflict_file "Regular conflicts tagged for removal"
    fi
    return 0
}

check_app_conflicts() {
    for pkg in $CONFLICT_APPS; do
        if pm path "$pkg" >/dev/null 2>&1; then
            log_warn "Conflicting app installed: $pkg"
            log_to_conflict_file "WARNING: Conflicting app installed: $pkg"
        fi
    done
}

check_all_conflicts() {
    log_info "Conflict check started"
    log_to_conflict_file "=== Conflict check started ==="
    boot_mgr=$(detect_boot_manager)
    log_info "Boot manager: $boot_mgr"
    log_to_conflict_file "Boot manager: $boot_mgr"

    if ! check_module_conflicts; then
        log_error "ABORT: Aggressive conflict detected"
        log_to_conflict_file "ABORT: Aggressive conflict detected"
        return 1
    fi

    check_app_conflicts
    log_info "Conflict check completed"
    log_to_conflict_file "=== Conflict check completed ==="
    return 0
}

case "$1" in
    --check)
        check_all_conflicts
        exit $?
        ;;
    --status)
        cat "$CONFLICT_LOG" 2>/dev/null
        ;;
esac
