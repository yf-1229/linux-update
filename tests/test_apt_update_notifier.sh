#!/usr/bin/env bash
# tests/test_apt_update_notifier.sh
#
# Unit / integration tests for update-notifier.sh (and the apt-update-notifier.sh wrapper).
# Run with:  bash tests/test_apt_update_notifier.sh
#
# Exit code: 0 = all tests passed, 1 = one or more failures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$ROOT_DIR/update-notifier.sh"
WRAPPER="$ROOT_DIR/apt-update-notifier.sh"

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
# Test 1 – Scripts exist and are executable
# --------------------------------------------------------------------------- #
echo "=== Test: script existence ==="
if [ -x "$SCRIPT" ]; then
    pass "update-notifier.sh is present and executable"
else
    fail "Script is missing or not executable: $SCRIPT"
fi
if [ -x "$WRAPPER" ]; then
    pass "apt-update-notifier.sh wrapper is present and executable"
else
    fail "Wrapper is missing or not executable: $WRAPPER"
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
# Test 7 – apt-update-notifier.sh wrapper forwards to update-notifier.sh
# --------------------------------------------------------------------------- #
echo "=== Test: apt-update-notifier.sh wrapper ==="
# Restore the mock apt with two upgradable packages for wrapper test
cat > "$MOCK_BIN_DIR/apt" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "list" ] && [ "${2:-}" = "--upgradable" ]; then
    echo "Listing... Done"
    echo "bash/focal-updates 5.1-6ubuntu1 amd64 [upgradable from: 5.1-6ubuntu0]"
fi
exit 0
EOF

assert_exit   "wrapper exits 0"                          0  bash "$WRAPPER" --no-update
assert_output_contains "wrapper forwards to main script" "update-notifier"  bash "$WRAPPER" --help

# --------------------------------------------------------------------------- #
# Test 8 – dnf-based system: detect PM and list upgradable packages
# --------------------------------------------------------------------------- #
echo "=== Test: dnf package manager ==="

DNF_MOCK_DIR="$(mktemp -d)"
trap 'rm -rf "$MOCK_BIN_DIR" "$DNF_MOCK_DIR"' EXIT

cat > "$DNF_MOCK_DIR/dnf" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    makecache) exit 0 ;;
    list)
        if [ "${2:-}" = "--upgrades" ]; then
            echo "Last metadata expiration check:"
            echo "Available Upgrades"
            echo "vim-enhanced.x86_64   2:9.0.1-1.fc38  updates"
            echo "curl.x86_64           7.85.0-1.fc38   updates"
        fi
        ;;
    changelog)
        pkg="${2:-unknown}"
        printf "* Mon Jan 01 2024 Test User <test@example.com> - 1.0-2\n- Fake dnf changelog for %s\n" "$pkg"
        ;;
    updateinfo) ;;
esac
exit 0
EOF
chmod +x "$DNF_MOCK_DIR/dnf"

# Force PM=dnf via env var; prepend mock dir so 'dnf' resolves to the mock
assert_exit   "dnf: exits 0 with mock packages" 0 \
    env UPDATE_NOTIFIER_PM=dnf PATH="$DNF_MOCK_DIR:$PATH" bash "$SCRIPT" --no-update
assert_output_contains "dnf: detects dnf PM" "dnf" \
    env UPDATE_NOTIFIER_PM=dnf PATH="$DNF_MOCK_DIR:$PATH" bash "$SCRIPT" --no-update
assert_output_contains "dnf: lists vim-enhanced" "vim-enhanced" \
    env UPDATE_NOTIFIER_PM=dnf PATH="$DNF_MOCK_DIR:$PATH" bash "$SCRIPT" --no-update
assert_output_contains "dnf: shows changelog entry" "Fake dnf changelog" \
    env UPDATE_NOTIFIER_PM=dnf PATH="$DNF_MOCK_DIR:$PATH" bash "$SCRIPT" --no-update

# --------------------------------------------------------------------------- #
# Test 9 – yum-based system: detect PM and list upgradable packages
# --------------------------------------------------------------------------- #
echo "=== Test: yum package manager ==="

YUM_MOCK_DIR="$(mktemp -d)"
trap 'rm -rf "$MOCK_BIN_DIR" "$DNF_MOCK_DIR" "$YUM_MOCK_DIR"' EXIT

cat > "$YUM_MOCK_DIR/yum" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    makecache) exit 0 ;;
    list)
        if [ "${2:-}" = "updates" ]; then
            echo "Updated Packages"
            echo "openssl.x86_64   1:1.1.1k-9.el7  updates"
            echo "bash.x86_64      4.2.46-35.el7   base"
        fi
        ;;
    changelog)
        pkg="${2:-unknown}"
        printf "* Mon Jan 01 2024 Test User <test@example.com> - 1.0-2\n- Fake yum changelog for %s\n" "$pkg"
        ;;
esac
exit 0
EOF
chmod +x "$YUM_MOCK_DIR/yum"

assert_exit   "yum: exits 0 with mock packages" 0 \
    env UPDATE_NOTIFIER_PM=yum PATH="$YUM_MOCK_DIR:$PATH" bash "$SCRIPT" --no-update
assert_output_contains "yum: detects yum PM" "yum" \
    env UPDATE_NOTIFIER_PM=yum PATH="$YUM_MOCK_DIR:$PATH" bash "$SCRIPT" --no-update
assert_output_contains "yum: lists openssl" "openssl" \
    env UPDATE_NOTIFIER_PM=yum PATH="$YUM_MOCK_DIR:$PATH" bash "$SCRIPT" --no-update

# --------------------------------------------------------------------------- #
# Test 10 – No package manager found: exits with error
# --------------------------------------------------------------------------- #
echo "=== Test: no package manager ==="
assert_exit   "exits non-zero when no PM found" 1 \
    env UPDATE_NOTIFIER_PM="" bash "$SCRIPT" --no-update
assert_output_contains "reports missing PM" "No supported package manager" \
    env UPDATE_NOTIFIER_PM="" bash "$SCRIPT" --no-update

# --------------------------------------------------------------------------- #
# Test 11 – shell-hooks.sh: sourcing defines wrapper functions
# --------------------------------------------------------------------------- #
echo "=== Test: shell-hooks.sh ==="
HOOKS="$ROOT_DIR/shell-hooks.sh"
if [ -f "$HOOKS" ]; then
    pass "shell-hooks.sh is present"
else
    fail "shell-hooks.sh is missing: $HOOKS"
fi

# Source hooks in a subshell and verify that the functions are defined
assert_output_contains "hooks define apt function"     "apt is a function" \
    bash -c "source '$HOOKS'; type apt"
assert_output_contains "hooks define apt-get function" "apt-get is a function" \
    bash -c "source '$HOOKS'; type apt-get"
assert_output_contains "hooks define dnf function"     "dnf is a function" \
    bash -c "source '$HOOKS'; type dnf"
assert_output_contains "hooks define yum function"     "yum is a function" \
    bash -c "source '$HOOKS'; type yum"

# --------------------------------------------------------------------------- #
# Summary
# --------------------------------------------------------------------------- #
echo
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
