#!/system/bin/sh
# ==============================================================================
# UNIFIED LOGGING SYSTEM for Tricky Addon Enhanced
# ==============================================================================
# Chief Android Shell Architect Design
#
# DESIGN PRINCIPLES:
# 1. Pre-initialize log directory ONCE at module install (customize.sh)
# 2. Never mkdir inside log functions - if dir missing, fallback to stderr
# 3. Boot phase aware - knows when /data is available
# 4. Works with toybox (AOSP) and busybox (Magisk) shell implementations
# 5. Defensive coding - every operation can fail, handle gracefully
#
# USAGE:
#   . /path/to/logging.sh
#   log_init "COMPONENT_NAME"    # Initialize with component identifier
#   log_info "message"           # Standard log
#   log_warn "warning message"   # Warning level
#   log_error "error message"    # Error level
#   log_debug "debug info"       # Debug (only if LOG_DEBUG=1)
#   log_fatal "critical error"   # Fatal - logs and returns 1
# ==============================================================================

# === CONFIGURATION ===
# These can be overridden before sourcing this file
LOG_BASE_DIR="${LOG_BASE_DIR:-/data/adb/Tricky-addon-enhanced/logs}"
LOG_MAIN_FILE="${LOG_MAIN_FILE:-$LOG_BASE_DIR/main.log}"
LOG_BOOT_FILE="${LOG_BOOT_FILE:-$LOG_BASE_DIR/boot.log}"
LOG_MAX_SIZE="${LOG_MAX_SIZE:-1048576}"  # 1MB default
LOG_DEBUG="${LOG_DEBUG:-0}"

# Internal state
_LOG_COMPONENT=""
_LOG_INITIALIZED=0
_LOG_TARGET=""
_LOG_FALLBACK_STDERR=0
_LOG_BOOT_PHASE=""

# === BOOT PHASE DETECTION ===
# Detects current Android boot phase to adjust logging behavior
_log_detect_boot_phase() {
    # Check if boot completed
    if [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ]; then
        _LOG_BOOT_PHASE="runtime"
        return 0
    fi

    # Check if zygote is running (indicates post-fs-data has completed)
    if pidof zygote >/dev/null 2>&1 || pidof zygote64 >/dev/null 2>&1; then
        _LOG_BOOT_PHASE="service"
        return 0
    fi

    # Check if /data is decrypted and mounted
    if [ -d "/data/adb" ] && [ -w "/data/adb" ]; then
        _LOG_BOOT_PHASE="post-fs-data"
        return 0
    fi

    # Very early boot or recovery
    _LOG_BOOT_PHASE="early"
    return 0
}

# === FILESYSTEM CHECKS ===
# Verifies log directory accessibility without creating it
_log_check_writable() {
    target_dir="$1"

    # Directory must exist (pre-created at install time)
    [ ! -d "$target_dir" ] && return 1

    # Directory must be writable
    [ ! -w "$target_dir" ] && return 1

    # Test actual write capability (some filesystems lie about -w)
    _test_file="$target_dir/.log_test_$$"
    if : > "$_test_file" 2>/dev/null; then
        rm -f "$_test_file" 2>/dev/null
        return 0
    fi

    return 1
}

# === LOG ROTATION ===
# Rotates log file if it exceeds maximum size
# MUST be called with existing, writable log file
_log_rotate() {
    log_file="$1"
    max_size="$2"

    [ ! -f "$log_file" ] && return 0

    # Get file size - compatible with both toybox and busybox
    # toybox stat uses -c, busybox stat may use -c or different format
    # wc -c is most portable
    current_size=$(wc -c < "$log_file" 2>/dev/null) || current_size=0

    # Handle wc output that may have leading spaces
    current_size=$(echo "$current_size" | tr -d ' ')

    if [ "$current_size" -gt "$max_size" ] 2>/dev/null; then
        # Rotate: current -> .old, .old gets overwritten
        mv -f "$log_file" "${log_file}.old" 2>/dev/null || {
            # If mv fails (read-only, etc), truncate instead
            : > "$log_file" 2>/dev/null
        }
    fi
}

# === TIMESTAMP GENERATION ===
# Generates ISO-like timestamp, compatible with both toybox and busybox date
_log_timestamp() {
    # Both toybox and busybox support this format
    date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "0000-00-00 00:00:00"
}

# === CORE LOG WRITER ===
# Internal function that performs actual log writing
# NEVER call mkdir - directory must pre-exist
_log_write() {
    level="$1"
    message="$2"

    timestamp=$(_log_timestamp)
    formatted="[$timestamp] [$_LOG_COMPONENT] [$level] $message"

    # Primary: write to log file if available
    if [ "$_LOG_FALLBACK_STDERR" -eq 0 ] && [ -n "$_LOG_TARGET" ]; then
        # Attempt rotation before write
        _log_rotate "$_LOG_TARGET" "$LOG_MAX_SIZE"

        # Write to file - if this fails, switch to stderr fallback
        if ! echo "$formatted" >> "$_LOG_TARGET" 2>/dev/null; then
            _LOG_FALLBACK_STDERR=1
        fi
    fi

    # Fallback: write to stderr if file logging failed or unavailable
    if [ "$_LOG_FALLBACK_STDERR" -eq 1 ]; then
        echo "$formatted" >&2
    fi
}

# === PUBLIC API ===

# Initialize logging for a component
# MUST be called before any log_* functions
# Parameters:
#   $1 - Component name (e.g., "KEYBOX", "PATCH", "BOOT")
#   $2 - (optional) "boot" to use boot.log instead of main.log
log_init() {
    _LOG_COMPONENT="${1:-UNKNOWN}"
    log_type="${2:-main}"

    _log_detect_boot_phase

    # Select target log file based on type
    case "$log_type" in
        boot)   _LOG_TARGET="$LOG_BOOT_FILE" ;;
        *)      _LOG_TARGET="$LOG_MAIN_FILE" ;;
    esac

    # Check if we can write to the log directory
    if _log_check_writable "$LOG_BASE_DIR"; then
        _LOG_FALLBACK_STDERR=0
        _LOG_INITIALIZED=1
    else
        # Directory not writable - fall back to stderr
        # This is NOT an error during early boot or install
        _LOG_FALLBACK_STDERR=1
        _LOG_INITIALIZED=1

        # Only warn if we're past early boot and expected /data
        if [ "$_LOG_BOOT_PHASE" != "early" ]; then
            echo "[LOGGING] WARNING: Cannot write to $LOG_BASE_DIR, using stderr" >&2
        fi
    fi
}

# Standard info-level log
log_info() {
    [ "$_LOG_INITIALIZED" -eq 0 ] && log_init "UNINITIALIZED"
    _log_write "INFO" "$1"
}

# Warning-level log
log_warn() {
    [ "$_LOG_INITIALIZED" -eq 0 ] && log_init "UNINITIALIZED"
    _log_write "WARN" "$1"
}

# Error-level log
log_error() {
    [ "$_LOG_INITIALIZED" -eq 0 ] && log_init "UNINITIALIZED"
    _log_write "ERROR" "$1"
}

# Debug-level log (only when LOG_DEBUG=1)
log_debug() {
    [ "$LOG_DEBUG" != "1" ] && return 0
    [ "$_LOG_INITIALIZED" -eq 0 ] && log_init "UNINITIALIZED"
    _log_write "DEBUG" "$1"
}

# Fatal error - logs and returns 1 for error chaining
log_fatal() {
    [ "$_LOG_INITIALIZED" -eq 0 ] && log_init "UNINITIALIZED"
    _log_write "FATAL" "$1"
    return 1
}

# === UTILITY FUNCTIONS ===

# Get current boot phase (for scripts that need to adjust behavior)
log_get_boot_phase() {
    _log_detect_boot_phase
    echo "$_LOG_BOOT_PHASE"
}

# Check if file logging is active (vs stderr fallback)
log_is_file_logging() {
    [ "$_LOG_FALLBACK_STDERR" -eq 0 ] && return 0
    return 1
}

# Force flush - no-op in shell but useful for documentation/future
log_flush() {
    # Shell writes are not buffered like C, but sync can help
    sync 2>/dev/null || true
}

# === PRE-INITIALIZATION HELPER ===
# Call this from customize.sh to create log directory structure
# This is the ONLY place mkdir should happen for logging
log_preinit_dirs() {
    target_dir="${1:-$LOG_BASE_DIR}"

    # Create directory with proper permissions
    if ! mkdir -p "$target_dir" 2>/dev/null; then
        echo "[LOGGING] ERROR: Failed to create log directory: $target_dir" >&2
        return 1
    fi

    # Set permissions - readable by shell, not world-writable
    chmod 755 "$target_dir" 2>/dev/null

    # Create empty log files to ensure they're ready
    : > "$target_dir/main.log" 2>/dev/null
    : > "$target_dir/boot.log" 2>/dev/null
    : > "$target_dir/install.log" 2>/dev/null
    : > "$target_dir/conflict.log" 2>/dev/null
    : > "$target_dir/watcher.log" 2>/dev/null

    # Set file permissions
    chmod 644 "$target_dir"/*.log 2>/dev/null

    return 0
}

# === MIGRATION HELPER ===
# Provides backward compatibility for scripts using old log function names
# These wrap the new API with the old function signatures
#
# NOTE: We use global variables instead of local to maintain
# strict POSIX sh compatibility. This is safe because:
# 1. Legacy functions are not recursive
# 2. Shell is single-threaded
# 3. We restore immediately after use

_LOG_SAVED_COMPONENT=""
_LOG_SAVED_TARGET=""

# Internal helper to temporarily switch log target and component
_log_legacy_write() {
    _component="$1"
    _log_type="$2"
    _message="$3"

    # Save current state
    _LOG_SAVED_COMPONENT="$_LOG_COMPONENT"
    _LOG_SAVED_TARGET="$_LOG_TARGET"

    # Initialize if needed, but always set correct target
    if [ "$_LOG_INITIALIZED" -eq 0 ]; then
        log_init "$_component" "$_log_type"
    else
        # Override target for this message
        case "$_log_type" in
            boot) _LOG_TARGET="$LOG_BOOT_FILE" ;;
            *)    _LOG_TARGET="$LOG_MAIN_FILE" ;;
        esac
    fi

    _LOG_COMPONENT="$_component"
    _log_write "INFO" "$_message"

    # Restore state
    _LOG_COMPONENT="$_LOG_SAVED_COMPONENT"
    _LOG_TARGET="$_LOG_SAVED_TARGET"
}

# Legacy: log_boot() -> log_info() with BOOT component
log_boot() {
    _log_legacy_write "BOOT" "boot" "$1"
}

# Legacy: log_keybox() -> log_info() with KEYBOX component
log_keybox() {
    _log_legacy_write "KEYBOX" "boot" "$1"
}

# Legacy: log_patch() -> log_info() with PATCH component
log_patch() {
    _log_legacy_write "PATCH" "boot" "$1"
}

# Legacy: log_vbhash() -> log_info() with VBHASH component
log_vbhash() {
    _log_legacy_write "VBHASH" "boot" "$1"
}

# Legacy: log_conflict() -> log_info() with CONFLICT component
log_conflict() {
    _log_legacy_write "CONFLICT" "boot" "$1"
}

# Legacy: log_msg() -> log_info() with WATCHER component
log_msg() {
    _log_legacy_write "WATCHER" "main" "$1"
}

# Legacy: log_install() -> log_info() with INSTALL component
log_install() {
    _log_legacy_write "INSTALL" "main" "$1"
}

# Legacy: early_log() -> log_info() with INSTALL component (customize.sh early phase)
early_log() {
    log_install "$1"
}
