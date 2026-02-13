#!/bin/sh
# WebUI CLI backend - all silent failures logged

MODPATH=${0%/*}
SKIPLIST="$MODPATH/tmp/skiplist"
XPOSED="$MODPATH/tmp/xposed"
PATH=$MODPATH/bin:$PATH

if [ "$MODPATH" = "/data/adb/modules/.TA_utl/common" ]; then
    MODDIR="/data/adb/modules/.TA_utl"
    MAGISK="true"
else
    MODDIR="/data/adb/modules/TA_utl"
fi

TS_DIR="/data/adb/tricky_store"
AUTOMATION_DIR="$TS_DIR/.automation"
LOG_DIR="/data/adb/Tricky-addon-enhanced/logs"
WEBUI_LOG="$LOG_DIR/webui.log"

# Dual-output logging: file + stderr for WebUI capture
_log() {
    local level="$1" msg="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
    local formatted="[$timestamp] [WEBUI] [$level] $msg"

    [ -d "$LOG_DIR" ] && echo "$formatted" >> "$WEBUI_LOG" 2>/dev/null
    [ "$level" = "ERROR" ] && echo "$formatted" >&2
}

_log_info() { _log "INFO" "$1"; }
_log_error() { _log "ERROR" "$1"; }

# Source canonical read_config() from utils.sh (avoids duplicate definitions)
. "$MODPATH/utils.sh"

download() {
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl --connect-timeout 10 -Ls "$url"
    else
        busybox wget -T 10 -qO- "$url"
    fi
}

get_xposed() {
    mkdir -p "$MODPATH/tmp"
    touch "$XPOSED" "$SKIPLIST"
    pm list packages -3 2>/dev/null | cut -d':' -f2 | grep -vxF -f "$SKIPLIST" | grep -vxF -f "$XPOSED" | while read -r PACKAGE; do
        APK_PATH=$(pm path "$PACKAGE" 2>/dev/null | head -n1 | cut -d: -f2)
        if [ -z "$APK_PATH" ]; then
            _log_info "get_xposed: no APK path for $PACKAGE"
            continue
        fi
        if unzip -p "$APK_PATH" AndroidManifest.xml 2>/dev/null | tr -d '\0' | grep -q "xposedmodule"; then
            echo "$PACKAGE" >> "$XPOSED"
        else
            echo "$PACKAGE" >> "$SKIPLIST"
        fi
    done
    cat "$XPOSED"
}

get_applist() {
    pm list packages -3 2>/dev/null | awk -F: '{print $2}'
    if [ -s "/data/adb/tricky_store/system_app" ]; then
        pm list packages -s 2>/dev/null | awk -F: '{print $2}' | grep -Fxf "/data/adb/tricky_store/system_app" || true
    fi
}

get_appname() {
    base_apk=$(pm path "$package_name" 2>/dev/null | head -n1 | awk -F: '{print $2}')
    if [ -z "$base_apk" ]; then
        _log_error "get_appname: no APK path for $package_name"
        echo "$package_name"
        return 1
    fi
    app_name=$(aapt dump badging "$base_apk" 2>/dev/null | grep "application-label:" | sed "s/application-label://; s/'//g")
    if [ -z "$app_name" ]; then
        _log_info "get_appname: aapt failed for $package_name, using package name"
        app_name="$package_name"
    fi
    echo "$app_name"
}

check_update() {
    LOCAL_VERSION=$(grep '^versionCode=' "$MODPATH/update/module.prop" 2>/dev/null | awk -F= '{print $2}')
    if [ -z "$LOCAL_VERSION" ]; then
        _log_error "check_update: cannot read local version"
        return 1
    fi
    if [ "$REMOTE_VERSION" -gt "$LOCAL_VERSION" ] 2>/dev/null && [ ! -f "/data/adb/modules/TA_utl/update" ]; then
        _log_info "check_update: update available ($LOCAL_VERSION -> $REMOTE_VERSION)"
        if [ "$CANARY" = "true" ]; then
            exit 1
        elif [ "$MAGISK" = "true" ]; then
            [ -d "/data/adb/modules/TA_utl" ] && rm -rf "/data/adb/modules/TA_utl"
            cp -rf "$MODPATH/update" "/data/adb/modules/TA_utl"
        else
            cp -f "$MODPATH/update/module.prop" "/data/adb/modules/TA_utl/module.prop"
        fi
        echo "update"
    fi
}

update_locales() {
    local link1="https://raw.githubusercontent.com/KOWX712/Tricky-Addon-Update-Target-List/bot/locales.zip"
    local link2="https://raw.gitmirror.com/KOWX712/Tricky-Addon-Update-Target-List/bot/locales.zip"
    local error=0

    _log_info "update_locales: fetching locale pack"
    download "$link1" > "$MODPATH/tmp/locales.zip" || download "$link2" > "$MODPATH/tmp/locales.zip"

    if [ ! -s "$MODPATH/tmp/locales.zip" ]; then
        _log_error "update_locales: download failed (both mirrors)"
        error=1
    fi

    if ! unzip -o "$MODPATH/tmp/locales.zip" -d "$MODDIR/webui/locales" 2>/dev/null; then
        _log_error "update_locales: unzip failed to $MODDIR/webui/locales"
        error=1
    fi

    if [ -d "/data/adb/modules_update/TA_utl" ]; then
        if ! unzip -o "$MODPATH/tmp/locales.zip" -d "/data/adb/modules_update/TA_utl/webui/locales" 2>/dev/null; then
            _log_error "update_locales: unzip failed to modules_update"
            error=1
        fi
    fi

    rm -f "$MODPATH/tmp/locales.zip"
    [ "$error" -eq 0 ] || exit 1
}

uninstall() {
    if [ ! -f "$MODPATH/manager.sh" ]; then
        _log_error "uninstall: manager.sh not found"
        exit 1
    fi
    . "$MODPATH/manager.sh"
    _log_info "uninstall: using manager=$MANAGER"

    case $MANAGER in
        APATCH)
            cp -f "$MODPATH/update/module.prop" "$MODDIR/module.prop"
            if ! apd module uninstall TA_utl 2>/dev/null; then
                _log_error "uninstall: apd uninstall failed"
            fi
            # Signal supervisors to stop before reboot
            touch "/data/adb/modules/TA_utl/remove" 2>/dev/null
            touch "/data/adb/modules/.TA_utl/remove" 2>/dev/null
            ;;
        KSU)
            cp -f "$MODPATH/update/module.prop" "$MODDIR/module.prop"
            if ! ksud module uninstall TA_utl 2>/dev/null; then
                _log_error "uninstall: ksud uninstall failed"
            fi
            # Signal supervisors to stop before reboot
            touch "/data/adb/modules/TA_utl/remove" 2>/dev/null
            touch "/data/adb/modules/.TA_utl/remove" 2>/dev/null
            ;;
        MAGISK)
            cp -rf "$MODPATH/update" "/data/adb/modules/TA_utl"
            if ! magisk --remove-module -n TA_utl 2>/dev/null; then
                _log_error "uninstall: magisk remove failed"
                touch "/data/adb/modules/TA_utl/remove"
            fi
            ;;
        *)
            _log_error "uninstall: unknown manager '$MANAGER'"
            touch "/data/adb/modules/TA_utl/remove"
            exit 1
            ;;
    esac
}

get_update() {
    _log_info "get_update: downloading from $ZIP_URL"
    download "$ZIP_URL" > "$MODPATH/tmp/module.zip"
    if [ ! -s "$MODPATH/tmp/module.zip" ]; then
        _log_error "get_update: download failed or empty"
        exit 1
    fi
}

install_update() {
    local zip_file="$MODPATH/tmp/module.zip"

    if [ ! -f "$MODPATH/manager.sh" ]; then
        _log_error "install_update: manager.sh not found"
        exit 1
    fi
    . "$MODPATH/manager.sh"
    _log_info "install_update: using manager=$MANAGER"

    case $MANAGER in
        APATCH)
            if ! apd module install "$zip_file" 2>/dev/null; then
                _log_error "install_update: apd install failed"
                exit 1
            fi
            ;;
        KSU)
            if ! ksud module install "$zip_file" 2>/dev/null; then
                _log_error "install_update: ksud install failed"
                exit 1
            fi
            ;;
        MAGISK)
            if ! magisk --install-module "$zip_file" 2>/dev/null; then
                _log_error "install_update: magisk install failed"
                exit 1
            fi
            ;;
        *)
            _log_error "install_update: unknown manager '$MANAGER'"
            rm -f "$zip_file" "$MODPATH/tmp/changelog.md" "$MODPATH/tmp/version" 2>/dev/null
            exit 1
            ;;
    esac

    update_locales || true
    rm -f "$zip_file" "$MODPATH/tmp/changelog.md" "$MODPATH/tmp/version" 2>/dev/null
}

release_note() {
    awk -v header="### $VERSION" '
        $0 == header {
            print;
            found = 1;
            next
        }
        found && /^###/ { exit }
        found { print }
    ' "$MODPATH/tmp/changelog.md"
}

set_security_patch() {
    local PIF=""
    local security_patch=""

    if [ -f "/data/adb/modules/playintegrityfix/pif.json" ]; then
        PIF="/data/adb/modules/playintegrityfix/pif.json"
        [ -f "/data/adb/pif.json" ] && PIF="/data/adb/pif.json"
    elif [ -f "/data/adb/modules/playintegrityfix/pif.prop" ]; then
        PIF="/data/adb/modules/playintegrityfix/pif.prop"
        [ -f "/data/adb/pif.prop" ] && PIF="/data/adb/pif.prop"
    elif [ -f "/data/adb/modules/playintegrityfix/custom.pif.json" ]; then
        PIF="/data/adb/modules/playintegrityfix/custom.pif.json"
    elif [ -f "/data/adb/modules/playintegrityfix/custom.pif.prop" ]; then
        PIF="/data/adb/modules/playintegrityfix/custom.pif.prop"
    fi

    if [ -n "$PIF" ]; then
        _log_info "set_security_patch: using PIF from $PIF"
        if echo "$PIF" | grep -q "prop"; then
            security_patch=$(grep 'SECURITY_PATCH' "$PIF" 2>/dev/null | cut -d'=' -f2 | tr -d '\n')
        else
            security_patch=$(grep '"SECURITY_PATCH"' "$PIF" 2>/dev/null | sed 's/.*: "//; s/".*//')
        fi
    fi

    if [ -z "$security_patch" ]; then
        security_patch=$(getprop ro.build.version.security_patch)
        _log_info "set_security_patch: using system patch $security_patch"
    fi

    local formatted_security_patch
    formatted_security_patch=$(echo "$security_patch" | sed 's/-//g')
    local security_patch_after_1y=$((formatted_security_patch + 10000))
    local TODAY
    TODAY=$(date +%Y%m%d)

    if [ -z "$formatted_security_patch" ]; then
        _log_error "set_security_patch: no valid security patch found"
        echo "not set"
        return 1
    fi

    if [ "$TODAY" -ge "$security_patch_after_1y" ] 2>/dev/null; then
        _log_error "set_security_patch: patch $security_patch is over 1 year old"
        echo "not set"
        return 1
    fi

    local TS_version
    TS_version=$(grep "versionCode=" "/data/adb/modules/tricky_store/module.prop" 2>/dev/null | cut -d'=' -f2)

    if grep -q "James" "/data/adb/modules/tricky_store/module.prop" 2>/dev/null && ! grep -q "beakthoven" "/data/adb/modules/tricky_store/module.prop" 2>/dev/null; then
        local SECURITY_PATCH_FILE="/data/adb/tricky_store/devconfig.toml"
        _log_info "set_security_patch: James fork detected, using $SECURITY_PATCH_FILE"
        if grep -q "^securityPatch" "$SECURITY_PATCH_FILE" 2>/dev/null; then
            sed -i "s/^securityPatch .*/securityPatch = \"$security_patch\"/" "$SECURITY_PATCH_FILE"
        else
            if ! grep -q "^\\[deviceProps\\]" "$SECURITY_PATCH_FILE" 2>/dev/null; then
                echo "securityPatch = \"$security_patch\"" >> "$SECURITY_PATCH_FILE"
            else
                sed -i "s/^\[deviceProps\]/securityPatch = \"$security_patch\"\n&/" "$SECURITY_PATCH_FILE"
            fi
        fi
    elif grep -q "TEESimulator" "/data/adb/modules/tricky_store/module.prop" 2>/dev/null || [ "$TS_version" -ge 158 ] 2>/dev/null || grep -q "beakthoven" "/data/adb/modules/tricky_store/module.prop" 2>/dev/null; then
        local SECURITY_PATCH_FILE="/data/adb/tricky_store/security_patch.txt"
        _log_info "set_security_patch: using $SECURITY_PATCH_FILE"
        printf "system=prop\nboot=%s\nvendor=%s\n" "$security_patch" "$security_patch" > "$SECURITY_PATCH_FILE"
        chmod 644 "$SECURITY_PATCH_FILE"
    else
        _log_info "set_security_patch: legacy mode, using resetprop"
        resetprop ro.vendor.build.security_patch "$security_patch" 2>/dev/null
        resetprop ro.build.version.security_patch "$security_patch" 2>/dev/null
    fi
}

get_latest_security_patch() {
    _log_info "get_latest_security_patch: fetching from source.android.com"
    local security_patch
    security_patch=$(download "https://source.android.com/docs/security/bulletin/pixel" |
                     sed -n 's/.*<td>\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)<\/td>.*/\1/p' |
                     head -n 1)

    if [ -n "$security_patch" ]; then
        echo "$security_patch"
        exit 0
    fi

    if ! ping -c 1 -W 5 "source.android.com" >/dev/null 2>&1; then
        _log_error "get_latest_security_patch: connection failed"
        echo "Connection failed" >&2
    else
        _log_error "get_latest_security_patch: parse failed"
    fi
    exit 1
}

valid_kb() {
    local LINK1="https://raw.githubusercontent.com/KOWX712/Tricky-Addon-Update-Target-List/main/.extra"
    local LINK2="https://raw.gitmirror.com/KOWX712/Tricky-Addon-Update-Target-List/main/.extra"

    _log_info "valid_kb: fetching keybox"
    local HEX
    HEX=$(download "$LINK1") || HEX=$(download "$LINK2")

    if [ -z "$HEX" ]; then
        _log_error "valid_kb: download failed (both mirrors)"
        exit 1
    fi

    local KEYBOX
    KEYBOX=$(echo "$HEX" | xxd -r -p | busybox base64 -d 2>/dev/null)

    if [ -z "$KEYBOX" ]; then
        _log_error "valid_kb: decode failed"
        exit 1
    fi

    # Validate before backup — don't clobber good keybox with corrupt data
    case "$KEYBOX" in
        *"<AndroidAttestation>"*"BEGIN CERTIFICATE"*)
            ;;
        *)
            _log_error "valid_kb: decoded keybox failed structural validation"
            exit 1
            ;;
    esac

    mv -f /data/adb/tricky_store/keybox.xml /data/adb/tricky_store/keybox.xml.bak 2>/dev/null
    if ! printf '%s\n' "$KEYBOX" > /data/adb/tricky_store/keybox.xml; then
        _log_error "valid_kb: write failed"
        # Restore backup on write failure
        mv -f /data/adb/tricky_store/keybox.xml.bak /data/adb/tricky_store/keybox.xml 2>/dev/null
        exit 1
    fi
    chmod 644 /data/adb/tricky_store/keybox.xml
    _log_info "valid_kb: keybox installed"
}

unknown_kb() {
    local ECKEY="eckey.pem"
    local CERT="cert.pem"
    local RSAKEY="rsakey.pem"
    local KEYBOX="keybox.xml"

    _log_info "unknown_kb: generating new keybox"

    if ! keygen gen_ec_key > "$ECKEY" 2>/dev/null; then
        _log_error "unknown_kb: gen_ec_key failed"
        exit 1
    fi

    if ! keygen gen_cert "$ECKEY" > "$CERT" 2>/dev/null; then
        _log_error "unknown_kb: gen_cert failed"
        rm -f "$ECKEY"
        exit 1
    fi

    if ! keygen gen_rsa_key > "$RSAKEY" 2>/dev/null; then
        _log_error "unknown_kb: gen_rsa_key failed"
        rm -f "$ECKEY" "$CERT"
        exit 1
    fi

    cat << KEYBOX_EOF > "$KEYBOX"
<?xml version="1.0"?>
    <AndroidAttestation>
        <NumberOfKeyboxes>1</NumberOfKeyboxes>
        <Keybox DeviceID="sw">
            <Key algorithm="ecdsa">
                <PrivateKey format="pem">
$(sed 's/^/                    /' "$ECKEY")
                </PrivateKey>
                <CertificateChain>
                    <NumberOfCertificates>1</NumberOfCertificates>
                        <Certificate format="pem">
$(sed 's/^/                        /' "$CERT")
                        </Certificate>
                </CertificateChain>
            </Key>
            <Key algorithm="rsa">
                <PrivateKey format="pem">
$(sed 's/^/                    /' "$RSAKEY")
                </PrivateKey>
            </Key>
        </Keybox>
</AndroidAttestation>
KEYBOX_EOF

    rm -f "$ECKEY" "$CERT" "$RSAKEY"

    if [ ! -f "$KEYBOX" ]; then
        _log_error "unknown_kb: keybox generation failed"
        exit 1
    fi

    mv /data/adb/tricky_store/keybox.xml /data/adb/tricky_store/keybox.xml.bak 2>/dev/null
    if ! mv "$KEYBOX" /data/adb/tricky_store/keybox.xml; then
        _log_error "unknown_kb: Failed to install generated keybox"
        exit 1
    fi
    _log_info "unknown_kb: keybox generated and installed"
}

case "$1" in
--download)
    shift
    download "$@"
    exit
    ;;
--xposed)
    get_xposed
    exit
    ;;
--applist)
    get_applist
    exit
    ;;
--appname)
    package_name="$2"
    get_appname
    exit
    ;;
--check-update)
    REMOTE_VERSION="$2"
    check_update
    exit
    ;;
--update-locales)
    update_locales
    exit
    ;;
--uninstall)
    uninstall
    exit
    ;;
--get-update)
    ZIP_URL="$2"
    get_update
    exit
    ;;
--install-update)
    install_update
    exit
    ;;
--release-note)
    VERSION="$2"
    release_note
    exit
    ;;
--security-patch)
    set_security_patch
    exit
    ;;
--get-security-patch)
    get_latest_security_patch
    exit
    ;;
--unknown-kb)
    unknown_kb
    exit
    ;;
--valid-kb)
    valid_kb
    exit
    ;;
--get-config)
    if [ ! -f "/data/adb/tricky_store/enhanced.conf" ]; then
        _log_error "--get-config: enhanced.conf not found"
        exit 1
    fi
    cat "/data/adb/tricky_store/enhanced.conf"
    exit
    ;;
--set-config)
    key="$2"
    value="$3"
    case "$key" in
        *[!a-zA-Z0-9_]*)
            _log_error "--set-config: invalid key '$key'"
            exit 1
            ;;
    esac
    if [ ! -f "/data/adb/tricky_store/enhanced.conf" ]; then
        _log_error "--set-config: enhanced.conf not found"
        exit 1
    fi
    # Reject values containing newlines or carriage returns
    case "$value" in
        *"$(printf '\n')"*|*"$(printf '\r')"*)
            _log_error "--set-config: value contains newline for key=$key"
            exit 1
            ;;
    esac
    escaped_value=$(printf '%s\n' "$value" | sed 's/[&/\]/\\&/g')
    if ! sed -i "s/^${key}=.*/${key}=${escaped_value}/" "/data/adb/tricky_store/enhanced.conf" 2>/dev/null; then
        _log_error "--set-config: sed failed for key=$key"
        exit 1
    fi
    _log_info "--set-config: $key=$value"
    exit
    ;;
--set-custom-keybox)
    if ! sed -i 's/^keybox_source=.*/keybox_source=custom/' "/data/adb/tricky_store/enhanced.conf" 2>/dev/null; then
        _log_error "--set-custom-keybox: failed to update config"
        exit 1
    fi
    _log_info "--set-custom-keybox: source set to custom"
    exit
    ;;
--fetch-keybox-now)
    if [ ! -f "$MODPATH/keybox_manager.sh" ]; then
        _log_error "--fetch-keybox-now: keybox_manager.sh not found"
        exit 1
    fi
    # Manager scripts expect MODPATH=module root for sourcing common/*.sh
    MODPATH="$MODDIR"
    . "$MODPATH/common/logging.sh"
    log_init "KEYBOX" "main"
    . "$MODPATH/common/keybox_manager.sh"
    fetch_keybox
    exit $?
    ;;
--set-security-patch-now)
    if [ ! -f "$MODDIR/common/security_patch_manager.sh" ]; then
        _log_error "--set-security-patch-now: security_patch_manager.sh not found"
        exit 1
    fi
    MODPATH="$MODDIR"
    . "$MODPATH/common/security_patch_manager.sh"
    set_security_patch
    exit $?
    ;;
--check-conflicts)
    if [ ! -f "$MODDIR/common/conflict_manager.sh" ]; then
        _log_error "--check-conflicts: conflict_manager.sh not found"
        exit 1
    fi
    MODPATH="$MODDIR"
    . "$MODPATH/common/conflict_manager.sh"
    check_all_conflicts
    exit $?
    ;;
--get-conflict-status)
    if [ ! -f "$LOG_DIR/conflict.log" ]; then
        _log_info "--get-conflict-status: no conflict log"
        echo "No conflict log found"
    else
        cat "$LOG_DIR/conflict.log"
    fi
    exit
    ;;
--get-keybox-sources)
    echo "Available sources: yurikey, upstream, integritybox, custom"
    echo "Current: $(read_config keybox_source yurikey)"
    echo "Fallback enabled: $(read_config keybox_fallback_enabled 1)"
    exit
    ;;
--tee-status)
    state_file="/data/adb/tricky_store/.health_state"
    ts_module="/data/adb/modules/tricky_store"

    # Detect engine name from daemon's --nice-name
    engine=""
    if [ -f "$ts_module/daemon" ]; then
        engine=$(grep -o '\-\-nice-name=[^ ]*' "$ts_module/daemon" 2>/dev/null | cut -d= -f2)
    fi
    if [ -z "$engine" ] && [ -f "$ts_module/module.prop" ]; then
        engine=$(grep '^name=' "$ts_module/module.prop" 2>/dev/null | cut -d= -f2)
    fi
    engine=${engine:-TEESimulator}

    tee_pid=$(pidof "$engine" 2>/dev/null)
    if [ -n "$tee_pid" ]; then
        echo "status=running"
        echo "pid=$tee_pid"
    else
        echo "status=dead"
        echo "pid="
    fi
    echo "engine=$engine"
    if [ -f "$state_file" ]; then
        restarts=$(grep "^restarts=" "$state_file" 2>/dev/null | cut -d= -f2)
        echo "restarts=${restarts:-0}"
    else
        echo "restarts=0"
    fi
    exit
    ;;
*)
    _log_error "Unknown command: $1"
    exit 1
    ;;
esac
