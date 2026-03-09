SKIPUNZIP=0
DEBUG=false
COMPATH="$MODPATH/common"
TS="/data/adb/modules/tricky_store"
SCRIPT_DIR="/data/adb/tricky_store"
CONFIG_DIR="$SCRIPT_DIR/target_list_config"
MODID=$(grep_prop id "$TMPDIR/module.prop")
NEW_MODID=".TA_enhanced"
AUTOMATION_DIR="$SCRIPT_DIR/.automation"
ACTION=true

ui_print " "
ui_print "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  ⚡ Tricky Addon Enhanced"
ui_print "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "

if [ "$APATCH" = "true" ]; then
    ui_print "  📱 APatch $APATCH_VER | $APATCH_VER_CODE"
    ACTION=false
elif [ "$KSU" = "true" ]; then
    if [ "$KSU_NEXT" ]; then
        ui_print "  📱 KernelSU Next $KSU_KERNEL_VER_CODE | $KSU_VER_CODE"
    else
        ui_print "  📱 KernelSU $KSU_KERNEL_VER_CODE | $KSU_VER_CODE"
    fi
    ACTION=false
elif [ "$MAGISK_VER_CODE" ]; then
    ui_print "  📱 Magisk $MAGISK_VER | $MAGISK_VER_CODE"
else
    ui_print " "
    ui_print "  ❌ Recovery is not supported"
    abort " "
fi

if [ -d "$TS" ]; then
    engine_name=""
    if [ -f "$TS/daemon" ]; then
        engine_name=$(grep -o '\-\-nice-name=[^ ]*' "$TS/daemon" 2>/dev/null | cut -d= -f2)
    fi
    engine_name=${engine_name:-"attestation engine"}
    ui_print "  🔒 $engine_name detected"
else
    ui_print "  ⚠️  No attestation engine module found"
fi

. "$MODPATH/install_func.sh"

ABI=$(getprop ro.product.cpu.abi)
case "$ABI" in
    arm64-v8a|armeabi-v7a) ;;
    *) abort "  ❌ Unsupported ABI: $ABI" ;;
esac
BIN="$MODPATH/bin/$ABI/ta-enhanced"

for legacy_id in TA_utl .TA_utl; do
    legacy_dir="/data/adb/modules/$legacy_id"
    if [ -d "$legacy_dir" ] && [ ! -f "$legacy_dir/remove" ]; then
        touch "$legacy_dir/disable" "$legacy_dir/remove"
        ui_print "  🗑️  Legacy module $legacy_id tagged for removal"
    fi
done

if [ -x "$BIN" ] && "$BIN" version >/dev/null 2>&1; then
    ui_print "  🔍 Checking for module conflicts..."
    if ! "$BIN" conflict check --install 2>/dev/null; then
        ui_print "  ❌ Aggressive conflict detected"
        ui_print "  ❌ Remove conflicting module before installing"
        abort "Conflict detection failed"
    fi
    ui_print "  ✅ No conflicts found"
fi

HAS_TARGET=0
if [ -f "/data/adb/tricky_store/target.txt" ] && [ -s "/data/adb/tricky_store/target.txt" ]; then
    HAS_TARGET=1
fi

ui_print " "
ui_print "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  🎯 Automation Mode"
ui_print "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "
ui_print "  🔊 Vol+ = Full Automation (recommended)"
ui_print "  🔉 Vol- = Manual Mode (keep existing target.txt)"
ui_print " "
if [ "$HAS_TARGET" -eq 1 ]; then
    ui_print "  📋 Existing target.txt detected — waiting for your choice..."
    ui_print " "
    choose_automation 0
else
    ui_print "  ⏱️  Auto-selecting Full Automation in 10s..."
    ui_print " "
    choose_automation
fi
auto_mode=$?

if [ "$auto_mode" -eq 0 ]; then
    ui_print "  ✅ Full Automation selected"
    AUTOMATION_ENABLED=1
else
    ui_print "  🔧 Manual Mode selected"
    AUTOMATION_ENABLED=0
fi

ui_print " "
ui_print "  📦 Installing..."

initialize
populate_system_app

if [ -x "$BIN" ]; then
    if ! "$BIN" version >/dev/null 2>&1; then
        abort "  ❌ Binary validation failed -- ta-enhanced does not run on this device"
    fi
else
    abort "  ❌ Binary not found at $BIN"
fi

_vbhash=$(getprop ro.boot.vbmeta.digest 2>/dev/null \
    | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' \
    | grep -oE '^[a-f0-9]{64}$')
if [ -n "$_vbhash" ]; then
    _old_hash=""
    [ -f "/data/adb/boot_hash" ] && _old_hash=$(cat /data/adb/boot_hash 2>/dev/null)
    if [ "$_vbhash" != "$_old_hash" ]; then
        echo "$_vbhash" > /data/adb/boot_hash.tmp
        mv -f /data/adb/boot_hash.tmp /data/adb/boot_hash
        chmod 644 /data/adb/boot_hash
        ui_print "  🔐 VBHash captured from bootloader"
    else
        ui_print "  🔐 VBHash unchanged"
    fi
fi

if [ "$AUTOMATION_ENABLED" -eq 1 ]; then
    ui_print "  📋 Building automation configuration..."
    build_exclude_list
    generate_initial_target
elif [ "$HAS_TARGET" -eq 1 ]; then
    ui_print "  📋 Existing target.txt preserved"
    for _app in com.google.android.gms com.google.android.gsf com.android.vending \
                 com.oplus.deepthinker com.heytap.speechassist com.coloros.sceneservice; do
        pm list packages -s 2>/dev/null | grep -q "package:$_app" || continue
        grep -qxF "$_app" "$TARGET_FILE" 2>/dev/null || echo "$_app" >> "$TARGET_FILE"
    done
    pm list packages -3 2>/dev/null | sed 's/^package://' | sort > "$AUTOMATION_DIR/known_packages.txt"
else
    generate_minimal_target
fi

TA_DIR="$SCRIPT_DIR/ta-enhanced"
mkdir -p "$TA_DIR/logs"

# PM can be sluggish during install
_try=0
while [ "$_try" -lt 3 ]; do
    _pkgs=$(pm list packages -s 2>/dev/null)
    [ -n "$_pkgs" ] && break
    _try=$((_try + 1))
    sleep 1
done
[ -n "$_pkgs" ] && echo "$_pkgs" | sed 's/^package://' | sort > "$TA_DIR/system_packages.txt"

if [ ! -f "$TA_DIR/config.toml" ]; then
    "$BIN" config init --automation="$AUTOMATION_ENABLED" 2>/dev/null \
        || ui_print "  ⚠️  Config init failed, daemon will create defaults at first run"

    DEVICE_LANG=$(getprop ro.system.locale 2>/dev/null)
    [ -z "$DEVICE_LANG" ] && DEVICE_LANG=$(getprop persist.sys.locale 2>/dev/null)
    [ -z "$DEVICE_LANG" ] && DEVICE_LANG=$(getprop ro.product.locale 2>/dev/null)

    LANG_CODE=$(printf '%s' "$DEVICE_LANG" | sed 's/_/-/g')
    case "$LANG_CODE" in
        zh-Hans*|zh-CN*) LANG_CODE="zh-CN" ;;
        zh-Hant*|zh-TW*) LANG_CODE="zh-TW" ;;
        pt-BR*) LANG_CODE="pt-BR" ;;
        pt*) LANG_CODE="pt-BR" ;;
        es-ES*|es*) LANG_CODE="es-ES" ;;
        *-*) LANG_CODE="${LANG_CODE%%-*}" ;;
    esac
    case "$LANG_CODE" in
        ar|az|bn|de|el|en|es-ES|fa|fr|id|it|ja|ko|pl|pt-BR|ru|th|tl|tr|uk|vi|zh-CN|zh-TW) ;;
        *) LANG_CODE="en" ;;
    esac

    "$BIN" config set ui.language "$LANG_CODE" 2>/dev/null || true
    ui_print "  ⚙️  Language: $LANG_CODE"
else
    "$BIN" config set automation.enabled "$AUTOMATION_ENABLED" 2>/dev/null || true
    ui_print "  ⚙️  Configuration preserved (automation=$AUTOMATION_ENABLED)"
fi

if [ -f "$SCRIPT_DIR/enhanced.conf" ]; then
    "$BIN" config migrate 2>/dev/null \
        || ui_print "  ⚠️  Legacy config migration failed"
fi

ui_print "  🛡️  Setting security patch dates..."
if "$BIN" security-patch update --force 2>/dev/null; then
    ui_print "  ✅ Security patch configured"
else
    ui_print "  ⚠️  Security patch failed (will retry on boot)"
fi

if [ ! -f "$SCRIPT_DIR/keybox.xml" ]; then
    ui_print "  🔑 Fetching keybox..."
    if "$BIN" keybox fetch 2>/dev/null; then
        ui_print "  ✅ Keybox installed"
    else
        ui_print "  ⚠️  Keybox fetch failed (will retry on boot)"
    fi
else
    ui_print "  🔑 Existing keybox preserved"
fi

rm -f "$MODPATH/install_func.sh"

ui_print " "
ui_print "  📌 This module is NOT part of Tricky Store."
ui_print "  📌 Do NOT report issues to Tricky Store."
ui_print " "

ui_print "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  ✨ Installation completed!"
ui_print "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "
