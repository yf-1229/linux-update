#!/usr/bin/env bash
# shell-hooks.sh
#
# Shell wrapper functions that automatically run update-notifier after package
# manager update / upgrade commands so you always see what changed.
#
# Usage – add ONE of the following lines to your ~/.bashrc or ~/.zshrc:
#
#   source /usr/local/share/update-notifier/shell-hooks.sh
#   source /path/to/update-notifier/shell-hooks.sh
#
# After sourcing, whenever you run any of these commands the notifier will
# print a changelog summary automatically on success:
#
#   apt update / apt upgrade
#   apt-get update / apt-get upgrade
#   dnf update / dnf upgrade / dnf check-update
#   yum update / yum upgrade / yum check-update
#
# Notes:
# - The notifier is run with --no-update so it uses already-refreshed metadata.
# - If the package manager command fails the notifier is NOT run.
# - Set UPDATE_NOTIFIER_BIN to override the path to update-notifier.sh.

# --------------------------------------------------------------------------- #
# Locate the notifier binary
# --------------------------------------------------------------------------- #
_update_notifier_find() {
    if [ -n "${UPDATE_NOTIFIER_BIN:-}" ] && [ -x "$UPDATE_NOTIFIER_BIN" ]; then
        echo "$UPDATE_NOTIFIER_BIN"
        return
    fi
    for candidate in \
            /usr/local/bin/update-notifier \
            /usr/local/bin/update-notifier.sh \
            "$(dirname "${BASH_SOURCE[0]}")/update-notifier.sh"; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return
        fi
    done
}

_update_notifier_run() {
    local bin
    bin="$(_update_notifier_find)"
    if [ -n "$bin" ]; then
        bash "$bin" --no-update || echo "[update-notifier] WARNING: notifier exited with errors" >&2
    fi
}

# --------------------------------------------------------------------------- #
# apt wrapper
# --------------------------------------------------------------------------- #
apt() {
    local subcmd="${1:-}"
    command apt "$@"
    local _exit=$?
    if [ $_exit -eq 0 ] && { [ "$subcmd" = "update" ] || [ "$subcmd" = "upgrade" ]; }; then
        _update_notifier_run
    fi
    return $_exit
}

# --------------------------------------------------------------------------- #
# apt-get wrapper
# --------------------------------------------------------------------------- #
apt-get() {
    local subcmd="${1:-}"
    command apt-get "$@"
    local _exit=$?
    if [ $_exit -eq 0 ] && { [ "$subcmd" = "update" ] || [ "$subcmd" = "upgrade" ]; }; then
        _update_notifier_run
    fi
    return $_exit
}

# --------------------------------------------------------------------------- #
# dnf wrapper
# --------------------------------------------------------------------------- #
dnf() {
    local subcmd="${1:-}"
    command dnf "$@"
    local _exit=$?
    if [ $_exit -eq 0 ] \
            && { [ "$subcmd" = "update" ] || [ "$subcmd" = "upgrade" ] \
                 || [ "$subcmd" = "check-update" ]; }; then
        _update_notifier_run
    fi
    return $_exit
}

# --------------------------------------------------------------------------- #
# yum wrapper
# --------------------------------------------------------------------------- #
yum() {
    local subcmd="${1:-}"
    command yum "$@"
    local _exit=$?
    if [ $_exit -eq 0 ] \
            && { [ "$subcmd" = "update" ] || [ "$subcmd" = "upgrade" ] \
                 || [ "$subcmd" = "check-update" ]; }; then
        _update_notifier_run
    fi
    return $_exit
}
