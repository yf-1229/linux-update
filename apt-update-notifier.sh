#!/usr/bin/env bash
# apt-update-notifier.sh
#
# Detects packages eligible for upgrade via apt, fetches their changelogs
# from the web, summarises the latest changes, and notifies the user.
#
# Usage:
#   sudo apt-update-notifier.sh [OPTIONS]
#
# Options:
#   -n, --no-update      Skip running 'apt-get update' (use cached lists)
#   -d, --desktop        Send a desktop notification via notify-send
#   -l, --lines <N>      Number of changelog lines to show per package (default: 20)
#   -h, --help           Show this help message
#
# Requirements:
#   apt-get, curl or wget (optional – used as fallback for changelog fetching)
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
    grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -20
    exit "${1:-0}"
}

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        error "'$cmd' is not installed. Please install it and try again."
        exit 1
    fi
}

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
# Prerequisites
# --------------------------------------------------------------------------- #
require_cmd apt-get
require_cmd apt

# --------------------------------------------------------------------------- #
# Step 1 – Refresh package lists
# --------------------------------------------------------------------------- #
if [ "$RUN_UPDATE" = true ]; then
    if [ "$EUID" -ne 0 ]; then
        warn "Not running as root; skipping 'apt-get update'. Use -n to suppress this warning."
        warn "Re-run with sudo to refresh package lists."
        RUN_UPDATE=false
    else
        info "Refreshing package lists …"
        apt-get update -qq
        success "Package lists refreshed."
    fi
fi

# --------------------------------------------------------------------------- #
# Step 2 – Collect upgradable packages
# --------------------------------------------------------------------------- #
info "Collecting upgradable packages …"

mapfile -t UPGRADABLE < <(
    apt list --upgradable 2>/dev/null \
    | grep -v '^Listing' \
    | awk -F'[/ ]' '{print $1}'
)

if [ ${#UPGRADABLE[@]} -eq 0 ]; then
    success "All packages are up to date. Nothing to do."
    exit 0
fi

success "Found ${#UPGRADABLE[@]} upgradable package(s): ${UPGRADABLE[*]}"
echo

# --------------------------------------------------------------------------- #
# Step 3 – Fetch changelog for each package and extract the latest entry
# --------------------------------------------------------------------------- #

# Returns the first changelog entry (up to MAX_LINES lines) for a package.
# Uses 'apt-get changelog' which downloads the full changelog from the internet.
fetch_changelog_entry() {
    local pkg="$1"
    local tmpfile
    tmpfile="$(mktemp)"

    # apt-get changelog streams the full changelog to stdout.
    # We capture it and extract only the first stanza (newest release).
    if apt-get changelog "$pkg" 2>/dev/null > "$tmpfile"; then
        # A Debian changelog stanza starts with the package name and ends
        # with a line like " -- Maintainer <email>  <date>"
        awk '
            /^ -- / { found_end=1 }
            { print }
            found_end { exit }
        ' "$tmpfile" | head -n "$MAX_LINES"
    else
        echo "(Changelog not available for $pkg)"
    fi

    rm -f "$tmpfile"
}

# --------------------------------------------------------------------------- #
# Step 4 – Build the summary
# --------------------------------------------------------------------------- #
SUMMARY_LINES=()
SUMMARY_LINES+=("$(echo -e "${BOLD}=== apt upgrade summary – $(date '+%Y-%m-%d %H:%M:%S') ===${RESET}")")
SUMMARY_LINES+=("")
SUMMARY_LINES+=("Upgradable packages (${#UPGRADABLE[@]}): ${UPGRADABLE[*]}")
SUMMARY_LINES+=("")

for pkg in "${UPGRADABLE[@]}"; do
    echo -e "${BOLD}──────────────────────────────────────────${RESET}"
    echo -e "${BOLD}Package: ${GREEN}${pkg}${RESET}"
    echo -e "${BOLD}──────────────────────────────────────────${RESET}"

    changelog=$(fetch_changelog_entry "$pkg")
    echo "$changelog"
    echo

    SUMMARY_LINES+=("### $pkg")
    SUMMARY_LINES+=("$changelog")
    SUMMARY_LINES+=("")
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
            "apt: Updates Available" \
            "$NOTIFY_BODY"
        success "Desktop notification sent."
    fi
fi

echo -e "${BOLD}=== Done ===${RESET}"
