#!/usr/bin/env bash
# apt/tests/test_logapt.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$ROOT_DIR/logapt"

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

cat > "$MOCK_BIN_DIR/mock-summary" <<'EOF'
#!/usr/bin/env bash
echo "summary-for-$3"
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/mock-summary"

echo "=== Test: apt update/install support ==="
assert_exit "logapt update exits 0" 0 \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGAPT_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" update
assert_output_contains "logapt update runs apt update" "MOCK apt update" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGAPT_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" update
assert_output_contains "logapt install runs apt install" "MOCK apt install curl" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGAPT_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" install curl
assert_output_contains "logapt install forwards multiple packages" "MOCK apt install curl git" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGAPT_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" install curl git
assert_output_contains "logapt prints log file location" "\[logapt\] log:" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGAPT_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" update
assert_output_contains "logapt can show scrollable summary UI" "logapt install package summary" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGAPT_LOG_DIR="$TMP_LOG_DIR" LOGAPT_SCROLL_UI=1 PAGER=cat bash "$SCRIPT" install curl
assert_output_contains "logapt uses summary command hook" "summary-for-curl" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGAPT_LOG_DIR="$TMP_LOG_DIR" LOGAPT_SCROLL_UI=1 LOGAPT_SUMMARY_CMD=mock-summary PAGER=cat bash "$SCRIPT" install curl

echo
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
