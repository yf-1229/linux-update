#!/usr/bin/env bash
# brew/tests/test_logbrew.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$ROOT_DIR/logbrew"

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
    pass "logbrew is present and executable"
else
    fail "Script is missing or not executable: $SCRIPT"
fi
assert_exit "logbrew --help exits 0" 0 bash "$SCRIPT" --help
assert_exit "unsupported subcommand exits 1" 1 bash "$SCRIPT" outdated

MOCK_BIN_DIR="$(mktemp -d)"
TMP_LOG_DIR="$(mktemp -d)"
trap 'rm -rf "$MOCK_BIN_DIR" "$TMP_LOG_DIR"' EXIT

cat > "$MOCK_BIN_DIR/brew" <<'EOF'
#!/usr/bin/env bash
echo "MOCK brew $*"
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/brew"

cat > "$MOCK_BIN_DIR/mock-summary" <<'EOF'
#!/usr/bin/env bash
if [ "$#" -ne 3 ]; then
    exit 1
fi
echo "summary-for-$3"
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/mock-summary"

echo "=== Test: brew update/upgrade/install support ==="
assert_exit "logbrew update exits 0" 0 \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGBREW_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" update
assert_output_contains "logbrew update runs brew update" "MOCK brew update" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGBREW_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" update
assert_output_contains "logbrew upgrade runs brew upgrade" "MOCK brew upgrade" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGBREW_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" upgrade
assert_output_contains "logbrew install runs brew install" "MOCK brew install curl" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGBREW_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" install curl
assert_output_contains "logbrew install forwards multiple packages" "MOCK brew install curl git" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGBREW_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" install curl git
assert_output_contains "logbrew prints log file location" "\[logbrew\] log:" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGBREW_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" update
assert_output_contains "logbrew can show scrollable summary UI" "logbrew install package summary" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGBREW_LOG_DIR="$TMP_LOG_DIR" LOGBREW_SCROLL_UI=1 PAGER=cat bash "$SCRIPT" install curl
assert_output_contains "logbrew uses summary command hook" "summary-for-curl" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGBREW_LOG_DIR="$TMP_LOG_DIR" LOGBREW_SCROLL_UI=1 LOGBREW_SUMMARY_CMD=mock-summary PAGER=cat bash "$SCRIPT" install curl

echo
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
