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

. "$MODPATH/install_i18n.sh"

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
    ui_print "  🔍 $(_msg conflict_check)"
    if ! "$BIN" conflict check --install 2>/dev/null; then
        ui_print "  ❌ $(_msg conflict_found)"
        ui_print "  ❌ $(_msg conflict_remove)"
        abort "Conflict detection failed"
    fi
    ui_print "  ✅ $(_msg no_conflicts)"
fi

HAS_TARGET=0
if [ -f "/data/adb/tricky_store/target.txt" ] && [ -s "/data/adb/tricky_store/target.txt" ]; then
    HAS_TARGET=1
fi

ui_print " "
ui_print "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  🎯 $(_msg automation_title)"
ui_print "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "
ui_print "  🔊 $(_msg vol_up)"
ui_print "  🔉 $(_msg vol_down)"
ui_print " "
if [ "$HAS_TARGET" -eq 1 ]; then
    ui_print "  📋 $(_msg has_target)"
    ui_print " "
    choose_automation 0
else
    ui_print "  ⏱️  $(_msg auto_select)"
    ui_print " "
    choose_automation
fi
auto_mode=$?

if [ "$auto_mode" -eq 0 ]; then
    ui_print "  ✅ $(_msg auto_selected)"
    AUTOMATION_ENABLED=1
else
    ui_print "  🔧 $(_msg manual_selected)"
    AUTOMATION_ENABLED=0
fi

ui_print " "
ui_print "  📦 $(_msg installing)"

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
    ui_print "  📋 $(_msg building_config)"
    build_exclude_list
    generate_initial_target
elif [ "$HAS_TARGET" -eq 1 ]; then
    ui_print "  📋 $(_msg target_preserved)"
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

    LANG_CODE="$INSTALL_LANG"
    "$BIN" config set ui.language "$LANG_CODE" 2>/dev/null || true
    ui_print "  ⚙️  Language: $LANG_CODE"
else
    "$BIN" config set automation.enabled "$AUTOMATION_ENABLED" 2>/dev/null || true
    ui_print "  ⚙️  Configuration preserved (automation=$AUTOMATION_ENABLED)"
fi

# Snapshot device region props (only on fresh install — don't overwrite user overrides)
_cur_hwc=$("$BIN" config get region.hwc 2>/dev/null)
if [ -z "$_cur_hwc" ]; then
    _hwc=$(getprop ro.boot.hwc 2>/dev/null)
    _hwcountry=$(getprop ro.boot.hwcountry 2>/dev/null)
    _mod_device=$(getprop ro.product.mod_device 2>/dev/null)
    [ -n "$_hwc" ] && "$BIN" config set region.hwc "$_hwc" 2>/dev/null
    [ -n "$_hwcountry" ] && "$BIN" config set region.hwcountry "$_hwcountry" 2>/dev/null
    [ -n "$_mod_device" ] && "$BIN" config set region.mod_device "$_mod_device" 2>/dev/null
    ui_print "  🌐 Region: hwc=${_hwc:-n/a} hwcountry=${_hwcountry:-n/a} mod_device=${_mod_device:-n/a}"
fi

if [ -f "$SCRIPT_DIR/enhanced.conf" ]; then
    "$BIN" config migrate 2>/dev/null \
        || ui_print "  ⚠️  Legacy config migration failed"
fi

ui_print "  🛡️  Setting security patch dates..."
if "$BIN" security-patch update --force 2>/dev/null; then
    ui_print "  ✅ $(_msg sec_patch_ok)"
else
    ui_print "  ⚠️  $(_msg sec_patch_fail)"
fi

if [ ! -f "$SCRIPT_DIR/keybox.xml" ]; then
    ui_print "  🔑 $(_msg keybox_fetch)"
    if "$BIN" keybox fetch 2>/dev/null; then
        ui_print "  ✅ $(_msg keybox_ok)"
    else
        ui_print "  ⚠️  $(_msg keybox_fail)"
    fi
else
    ui_print "  🔑 $(_msg keybox_kept)"
fi

rm -f "$MODPATH/install_func.sh"

ui_print " "
ui_print "  📌 $(_msg not_tricky_store)"
ui_print "  📌 $(_msg no_report)"
ui_print " "

ui_print "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  ✨ $(_msg completed)"
ui_print "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "
