# linux-update

`apt-update-notifier` — A Linux shell script that detects upgradable apt packages,
fetches their latest changelogs from the web, and presents a human-readable
summary so you know exactly what is changing before you run `apt upgrade`.

---

## Features

- Runs `apt-get update` to refresh package lists (requires root)
- Detects all upgradable packages via `apt list --upgradable`
- Downloads the official Debian/Ubuntu changelog for each package using
  `apt-get changelog` (network access required)
- Extracts and displays the **latest** changelog entry per package
- Optionally sends a desktop notification via `notify-send`
- Colour-coded terminal output; colours are suppressed when stdout is not a TTY

---

## Requirements

| Tool | Purpose | Required? |
|------|---------|-----------|
| `apt` / `apt-get` | Package management | **Yes** |
| Network access | Download changelogs | Yes (for changelog fetch) |
| `notify-send` | Desktop notification | Optional (`--desktop` only) |

Tested on Ubuntu 20.04 LTS and later.

---

## Installation

```bash
git clone https://github.com/yf-1229/linux-update.git
cd linux-update
chmod +x apt-update-notifier.sh
sudo cp apt-update-notifier.sh /usr/local/bin/apt-update-notifier
```

---

## Usage

```
sudo apt-update-notifier [OPTIONS]

Options:
  -n, --no-update      Skip running 'apt-get update' (use cached lists)
  -d, --desktop        Send a desktop notification via notify-send
  -l, --lines <N>      Number of changelog lines to show per package (default: 20)
  -h, --help           Show this help message
```

### Examples

```bash
# Full run: refresh package lists then show changelogs
sudo apt-update-notifier

# Use cached package lists (no network refresh, no root needed)
apt-update-notifier --no-update

# Also send a desktop notification
sudo apt-update-notifier --desktop

# Show only the first 10 lines of each changelog
sudo apt-update-notifier --lines 10
```

### Sample output

```
[INFO]  Refreshing package lists …
[OK]    Package lists refreshed.
[INFO]  Collecting upgradable packages …
[OK]    Found 2 upgradable package(s): bash curl

──────────────────────────────────────────
Package: bash
──────────────────────────────────────────
bash (5.1-6ubuntu1) focal-updates; urgency=medium

  * Backport upstream patch to fix CVE-2022-3715

 -- Ubuntu Developers <ubuntu-devel@lists.ubuntu.com>  Mon, 26 Dec 2022 ...

──────────────────────────────────────────
Package: curl
──────────────────────────────────────────
curl (7.81.0-1ubuntu1.7) focal-updates; urgency=medium

  * SECURITY UPDATE: ...

=== Done ===
```

---

## Running as a cron job

Add the following line to root's crontab (`sudo crontab -e`) to run every
morning at 07:00 and log output:

```cron
0 7 * * * /usr/local/bin/apt-update-notifier --desktop >> /var/log/apt-update-notifier.log 2>&1
```

---

## Running the tests

```bash
bash tests/test_apt_update_notifier.sh
```

The test suite mocks `apt` and `apt-get` so it does **not** require root or
network access.

---

## License

MIT
