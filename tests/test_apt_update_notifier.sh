#!/usr/bin/env bash
# tests/test_apt_update_notifier.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$ROOT_DIR/logapt"
UPDATE_WRAPPER="$ROOT_DIR/update-notifier.sh"
APT_WRAPPER="$ROOT_DIR/apt-update-notifier.sh"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; ((PASS++)) || true; }
fail() { echo "  FAIL: $1"; ((FAIL++)) || true; }

assert_exit() {
    local description="$1" expected_code="$2"
    shift 2
    local actual_code=0
    "$@" &>/dev/null || actual_code=$?
    if [ "$actual_code" -eq "$expected_code" ]; then
        pass "$description"
    else
        fail "$description (expected exit $expected_code, got $actual_code)"
    fi
}

assert_output_contains() {
    local description="$1" pattern="$2"
    shift 2
    local output
    output=$("$@" 2>&1) || true
    if echo "$output" | grep -q "$pattern"; then
        pass "$description"
    else
        fail "$description (pattern '$pattern' not found in output)"
    fi
}

echo "=== Test: script existence ==="
if [ -x "$SCRIPT" ]; then
    pass "logapt is present and executable"
else
    fail "Script is missing or not executable: $SCRIPT"
fi
assert_exit "logapt --help exits 0" 0 bash "$SCRIPT" --help
assert_exit "unsupported subcommand exits 1" 1 bash "$SCRIPT" upgrade

MOCK_BIN_DIR="$(mktemp -d)"
TMP_LOG_DIR="$(mktemp -d)"
trap 'rm -rf "$MOCK_BIN_DIR" "$TMP_LOG_DIR"' EXIT

cat > "$MOCK_BIN_DIR/apt" <<'EOF'
#!/usr/bin/env bash
echo "MOCK apt $*"
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/apt"

echo "=== Test: apt update/install support ==="
assert_exit "logapt update exits 0" 0 env PATH="$MOCK_BIN_DIR:$PATH" LOGAPT_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" update
assert_output_contains "logapt update runs apt update" "MOCK apt update" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGAPT_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" update
assert_output_contains "logapt install runs apt install" "MOCK apt install curl" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGAPT_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" install curl
assert_output_contains "logapt prints log file location" "\\[logapt\\] log:" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGAPT_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" update

echo "=== Test: wrappers forward to logapt ==="
assert_output_contains "update-notifier.sh wrapper forwards to logapt help" "logapt update" \
    bash "$UPDATE_WRAPPER" --help
assert_output_contains "apt-update-notifier.sh wrapper forwards to logapt help" "logapt update" \
    bash "$APT_WRAPPER" --help

echo
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
