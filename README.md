# linux-update

`logapt` — A minimal wrapper for **apt** that runs only:
- `apt update`
- `apt install`

When `logapt` is executed, it outputs detailed command logs and also saves them.

---

## Features

- Supports **apt only**
- Single command name: `logapt`
- Supports only `update` and `install`
- Detailed logs are shown **only when `logapt` is run**
- Logs are also saved to `${LOGAPT_LOG_DIR:-$HOME/.logapt}`

---

## Requirements

| Tool | Purpose | Required? |
|------|---------|-----------|
| `apt` | Package management | **Yes** |

---

## Installation

```bash
git clone https://github.com/yf-1229/linux-update.git
cd linux-update
chmod +x logapt
sudo cp logapt /usr/local/bin/logapt
```

`update-notifier.sh` / `apt-update-notifier.sh` remain thin wrappers to `logapt`.

---

## Usage

```bash
logapt update
logapt install curl
```

### Examples

```bash
# show apt output with detailed log lines and save log file
LOGAPT_LOG_DIR=/tmp/logapt logapt update
```

---

## Running as a cron job

Add the following to root's crontab (`sudo crontab -e`) to run every morning
at 07:00 and log output:

```cron
0 7 * * * /usr/local/bin/logapt update >> /var/log/logapt.log 2>&1
```

---

## Running the tests

```bash
bash tests/test_apt_update_notifier.sh
```

The test suite mocks `apt` and requires no root access.

---

## File overview

| File | Description |
|------|-------------|
| `logapt` | Main script (apt-only, `update`/`install`) |
| `update-notifier.sh` | Compatibility wrapper for `logapt` |
| `apt-update-notifier.sh` | Compatibility wrapper for `logapt` |
| `tests/test_apt_update_notifier.sh` | Test suite |

---

## License

MIT
