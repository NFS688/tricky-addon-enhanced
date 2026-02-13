#!/bin/sh
# automation.sh - Core automation functions for target.txt management

TS_DIR="/data/adb/tricky_store"
AUTOMATION_DIR="$TS_DIR/.automation"
TARGET_FILE="$TS_DIR/target.txt"
EXCLUDE_FILE="$AUTOMATION_DIR/exclude_patterns.txt"
KNOWN_PACKAGES="$AUTOMATION_DIR/known_packages.txt"
DAEMON_PID="$AUTOMATION_DIR/daemon.pid"

MODPATH="${MODPATH:-${0%/*}/..}"
. "$MODPATH/common/logging.sh"

# Root manager packages — force-stop refreshes their cached listPackages() API
ROOT_MANAGERS="me.weishu.kernelsu com.rifsxd.ksunext com.sukisu.ultra \
com.topjohnwu.magisk io.github.vvb2060.magisk io.github.huskydg.magisk \
me.bmax.apatch me.garfieldhan.apatch.next com.android.patch \
com.dergoogler.mmrl com.dergoogler.mmrl.wx"

refresh_root_manager() {
    for pkg in $ROOT_MANAGERS; do
        am force-stop "$pkg" 2>/dev/null
    done
    log_info "Root manager cache invalidated"
}

ensure_dirs() {
    if ! mkdir -p "$AUTOMATION_DIR" 2>/dev/null; then
        log_warn "Failed to create automation directory"
    fi
}

is_excluded() {
    package="$1"
    [ -f "$EXCLUDE_FILE" ] && grep -qxF "$package" "$EXCLUDE_FILE"
}

is_xposed_module() {
    package="$1"
    apk_path=$(pm path "$package" 2>/dev/null | head -n1 | cut -d: -f2)
    if [ -z "$apk_path" ]; then
        log_debug "Cannot get APK path for: $package"
        return 1
    fi

    # Primary check: assets/xposed_init
    if unzip -l "$apk_path" 2>/dev/null | grep -q "assets/xposed_init"; then
        return 0
    fi

    # Backup check: xposedmodule in manifest
    if unzip -p "$apk_path" AndroidManifest.xml 2>/dev/null | tr -d '\0' | grep -q "xposedmodule"; then
        return 0
    fi

    return 1
}

add_to_target() {
    package="$1"
    if grep -qxF "$package" "$TARGET_FILE" 2>/dev/null; then
        return 0
    fi

    if ! echo "$package" >> "$TARGET_FILE"; then
        log_error "Failed to add $package to target.txt"
        return 1
    fi
    log_info "Added: $package"
}

cleanup_dead_apps() {
    [ ! -f "$TARGET_FILE" ] && return 0

    installed=$(pm list packages 2>/dev/null | cut -d: -f2)
    [ -z "$installed" ] && return 1

    tmp_target="$TS_DIR/.target_clean"
    removed=0

    # Clean up temp file on interrupt
    trap 'rm -f "$tmp_target"' INT TERM HUP
    rm -f "$tmp_target"

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        pkg=$(echo "$line" | sed 's/[!?]$//')
        if echo "$installed" | grep -qxF "$pkg"; then
            echo "$line" >> "$tmp_target"
        else
            log_info "Removed (uninstalled): $pkg"
            removed=$((removed + 1))
        fi
    done < "$TARGET_FILE"

    if [ "$removed" -gt 0 ]; then
        mv "$tmp_target" "$TARGET_FILE"
        log_info "Cleaned $removed dead entries"
    else
        rm -f "$tmp_target"
    fi

    # Restore default trap
    trap - INT TERM HUP
}

get_packages_hash() {
    pm list packages -3 2>/dev/null | sort | md5sum | cut -d' ' -f1
}

check_new_packages() {
    current_packages=$(pm list packages -3 2>/dev/null | sed 's/^package://' | sort)

    if [ ! -f "$KNOWN_PACKAGES" ]; then
        if ! echo "$current_packages" > "$KNOWN_PACKAGES"; then
            log_error "Failed to initialize known_packages.txt"
        fi
        return 0
    fi

    new_packages=$(echo "$current_packages" | grep -vxF -f "$KNOWN_PACKAGES" 2>/dev/null)

    if [ -n "$new_packages" ]; then
        target_hash=$(md5sum "$TARGET_FILE" 2>/dev/null | cut -d' ' -f1)

        # Note: pipe runs while-loop in subshell — add_to_target writes to
        # TARGET_FILE directly (not via variable), so this pattern works.
        echo "$new_packages" | while read -r pkg; do
            [ -z "$pkg" ] && continue
            if is_excluded "$pkg"; then
                log_info "Skipped (excluded): $pkg"
            elif is_xposed_module "$pkg"; then
                log_info "Skipped (Xposed module): $pkg"
            else
                add_to_target "$pkg"
            fi
        done

        new_hash=$(md5sum "$TARGET_FILE" 2>/dev/null | cut -d' ' -f1)
        [ "$target_hash" != "$new_hash" ] && refresh_root_manager
    fi

    if ! echo "$current_packages" > "$KNOWN_PACKAGES"; then
        log_warn "Failed to update known_packages.txt"
    fi

    cleanup_dead_apps
}

start_daemon() {
    ensure_dirs
    log_init "WATCHER" "main"

    if [ -f "$DAEMON_PID" ]; then
        pid=$(cat "$DAEMON_PID" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            log_info "Daemon already running (PID: $pid)"
            return 0
        fi
        # Stale PID file — previous instance died
        rm -f "$DAEMON_PID"
    fi

    log_info "Daemon starting"
    # Atomic PID write: temp file + mv to prevent TOCTOU
    pid_tmp="${DAEMON_PID}.$$"
    if ! echo $$ > "$pid_tmp"; then
        log_error "Failed to write daemon PID file"
        rm -f "$pid_tmp"
        return 1
    fi
    mv "$pid_tmp" "$DAEMON_PID"

    trap 'rm -f "$DAEMON_PID" "$AUTOMATION_DIR/inotify_handler.sh"; log_info "Daemon stopped"; exit 0' INT TERM EXIT

    if command -v inotifywait >/dev/null 2>&1; then
        log_info "Using inotifywait for instant detection"
        while true; do
            if ! inotifywait -r -q -e create -e moved_to /data/app 2>/dev/null; then
                log_warn "inotifywait error, falling back to sleep"
                sleep 10
            fi
            sleep 3
            check_new_packages
        done
    else
        log_info "Using polling (10s interval)"
        while true; do
            sleep 10
            check_new_packages
        done
    fi
}

stop_daemon() {
    if [ -f "$DAEMON_PID" ]; then
        pid=$(cat "$DAEMON_PID" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            if kill "$pid" 2>/dev/null; then
                log_info "Daemon stopped by request"
                rm -f "$DAEMON_PID"
            else
                log_warn "Failed to kill daemon (PID: $pid), PID file retained"
            fi
        else
            # PID not alive — stale file
            rm -f "$DAEMON_PID"
        fi
    else
        log_debug "No daemon PID file found"
    fi
}

show_status() {
    echo "=== Tricky Addon - Automation Status ==="
    echo ""

    if [ -f "$TARGET_FILE" ]; then
        count=$(wc -l < "$TARGET_FILE" 2>/dev/null || echo 0)
        echo "target.txt: $count apps"
    else
        echo "target.txt: NOT FOUND"
    fi

    if [ -f "$DAEMON_PID" ]; then
        pid=$(cat "$DAEMON_PID" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "Daemon: RUNNING (PID: $pid)"
        else
            echo "Daemon: STOPPED (stale PID file)"
        fi
    else
        echo "Daemon: STOPPED"
    fi

    install_log="/data/adb/Tricky-addon-enhanced/logs/install.log"
    boot_log="/data/adb/Tricky-addon-enhanced/logs/boot.log"
    watcher_log="/data/adb/Tricky-addon-enhanced/logs/watcher.log"

    if [ -f "$install_log" ]; then
        last_install=$(tail -1 "$install_log" 2>/dev/null | cut -d']' -f1 | tr -d '[')
        echo "Last install: $last_install"
    else
        echo "Last install: N/A"
    fi

    if [ -f "$boot_log" ]; then
        last_boot=$(tail -1 "$boot_log" 2>/dev/null | cut -d']' -f1 | tr -d '[')
        echo "Last boot: $last_boot"
    else
        echo "Last boot: N/A"
    fi

    if [ -f "$watcher_log" ]; then
        last_activity=$(tail -1 "$watcher_log" 2>/dev/null | cut -d']' -f1 | tr -d '[')
        echo "Last activity: $last_activity"
    else
        echo "Last activity: N/A"
    fi

    echo ""
}

# Command line interface
case "$1" in
    --start-daemon)
        start_daemon
        ;;
    --stop-daemon)
        stop_daemon
        ;;
    --check-packages)
        check_new_packages
        ;;
    --status)
        show_status
        ;;
    *)
        echo "Usage: $0 {--start-daemon|--stop-daemon|--check-packages|--status}"
        exit 1
        ;;
esac
