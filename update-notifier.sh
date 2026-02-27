#!/usr/bin/env bash
# update-notifier.sh
#
# Detects packages eligible for upgrade via the system package manager,
# fetches their latest changelogs from the web / package metadata,
# summarises the changes, and notifies the user.
#
# Supported package managers:
#   apt / apt-get   (Debian, Ubuntu, Linux Mint, …)
#   dnf             (Fedora, RHEL 8+, CentOS Stream, AlmaLinux, Rocky Linux, …)
#   yum             (CentOS 7, older RHEL, Amazon Linux 2, …)
#
# Usage:
#   sudo update-notifier.sh [OPTIONS]
#
# Options:
#   -n, --no-update      Skip refreshing package metadata
#   -d, --desktop        Send a desktop notification via notify-send
#   -l, --lines <N>      Number of changelog lines to show per package (default: 20)
#   -h, --help           Show this help message
#
# Requirements:
#   One of: apt-get, dnf, yum
#   notify-send (optional – needed only with --desktop)

set -euo pipefail

# --------------------------------------------------------------------------- #
# Defaults
# --------------------------------------------------------------------------- #
RUN_UPDATE=true
DESKTOP_NOTIFY=false
MAX_LINES=20

# --------------------------------------------------------------------------- #
# Colours (disabled when stdout is not a terminal)
# --------------------------------------------------------------------------- #
if [ -t 1 ]; then
    BOLD='\033[1m'
    GREEN='\033[0;32m'
    CYAN='\033[0;36m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    RESET='\033[0m'
else
    BOLD='' GREEN='' CYAN='' YELLOW='' RED='' RESET=''
fi

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
usage() {
    grep '^#' "$0" | grep -v '^#!' | grep -v '^# ---' | sed 's/^# \{0,1\}//' | head -23
    exit "${1:-0}"
}

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--no-update)   RUN_UPDATE=false; shift ;;
        -d|--desktop)     DESKTOP_NOTIFY=true; shift ;;
        -l|--lines)       MAX_LINES="${2:?'--lines requires a number'}"; shift 2 ;;
        -h|--help)        usage ;;
        *) error "Unknown option: $1"; usage 1 ;;
    esac
done

# --------------------------------------------------------------------------- #
# Package manager detection
# --------------------------------------------------------------------------- #
detect_pm() {
    if command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v yum &>/dev/null; then
        echo "yum"
    else
        echo ""
    fi
}

if [ -n "${UPDATE_NOTIFIER_PM+x}" ]; then
    PM="${UPDATE_NOTIFIER_PM}"
else
    PM="$(detect_pm)"
fi
if [ -z "$PM" ]; then
    error "No supported package manager found (apt-get, dnf, or yum required)."
    exit 1
fi

info "Detected package manager: $PM"

# --------------------------------------------------------------------------- #
# Step 1 – Refresh package metadata
# --------------------------------------------------------------------------- #
refresh_packages() {
    case "$PM" in
        apt)
            if [ "$EUID" -ne 0 ]; then
                warn "Not running as root; skipping 'apt-get update'."
                warn "Re-run with sudo to refresh package lists."
                return
            fi
            info "Refreshing package lists …"
            apt-get update -qq
            ;;
        dnf)
            if [ "$EUID" -ne 0 ]; then
                warn "Not running as root; skipping 'dnf makecache'."
                return
            fi
            info "Refreshing dnf metadata …"
            dnf makecache -q
            ;;
        yum)
            if [ "$EUID" -ne 0 ]; then
                warn "Not running as root; skipping 'yum makecache'."
                return
            fi
            info "Refreshing yum metadata …"
            yum makecache -q
            ;;
    esac
    success "Package metadata refreshed."
}

if [ "$RUN_UPDATE" = true ]; then
    refresh_packages
fi

# --------------------------------------------------------------------------- #
# Step 2 – Collect upgradable packages
# --------------------------------------------------------------------------- #
info "Collecting upgradable packages …"

list_upgradable() {
    case "$PM" in
        apt)
            apt list --upgradable 2>/dev/null \
                | grep -v '^Listing' \
                | awk -F'[/ ]' '{print $1}'
            ;;
        dnf)
            # dnf list --upgrades: first two lines are header/blank; columns are
            #   <name>.<arch>  <version>  <repo>
            dnf list --upgrades 2>/dev/null \
                | awk 'NR>1 && NF==3 {print $1}' \
                | sed 's/\.[^.]*$//'
            ;;
        yum)
            # yum list updates: skip header lines; package lines have arch suffix
            yum list updates 2>/dev/null \
                | awk 'NF==3 && $1 ~ /\.(x86_64|i686|noarch|aarch64|armv7hl|ppc64le|s390x)$/ {print $1}' \
                | sed 's/\.[^.]*$//'
            ;;
    esac
}

mapfile -t UPGRADABLE < <(list_upgradable)

if [ ${#UPGRADABLE[@]} -eq 0 ]; then
    success "All packages are up to date. Nothing to do."
    exit 0
fi

success "Found ${#UPGRADABLE[@]} upgradable package(s): ${UPGRADABLE[*]}"
echo

# --------------------------------------------------------------------------- #
# Step 3 – Fetch changelog for each package
# --------------------------------------------------------------------------- #

fetch_changelog_entry() {
    local pkg="$1"
    local tmpfile
    tmpfile="$(mktemp)"

    case "$PM" in
        apt)
            # apt-get changelog downloads the full changelog; extract first stanza
            if apt-get changelog "$pkg" 2>/dev/null > "$tmpfile"; then
                awk '/^ -- / { found_end=1 } { print } found_end { exit }' \
                    "$tmpfile" | head -n "$MAX_LINES"
            else
                echo "(Changelog not available for $pkg)"
            fi
            ;;
        dnf)
            # Prefer dnf changelog (from dnf-plugins-core)
            if dnf changelog "$pkg" 2>/dev/null > "$tmpfile" \
                    && [ -s "$tmpfile" ]; then
                head -n "$MAX_LINES" "$tmpfile"
            # Fallback: dnf updateinfo info
            elif dnf updateinfo info "$pkg" 2>/dev/null > "$tmpfile" \
                    && [ -s "$tmpfile" ]; then
                head -n "$MAX_LINES" "$tmpfile"
            # Last resort: rpm changelog for installed version
            elif rpm -q --changelog "$pkg" 2>/dev/null > "$tmpfile" \
                    && [ -s "$tmpfile" ]; then
                head -n "$MAX_LINES" "$tmpfile"
            else
                echo "(Changelog not available for $pkg)"
            fi
            ;;
        yum)
            # Prefer yum changelog (from yum-plugin-changelog)
            if yum changelog "$pkg" 2>/dev/null > "$tmpfile" \
                    && [ -s "$tmpfile" ]; then
                head -n "$MAX_LINES" "$tmpfile"
            # Fallback: rpm changelog
            elif rpm -q --changelog "$pkg" 2>/dev/null > "$tmpfile" \
                    && [ -s "$tmpfile" ]; then
                head -n "$MAX_LINES" "$tmpfile"
            else
                echo "(Changelog not available for $pkg)"
            fi
            ;;
    esac

    rm -f "$tmpfile"
}

# --------------------------------------------------------------------------- #
# Step 4 – Build and print the summary
# --------------------------------------------------------------------------- #
echo -e "${BOLD}=== update-notifier summary – $(date '+%Y-%m-%d %H:%M:%S') ===${RESET}"
echo -e "Package manager: ${GREEN}${PM}${RESET}"
echo -e "Upgradable packages (${#UPGRADABLE[@]}): ${UPGRADABLE[*]}"
echo

for pkg in "${UPGRADABLE[@]}"; do
    echo -e "${BOLD}──────────────────────────────────────────${RESET}"
    echo -e "${BOLD}Package: ${GREEN}${pkg}${RESET}"
    echo -e "${BOLD}──────────────────────────────────────────${RESET}"

    changelog=$(fetch_changelog_entry "$pkg")
    echo "$changelog"
    echo
done

# --------------------------------------------------------------------------- #
# Step 5 – Desktop notification (optional)
# --------------------------------------------------------------------------- #
if [ "$DESKTOP_NOTIFY" = true ]; then
    if ! command -v notify-send &>/dev/null; then
        warn "'notify-send' not found; skipping desktop notification."
    else
        NOTIFY_BODY="$(printf '%d package(s) have updates available:\n%s' \
            "${#UPGRADABLE[@]}" "${UPGRADABLE[*]}")"
        notify-send \
            --urgency=normal \
            --icon=software-update-available \
            "Updates Available ($PM)" \
            "$NOTIFY_BODY"
        success "Desktop notification sent."
    fi
fi

echo -e "${BOLD}=== Done ===${RESET}"
