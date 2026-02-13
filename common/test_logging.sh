#!/system/bin/sh
# Integration test harness for logging.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS_COUNT=0
FAIL_COUNT=0

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "[PASS] $1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "[FAIL] $1"
}

# Test 1: Source without error
echo "=== TEST: Source logging.sh ==="
if . "$SCRIPT_DIR/logging.sh" 2>/dev/null; then
    pass "logging.sh sources without error"
else
    fail "logging.sh failed to source"
fi

# Test 2: Re-source without error (idempotent)
echo "=== TEST: Re-source logging.sh ==="
if . "$SCRIPT_DIR/logging.sh" 2>/dev/null; then
    pass "logging.sh can be sourced multiple times"
else
    fail "logging.sh fails on re-source"
fi

# Test 3: API functions exist
echo "=== TEST: API functions exist ==="
for func in log_init log_info log_warn log_error log_debug log_fatal log_preinit_dirs log_get_boot_phase; do
    if type "$func" >/dev/null 2>&1; then
        pass "Function $func exists"
    else
        fail "Function $func missing"
    fi
done

# Test 4: Legacy functions exist
echo "=== TEST: Legacy compatibility functions exist ==="
for func in log_boot log_keybox log_patch log_vbhash log_conflict log_msg log_install early_log; do
    if type "$func" >/dev/null 2>&1; then
        pass "Legacy function $func exists"
    else
        fail "Legacy function $func missing"
    fi
done

# Test 5: Boot phase detection
echo "=== TEST: Boot phase detection ==="
phase=$(log_get_boot_phase 2>/dev/null)
case "$phase" in
    early|post-fs-data|service|runtime)
        pass "Boot phase detected: $phase"
        ;;
    "")
        fail "Boot phase detection returned empty"
        ;;
    *)
        fail "Unknown boot phase: $phase"
        ;;
esac

# Test 6: stderr fallback with non-existent directory
echo "=== TEST: stderr fallback with non-existent directory ==="
_LOG_INITIALIZED=0
LOG_BASE_DIR="/nonexistent/path/that/does/not/exist"
LOG_MAIN_FILE="$LOG_BASE_DIR/main.log"
LOG_BOOT_FILE="$LOG_BASE_DIR/boot.log"

log_init "TEST_FALLBACK" 2>/dev/null
if [ "$_LOG_FALLBACK_STDERR" -eq 1 ]; then
    pass "Correctly fell back to stderr for non-existent directory"
else
    fail "Did not fall back to stderr for non-existent directory"
fi

# Test 7: log_info writes to stderr when in fallback mode
echo "=== TEST: log_info writes to stderr in fallback mode ==="
stderr_output=$(log_info "test message" 2>&1)
if echo "$stderr_output" | grep -q "test message"; then
    pass "log_info writes to stderr in fallback mode"
else
    fail "log_info did not write to stderr in fallback mode"
fi

# Test 8: Formatted output structure
echo "=== TEST: Log format structure ==="
stderr_output=$(log_warn "format test" 2>&1)
if echo "$stderr_output" | grep -q '\[.*\] \[TEST_FALLBACK\] \[WARN\] format test'; then
    pass "Log format is correct: [timestamp] [component] [level] message"
else
    fail "Log format incorrect: $stderr_output"
fi

# Test 9: log_debug respects LOG_DEBUG flag
echo "=== TEST: log_debug respects LOG_DEBUG flag ==="
LOG_DEBUG=0
stderr_output=$(log_debug "should not appear" 2>&1)
if [ -z "$stderr_output" ]; then
    pass "log_debug suppressed when LOG_DEBUG=0"
else
    fail "log_debug output when LOG_DEBUG=0: $stderr_output"
fi

LOG_DEBUG=1
stderr_output=$(log_debug "should appear" 2>&1)
if echo "$stderr_output" | grep -q "should appear"; then
    pass "log_debug outputs when LOG_DEBUG=1"
else
    fail "log_debug did not output when LOG_DEBUG=1"
fi

# Test 10: log_fatal returns 1
echo "=== TEST: log_fatal returns 1 ==="
log_fatal "fatal test" 2>/dev/null
ret=$?
if [ "$ret" -eq 1 ]; then
    pass "log_fatal returns 1"
else
    fail "log_fatal returned $ret instead of 1"
fi

# Test 11: log_preinit_dirs creates directory structure
echo "=== TEST: log_preinit_dirs creates directories ==="
test_dir="/tmp/logging_test_$$"
rm -rf "$test_dir" 2>/dev/null
if log_preinit_dirs "$test_dir" 2>/dev/null; then
    if [ -d "$test_dir" ] && [ -f "$test_dir/main.log" ] && [ -f "$test_dir/boot.log" ]; then
        pass "log_preinit_dirs creates directory and log files"
    else
        fail "log_preinit_dirs did not create expected files"
    fi
else
    fail "log_preinit_dirs returned error"
fi
rm -rf "$test_dir" 2>/dev/null

# Test 12: File logging works with valid directory
echo "=== TEST: File logging with valid directory ==="
test_dir="/tmp/logging_test_$$"
log_preinit_dirs "$test_dir" 2>/dev/null
LOG_BASE_DIR="$test_dir"
LOG_MAIN_FILE="$test_dir/main.log"
LOG_BOOT_FILE="$test_dir/boot.log"
_LOG_INITIALIZED=0
_LOG_FALLBACK_STDERR=0

log_init "FILE_TEST" "main"
if [ "$_LOG_FALLBACK_STDERR" -eq 0 ]; then
    pass "File logging mode enabled for valid directory"
else
    fail "Unexpected fallback for valid directory"
fi

log_info "file test message"
if grep -q "file test message" "$test_dir/main.log" 2>/dev/null; then
    pass "Message written to log file"
else
    fail "Message not found in log file"
fi
rm -rf "$test_dir" 2>/dev/null

# Test 12b: BUG - First write failure loses message
echo "=== TEST: First write failure message loss (KNOWN BUG) ==="
test_dir="/tmp/logging_test_$$"
log_preinit_dirs "$test_dir" 2>/dev/null
LOG_BASE_DIR="$test_dir"
LOG_MAIN_FILE="$test_dir/main.log"
_LOG_INITIALIZED=0
_LOG_FALLBACK_STDERR=0

log_init "FAILOVER_TEST" "main"
chmod 000 "$test_dir/main.log" 2>/dev/null

stderr_output=$(log_info "failover message" 2>&1)
chmod 644 "$test_dir/main.log" 2>/dev/null

if echo "$stderr_output" | grep -q "failover message"; then
    pass "Message written to stderr on first write failure"
else
    fail "BUG: Message lost on first write failure (not written to stderr)"
fi
rm -rf "$test_dir" 2>/dev/null

# Test 13: Legacy function writes with correct component
echo "=== TEST: Legacy function component names ==="
_LOG_INITIALIZED=0
LOG_BASE_DIR="/nonexistent"
LOG_BOOT_FILE="/nonexistent/boot.log"
_LOG_FALLBACK_STDERR=1

stderr_output=$(log_keybox "legacy test" 2>&1)
if echo "$stderr_output" | grep -q '\[KEYBOX\]'; then
    pass "log_keybox uses KEYBOX component"
else
    fail "log_keybox did not use KEYBOX component: $stderr_output"
fi

stderr_output=$(log_boot "boot test" 2>&1)
if echo "$stderr_output" | grep -q '\[BOOT\]'; then
    pass "log_boot uses BOOT component"
else
    fail "log_boot did not use BOOT component"
fi

# Test 14: MODPATH fallback (when MODPATH not set)
echo "=== TEST: Works without MODPATH ==="
unset MODPATH 2>/dev/null
_LOG_INITIALIZED=0
LOG_BASE_DIR="/nonexistent"
if . "$SCRIPT_DIR/logging.sh" 2>/dev/null; then
    pass "logging.sh works without MODPATH set"
else
    fail "logging.sh requires MODPATH"
fi

# Summary
echo ""
echo "=========================================="
echo "SUMMARY: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "=========================================="

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
