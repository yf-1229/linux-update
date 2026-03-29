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
if [ "$1" = "show" ]; then
echo "Description: ${2} package description"
exit 0
fi
if [ "$1" = "list" ] && [ "$2" = "--upgradable" ]; then
echo "Listing..."
echo "curl/stable 8.0 amd64 [upgradable from: 7.0]"
echo "git/stable 2.0 amd64 [upgradable from: 1.0]"
exit 0
fi
echo "MOCK apt $*"
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/apt"

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
assert_output_contains "logapt update shows summary count" "\[logapt\] update summary: 2 upgradable package(s)" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGAPT_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" update
assert_output_contains "logapt update shows summarized package names and change details" "\[logapt\]   - curl: 7.0 -> 8.0 | curl package description" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGAPT_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" update
assert_output_contains "logapt update prints exclude file path" "\[logapt\] exclude file:" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGAPT_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" update
assert_output_contains "logapt install keeps using apt install" "MOCK apt install curl" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGAPT_LOG_DIR="$TMP_LOG_DIR" bash "$SCRIPT" install curl

TMP_EXCLUDE_FILE="$(mktemp)"
echo "curl" > "$TMP_EXCLUDE_FILE"
assert_output_contains "logapt excluded package is omitted from summary list" "\[logapt\]   - git: 1.0 -> 2.0 | git package description" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGAPT_LOG_DIR="$TMP_LOG_DIR" LOGAPT_EXCLUDE_FILE="$TMP_EXCLUDE_FILE" LOGAPT_GUI=0 bash "$SCRIPT" update
assert_output_contains "logapt excluded package is not printed" "\[logapt\] update summary: 1 upgradable package(s)" \
    env PATH="$MOCK_BIN_DIR:$PATH" LOGAPT_LOG_DIR="$TMP_LOG_DIR" LOGAPT_EXCLUDE_FILE="$TMP_EXCLUDE_FILE" LOGAPT_GUI=0 bash "$SCRIPT" update
rm -f "$TMP_EXCLUDE_FILE"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
