#!/system/bin/sh
# Attestation engine fallback supervisor — restarts when internal loop dies

TS_MODULE="/data/adb/modules/tricky_store"
TS_DIR="/data/adb/tricky_store"
HEALTH_STATE="$TS_DIR/.health_state"
TA_MODULE="/data/adb/modules/TA_utl"
TA_HIDDEN="/data/adb/modules/.TA_utl"
POLL_INTERVAL=10
GRACE_PERIOD=5

# Requires: logging.sh (log_info, log_warn, log_fatal) and utils.sh (is_uninstall_pending)
# sourced by run_health.sh before this file

# Detect installed engine from daemon's --nice-name parameter
detect_engine() {
    if [ -f "$TS_MODULE/daemon" ]; then
        name=$(grep -o '\-\-nice-name=[^ ]*' "$TS_MODULE/daemon" 2>/dev/null | cut -d= -f2)
        [ -n "$name" ] && echo "$name" && return
    fi
    # Skip module.prop — human-readable name (e.g. "Tricky Store") breaks pidof
    echo "TEESimulator"
}

write_state() {
    cat > "$HEALTH_STATE" <<EOF
status=$1
pid=$2
restarts=${restarts:-0}
engine=${ENGINE_NAME}
last_check=$(date +%s 2>/dev/null || echo 0)
last_restart=${last_restart:-0}
EOF
}

MAX_RESTARTS=10
BACKOFF_INIT=20
BACKOFF_CAP=300

# Restart only the attestation engine, not the full tricky_store service.sh
restart_engine() {
    if [ -f "$TS_MODULE/service.sh" ]; then
        # Kill any stale engine process first
        old_pid=$(pidof "$ENGINE_NAME" 2>/dev/null)
        [ -n "$old_pid" ] && kill "$old_pid" 2>/dev/null
        sh "$TS_MODULE/service.sh" &
    fi
}

monitor_tee_health() {
    ENGINE_NAME=$(detect_engine)
    restarts=0
    last_restart=0
    was_dead=0
    backoff=$BACKOFF_INIT

    if [ -f "$HEALTH_STATE" ]; then
        restarts=$(grep "^restarts=" "$HEALTH_STATE" 2>/dev/null | cut -d= -f2)
        restarts=${restarts:-0}
        last_restart=$(grep "^last_restart=" "$HEALTH_STATE" 2>/dev/null | cut -d= -f2)
        last_restart=${last_restart:-0}
    fi

    log_info "$ENGINE_NAME monitor started (poll=${POLL_INTERVAL}s, grace=${GRACE_PERIOD}s, max_restarts=${MAX_RESTARTS})"

    while true; do
        sleep "$POLL_INTERVAL"

        [ -f "$TS_MODULE/disable" ] && continue
        [ ! -d "$TS_MODULE" ] && continue
        is_uninstall_pending && break

        tee_pid=$(pidof "$ENGINE_NAME" 2>/dev/null)

        if [ -n "$tee_pid" ]; then
            if [ "$was_dead" = "1" ]; then
                log_info "$ENGINE_NAME recovered (PID: $tee_pid)"
                was_dead=0
                # Reset circuit breaker on recovery so future failures get fresh budget
                restarts=0
                backoff=$BACKOFF_INIT
            fi
            write_state "running" "$tee_pid"
            continue
        fi

        if [ "$was_dead" = "0" ]; then
            log_warn "$ENGINE_NAME not running, grace period..."
            was_dead=1
            write_state "restarting" ""
            sleep "$GRACE_PERIOD"

            tee_pid=$(pidof "$ENGINE_NAME" 2>/dev/null)
            if [ -n "$tee_pid" ]; then
                log_info "$ENGINE_NAME internal loop recovered (PID: $tee_pid)"
                was_dead=0
                write_state "running" "$tee_pid"
                continue
            fi
        fi

        # Circuit breaker: stop after MAX_RESTARTS
        if [ "$restarts" -ge "$MAX_RESTARTS" ]; then
            log_fatal "$ENGINE_NAME failed after $MAX_RESTARTS restarts, giving up"
            write_state "failed" ""
            return 0
        fi

        restarts=$((restarts + 1))
        last_restart=$(date +%s 2>/dev/null || echo 0)
        log_warn "$ENGINE_NAME dead, restart $restarts/$MAX_RESTARTS (backoff=${backoff}s)"
        restart_engine
        write_state "restarted" ""

        # Exponential backoff: 20s, 40s, 80s, 160s, capped at 300s
        sleep "$backoff"
        backoff=$((backoff * 2))
        [ "$backoff" -gt "$BACKOFF_CAP" ] && backoff=$BACKOFF_CAP
    done
}
