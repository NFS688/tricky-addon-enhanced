#!/system/bin/sh

TS_DIR="/data/adb/tricky_store"
TA_MODULE="/data/adb/modules/TA_utl"
TA_HIDDEN="/data/adb/modules/.TA_utl"
EXIT_UNINSTALL=42

is_uninstall_pending() {
    [ -f "$TA_MODULE/remove" ] || [ -f "$TA_HIDDEN/remove" ]
}

read_config() {
    key="$1"
    default="$2"
    if [ -f "$TS_DIR/enhanced.conf" ]; then
        value=$(grep "^${key}=" "$TS_DIR/enhanced.conf" 2>/dev/null | cut -d'=' -f2- | tr -d ' ')
        [ -n "$value" ] && echo "$value" && return 0
    fi
    echo "$default"
}

check_network() {
    ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 || ping -c1 -W2 8.8.8.8 >/dev/null 2>&1
}

wait_for_network() {
    for i in $(seq 1 30); do
        check_network && return 0
        sleep 2
    done
    return 1
}
