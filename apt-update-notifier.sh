#!/usr/bin/env bash
# apt-update-notifier.sh
#
# Backward-compatible wrapper around update-notifier.sh.
# All options are forwarded as-is.
#
# For full documentation see update-notifier.sh or run:
#   update-notifier.sh --help

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/update-notifier.sh" "$@"
