#!/usr/bin/env bash
# pacman/tests/test_logpacman.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$ROOT_DIR/logpacman"

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
    pass "logpacman is present and executable"
else
    fail "Script is missing or not executable: $SCRIPT"
fi
assert_exit "logpacman --help exits 0" 0 bash "$SCRIPT" --help
assert_exit "unsupported subcommand exits 1" 1 bash "$SCRIPT" remove

MOCK_BIN_DIR="$(mktemp -d)"
TMP_LOG_DIR="$(mktemp -d)"
trap 'rm -rf "$MOCK_BIN_DIR" "$TMP_LOG_DIR"' EXIT

cat > "$MOCK_BIN_DIR/pacman" <<'EOF'
#!/usr/bin/env bash
echo "MOCK pacman $*"
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/pacman"

cat > "$MOCK_BIN_DIR/mock-summary" <<'EOF'
#!/usr/bin/env bash
if [ "$#" -ne 3 ]; then
    exit 1
fi
echo "summary-for-$3"
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/mock-summary"

echo "=== Test: pacman update/install support ==="
assert_exit "logpacman update exits 0" 0 \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGPACMAN_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" update
assert_output_contains "logpacman update runs pacman -Syu" "MOCK pacman -Syu" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGPACMAN_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" update
assert_output_contains "logpacman install runs pacman -S" "MOCK pacman -S curl" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGPACMAN_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" install curl
assert_output_contains "logpacman install forwards multiple packages" "MOCK pacman -S curl git" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGPACMAN_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" install curl git
assert_output_contains "logpacman prints log file location" "\[logpacman\] log:" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGPACMAN_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" update
assert_output_contains "logpacman can show scrollable summary UI" "logpacman install package summary" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGPACMAN_LOG_DIR="$TMP_LOG_DIR" LOGPACMAN_SCROLL_UI=1 PAGER=cat bash "$SCRIPT" install curl
assert_output_contains "logpacman uses summary command hook" "summary-for-curl" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGPACMAN_LOG_DIR="$TMP_LOG_DIR" LOGPACMAN_SCROLL_UI=1 LOGPACMAN_SUMMARY_CMD=mock-summary PAGER=cat bash "$SCRIPT" install curl

echo
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
