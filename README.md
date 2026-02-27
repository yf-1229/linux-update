# linux-update

`update-notifier` — A Linux shell script that detects upgradable packages,
fetches their latest changelogs from the web, and presents a human-readable
summary so you know exactly what is changing before you upgrade.

Supports **apt** (Debian/Ubuntu), **dnf** (Fedora/RHEL 8+/CentOS Stream), and
**yum** (CentOS 7/older RHEL) — the package manager is detected automatically.

---

## Features

- Auto-detects the system package manager (apt, dnf, or yum)
- Refreshes package metadata before scanning
- Detects all upgradable packages
- Downloads the official changelog for each package from the internet
- Extracts and displays only the **latest** changelog entry per package
- Optionally sends a desktop notification via `notify-send`
- Colour-coded terminal output; colours are suppressed when stdout is not a TTY
- **Shell hooks** (`shell-hooks.sh`) that automatically show the summary after
  any `apt update`, `dnf update`, `yum update`, etc. command

---

## Requirements

| Tool | Purpose | Required? |
|------|---------|-----------|
| `apt-get` / `dnf` / `yum` | Package management | **Yes** (one of) |
| Network access | Download changelogs | Yes (for changelog fetch) |
| `dnf-plugins-core` | `dnf changelog` sub-command | Optional (dnf systems) |
| `yum-plugin-changelog` | `yum changelog` sub-command | Optional (yum systems) |
| `notify-send` | Desktop notification | Optional (`--desktop` only) |

---

## Installation

```bash
git clone https://github.com/yf-1229/linux-update.git
cd linux-update
chmod +x update-notifier.sh
sudo cp update-notifier.sh /usr/local/bin/update-notifier
```

The old `apt-update-notifier.sh` still works as a backward-compatible wrapper.

---

## Usage

```
sudo update-notifier.sh [OPTIONS]

Options:
  -n, --no-update      Skip refreshing package metadata
  -d, --desktop        Send a desktop notification via notify-send
  -l, --lines <N>      Number of changelog lines to show per package (default: 20)
  -h, --help           Show this help message
```

### Examples

```bash
# Full run: refresh package lists then show changelogs
sudo update-notifier.sh

# Use cached package lists (no network refresh, no root needed)
update-notifier.sh --no-update

# Also send a desktop notification
sudo update-notifier.sh --desktop

# Show only the first 10 lines of each changelog
sudo update-notifier.sh --lines 10
```

### Sample output

```
[INFO]  Detected package manager: apt
[INFO]  Refreshing package lists ...
[OK]    Package metadata refreshed.
[INFO]  Collecting upgradable packages ...
[OK]    Found 2 upgradable package(s): bash curl

------------------------------------------
Package: curl
------------------------------------------
curl (7.81.0-1ubuntu1.7) focal-updates; urgency=medium

  * SECURITY UPDATE: fix for CVE-2023-XXXXX ...

 -- Ubuntu Developers <ubuntu-devel@lists.ubuntu.com>  Fri, 01 Sep 2023 ...

=== Done ===
```

---

## Automatic display after update commands (shell hooks)

Source `shell-hooks.sh` in your shell configuration to automatically run the
notifier every time you run a package manager update command:

```bash
# Add to ~/.bashrc or ~/.zshrc
source /path/to/linux-update/shell-hooks.sh
```

After sourcing, the notifier runs automatically on success of:

| Command | Trigger |
|---------|---------|
| `apt update` / `apt upgrade` | yes |
| `apt-get update` / `apt-get upgrade` | yes |
| `dnf update` / `dnf upgrade` / `dnf check-update` | yes |
| `yum update` / `yum upgrade` / `yum check-update` | yes |

The notifier is called with `--no-update` so it uses already-refreshed metadata
without re-downloading. If the package manager command itself fails, the
notifier is **not** triggered.

You can override the path to the notifier binary:

```bash
export UPDATE_NOTIFIER_BIN=/path/to/update-notifier.sh
source /path/to/linux-update/shell-hooks.sh
```

---

## Running as a cron job

Add the following to root's crontab (`sudo crontab -e`) to run every morning
at 07:00 and log output:

```cron
0 7 * * * /usr/local/bin/update-notifier --desktop >> /var/log/update-notifier.log 2>&1
```

---

## Running the tests

```bash
bash tests/test_apt_update_notifier.sh
```

The test suite mocks all package managers (apt, dnf, yum) and requires no root
access or network connectivity.

---

## File overview

| File | Description |
|------|-------------|
| `update-notifier.sh` | Main script — multi-PM support (apt/dnf/yum) |
| `apt-update-notifier.sh` | Backward-compatible wrapper for `update-notifier.sh` |
| `shell-hooks.sh` | Shell functions for auto-run after update commands |
| `tests/test_apt_update_notifier.sh` | Test suite (31 tests) |

---

## License

MIT
