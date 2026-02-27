#!/usr/bin/env bash
# tests/test_apt_update_notifier.sh
#
# Unit / integration tests for apt-update-notifier.sh.
# Run with:  bash tests/test_apt_update_notifier.sh
#
# Exit code: 0 = all tests passed, 1 = one or more failures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$ROOT_DIR/apt-update-notifier.sh"

PASS=0
FAIL=0

# --------------------------------------------------------------------------- #
# Test harness helpers
# --------------------------------------------------------------------------- #
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

assert_output_not_contains() {
    local description="$1" pattern="$2"
    shift 2
    local output
    output=$("$@" 2>&1) || true
    if echo "$output" | grep -q "$pattern"; then
        fail "$description (pattern '$pattern' unexpectedly found in output)"
    else
        pass "$description"
    fi
}

# --------------------------------------------------------------------------- #
# Test 1 – Script exists and is executable
# --------------------------------------------------------------------------- #
echo "=== Test: script existence ==="
if [ -x "$SCRIPT" ]; then
    pass "Script is present and executable"
else
    fail "Script is missing or not executable: $SCRIPT"
fi

# --------------------------------------------------------------------------- #
# Test 2 – Help flag exits cleanly and contains expected text
# --------------------------------------------------------------------------- #
echo "=== Test: --help flag ==="
assert_exit "--help exits 0"                          0  bash "$SCRIPT" --help
assert_output_contains "--help mentions -n"           "\-n"  bash "$SCRIPT" --help
assert_output_contains "--help mentions --desktop"    "\-d"  bash "$SCRIPT" --help
assert_output_contains "--help mentions --lines"      "\-l"  bash "$SCRIPT" --help

# --------------------------------------------------------------------------- #
# Test 3 – Unknown option exits non-zero
# --------------------------------------------------------------------------- #
echo "=== Test: unknown option ==="
assert_exit "unknown option exits non-zero" 1 bash "$SCRIPT" --this-option-does-not-exist

# --------------------------------------------------------------------------- #
# Test 4 – --no-update flag skips apt-get update (no root needed)
# --------------------------------------------------------------------------- #
echo "=== Test: --no-update flag ==="

# We mock apt and apt-get so the test can run without sudo / a real apt.
MOCK_BIN_DIR="$(mktemp -d)"
trap 'rm -rf "$MOCK_BIN_DIR"' EXIT

# Mock apt-get: does nothing (no update, no changelog fetch)
cat > "$MOCK_BIN_DIR/apt-get" <<'EOF'
#!/usr/bin/env bash
# If called as "apt-get changelog <pkg>" output a minimal fake changelog.
if [ "${1:-}" = "changelog" ]; then
    pkg="${2:-unknown}"
    printf "%s (1.0-2) unstable; urgency=medium\n\n  * Fake changelog entry for %s\n\n -- Test User <test@example.com>  Mon, 01 Jan 2024 00:00:00 +0000\n" "$pkg" "$pkg"
    exit 0
fi
# update / other sub-commands: succeed silently
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/apt-get"

# Mock apt: returns a couple of fake upgradable packages
cat > "$MOCK_BIN_DIR/apt" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "list" ] && [ "${2:-}" = "--upgradable" ]; then
    echo "Listing... Done"
    echo "bash/focal-updates 5.1-6ubuntu1 amd64 [upgradable from: 5.1-6ubuntu0]"
    echo "curl/focal-updates 7.81.0-1ubuntu1 amd64 [upgradable from: 7.68.0-1ubuntu2]"
fi
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/apt"

export PATH="$MOCK_BIN_DIR:$PATH"

assert_exit   "--no-update exits 0 with mock packages"     0  bash "$SCRIPT" --no-update
assert_output_contains "--no-update lists bash"            "bash"  bash "$SCRIPT" --no-update
assert_output_contains "--no-update lists curl"            "curl"  bash "$SCRIPT" --no-update
assert_output_contains "--no-update shows changelog entry" "Fake changelog entry" bash "$SCRIPT" --no-update
assert_output_not_contains "--no-update skips apt-get update" "Refreshing package lists" bash "$SCRIPT" --no-update

# --------------------------------------------------------------------------- #
# Test 5 – --lines flag is respected (limits changelog output)
# --------------------------------------------------------------------------- #
echo "=== Test: --lines flag ==="
# With --lines 1 we should see at most 1 line of changelog per package
output=$(bash "$SCRIPT" --no-update --lines 1 2>&1)
# The fake changelog has 6 lines per package; with --lines 1 we should NOT see
# the trailer line that contains the maintainer email
assert_output_not_contains "--lines 1 truncates changelog" "test@example.com" \
    bash "$SCRIPT" --no-update --lines 1

# --------------------------------------------------------------------------- #
# Test 6 – No upgradable packages: exits 0 and reports up-to-date
# --------------------------------------------------------------------------- #
echo "=== Test: no upgradable packages ==="

# Replace mock apt with one that returns nothing upgradable
cat > "$MOCK_BIN_DIR/apt" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "list" ] && [ "${2:-}" = "--upgradable" ]; then
    echo "Listing... Done"
fi
exit 0
EOF

assert_exit   "exits 0 when nothing to upgrade"   0  bash "$SCRIPT" --no-update
assert_output_contains "reports up-to-date"       "up to date"  bash "$SCRIPT" --no-update

# --------------------------------------------------------------------------- #
# Summary
# --------------------------------------------------------------------------- #
echo
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
