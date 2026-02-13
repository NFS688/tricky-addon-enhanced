SKIPUNZIP=0
DEBUG=false
COMPATH="$MODPATH/common"
TS="/data/adb/modules/tricky_store"
SCRIPT_DIR="/data/adb/tricky_store"
CONFIG_DIR="$SCRIPT_DIR/target_list_config"
MODID=$(grep_prop id "$TMPDIR/module.prop")
NEW_MODID=".TA_utl"
kb="$COMPATH/.default"
AUTOMATION_DIR="$SCRIPT_DIR/.automation"
ACTION=true

# Initialize logging FIRST - create directories before any logging attempts
. "$MODPATH/common/logging.sh"
log_preinit_dirs
mkdir -p "$AUTOMATION_DIR"
log_init "INSTALL" "main"

ui_print " "
ui_print "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  ⚡ Tricky Addon Enhanced"
ui_print "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "

# Detect and log root manager
if [ "$APATCH" = "true" ]; then
    if [ "$APATCH_VER_CODE" -lt 11159 ]; then
        log_error "APatch version $APATCH_VER_CODE too old (need 11159+)"
        abort "  ❌ Unsupported APatch version, please update to 11159+"
    fi
    ui_print "  📱 APatch $APATCH_VER | $APATCH_VER_CODE"
    log_info "Root manager: APatch $APATCH_VER ($APATCH_VER_CODE)"
    ACTION=false
elif [ "$KSU" = "true" ]; then
    if [ "$KSU_VER_CODE" -lt 32234 ]; then
        log_error "KernelSU version $KSU_VER_CODE too old (need 32234+)"
        abort "  ❌ Unsupported KernelSU version, please update to 32234+"
    fi
    if [ "$KSU_NEXT" ]; then
        ui_print "  📱 KernelSU Next $KSU_KERNEL_VER_CODE | $KSU_VER_CODE"
        log_info "Root manager: KernelSU Next $KSU_KERNEL_VER_CODE ($KSU_VER_CODE)"
    else
        ui_print "  📱 KernelSU $KSU_KERNEL_VER_CODE | $KSU_VER_CODE"
        log_info "Root manager: KernelSU $KSU_KERNEL_VER_CODE ($KSU_VER_CODE)"
    fi
    ACTION=false
elif [ "$MAGISK_VER_CODE" ]; then
    ui_print "  📱 Magisk $MAGISK_VER | $MAGISK_VER_CODE"
    log_info "Root manager: Magisk $MAGISK_VER ($MAGISK_VER_CODE)"
else
    log_error "Recovery installation not supported"
    ui_print " "
    ui_print "  ❌ Recovery is not supported"
    abort " "
fi

# Check attestation engine (TEESimulator or TrickyStore)
if [ -d "$TS" ]; then
    engine_name=""
    if [ -f "$TS/daemon" ]; then
        engine_name=$(grep -o '\-\-nice-name=[^ ]*' "$TS/daemon" 2>/dev/null | cut -d= -f2)
    fi
    engine_name=${engine_name:-"attestation engine"}
    ui_print "  🔒 $engine_name detected"
    log_info "$engine_name module found"
else
    log_warn "No attestation engine found (TEESimulator/TrickyStore)"
    ui_print "  ⚠️  No attestation engine module found"
fi

. "$MODPATH/install_func.sh"
. "$MODPATH/common/utils.sh"

# Check for conflicting modules
. "$MODPATH/common/conflict_manager.sh"
ui_print "  🔍 Checking for module conflicts..."
if ! check_all_conflicts; then
    log_error "Conflict detection failed - aggressive conflict found"
    ui_print "  ❌ Aggressive conflict detected"
    ui_print "  ❌ Remove conflicting module before installing"
    abort "Conflict detection failed"
fi
ui_print "  ✅ No conflicts found"
log_info "Conflict check passed"

ui_print " "

# Volume key selection for automation mode
ui_print "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  🎯 Automation Mode"
ui_print "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "
ui_print "  🔊 Vol+ = Full Automation (recommended)"
ui_print "  🔉 Vol- = Manual Mode (skip target.txt)"
ui_print " "
ui_print "  ⏱️  Auto-selecting Full Automation in 10s..."
ui_print " "

choose_automation
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

# Capture VBHash at install time — bootloader property is untouched here
if [ ! -f "/data/adb/boot_hash" ]; then
    _vbhash=$(getprop ro.boot.vbmeta.digest 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' | grep -oE '^[a-f0-9]{64}$')
    if [ -n "$_vbhash" ]; then
        echo "$_vbhash" > /data/adb/boot_hash.tmp && mv -f /data/adb/boot_hash.tmp /data/adb/boot_hash
        chmod 644 /data/adb/boot_hash
        log_info "VBHash captured at install: $(printf '%.16s' "$_vbhash")..."
        ui_print "  🔐 VBHash captured from bootloader"
    else
        log_debug "Bootloader vbmeta.digest not available (length: ${#_vbhash}), will extract at boot"
    fi
else
    ui_print "  🔐 Existing VBHash preserved"
    log_info "VBHash preserved from previous install"
fi

# Build target.txt based on automation choice
if [ "$AUTOMATION_ENABLED" -eq 1 ]; then
    ui_print "  📋 Building automation configuration..."
    build_exclude_list
    generate_initial_target
else
    generate_minimal_target
fi

# Preserve existing config across reinstalls
if [ ! -f "$SCRIPT_DIR/enhanced.conf" ]; then
    ui_print "  ⚙️  Creating configuration..."
    cat > "$SCRIPT_DIR/enhanced.conf" << EOF
# Keybox settings
keybox_source=yurikey
keybox_enabled=1
keybox_interval=300
keybox_fallback_enabled=1

# Security patch settings
security_patch_auto=1
security_patch_interval=86400

# VBMeta spoofing
vbhash_enabled=1

# Integrity settings
conflict_check_enabled=1

# Automation settings
automation_target_enabled=$AUTOMATION_ENABLED
EOF
    log_info "Enhanced config created (automation=$AUTOMATION_ENABLED)"
else
    # Update automation setting in existing config
    if grep -q "^automation_target_enabled=" "$SCRIPT_DIR/enhanced.conf"; then
        sed -i "s/^automation_target_enabled=.*/automation_target_enabled=$AUTOMATION_ENABLED/" "$SCRIPT_DIR/enhanced.conf"
    else
        printf '\n# Automation settings\nautomation_target_enabled=%s\n' "$AUTOMATION_ENABLED" >> "$SCRIPT_DIR/enhanced.conf"
    fi
    ui_print "  ⚙️  Configuration preserved (automation=$AUTOMATION_ENABLED)"
    log_info "Enhanced config preserved, automation=$AUTOMATION_ENABLED"
fi

# Auto-set security patch dates
ui_print "  🛡️  Setting security patch dates..."
. "$MODPATH/common/security_patch_manager.sh"
if set_security_patch; then
    log_info "Security patch configured (device defaults)"
    ui_print "  ✅ Security patch baseline set"
    if auto_update_security_patch; then
        log_info "Security patch upgraded to latest"
        ui_print "  ✅ Security patch upgraded to latest"
    else
        log_info "Google fetch unavailable, using device defaults"
    fi
else
    log_warn "Security patch configuration failed - will retry on boot"
    ui_print "  ⚠️  Security patch failed (will retry on boot)"
fi

# Only fetch keybox on fresh install — respect user's existing keybox
if [ ! -f "$SCRIPT_DIR/keybox.xml" ]; then
    ui_print "  🔑 Fetching keybox..."
    . "$MODPATH/common/keybox_manager.sh"
    if fetch_keybox; then
        log_info "Keybox installed from $(read_config keybox_source yurikey)"
        ui_print "  ✅ Keybox installed"
    else
        log_warn "Keybox fetch failed - will retry on boot"
        ui_print "  ⚠️  Keybox fetch failed (will retry on boot)"
    fi
else
    ui_print "  🔑 Existing keybox preserved"
    log_info "Keybox preserved from previous install"
fi

ui_print "  🏁 Finalizing..."
find_config
migrate_config

log_info "Installation completed successfully"

rm -f "$MODPATH/install_func.sh"

ui_print " "
ui_print "  📌 This module is NOT part of Tricky Store."
ui_print "  📌 Do NOT report issues to Tricky Store."
ui_print " "

sleep 1

ui_print "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  ✨ Installation completed!"
ui_print "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "
