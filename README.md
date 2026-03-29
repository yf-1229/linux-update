# linux-update

Minimal logging wrappers for popular package managers — **apt**, **yum**, **brew**, and **pacman**.

Each wrapper runs the underlying package manager, prints timestamped log lines to the terminal, and saves a log file.  
By adding a shell alias you can make even the plain `apt update` (or `brew update`, etc.) go through the wrapper automatically.

---

## Supported package managers

| Directory | Script | Package manager | Platforms |
|-----------|--------|-----------------|-----------|
| `apt/` | `logapt` | apt | Debian, Ubuntu, … |
| `yum/` | `logyum` | yum | RHEL, CentOS, Fedora, … |
| `brew/` | `logbrew` | Homebrew | macOS, Linux |
| `pacman/` | `logpacman` | pacman | Arch Linux, Manjaro, … |

---

## Features

- One script per package manager, each in its own directory
- Supported subcommands per wrapper:
  - `logapt`   — `update`, `install`
  - `logyum`   — `update`, `install`
  - `logbrew`  — `update`, `upgrade`, `install`
  - `logpacman`— `update` (→ `pacman -Syu`), `install` (→ `pacman -S`)
- Detailed logs are shown on the terminal **and** saved to a file
- `update` fetches per-package change details (version diff + short description) and prints summarized list
- `update` can show a GUI checklist (zenity) and lets you exclude packages from future update lists
- Log directory is configurable via environment variable (e.g. `LOGAPT_LOG_DIR`)

---

## Installation

Clone the repository and install the script(s) you need:

```bash
git clone https://github.com/yf-1229/linux-update.git
cd linux-update
```

### apt (Debian/Ubuntu)

```bash
chmod +x apt/logapt
sudo cp apt/logapt /usr/local/bin/logapt
```

### yum (RHEL/CentOS/Fedora)

```bash
chmod +x yum/logyum
sudo cp yum/logyum /usr/local/bin/logyum
```

### brew (Homebrew)

```bash
chmod +x brew/logbrew
sudo cp brew/logbrew /usr/local/bin/logbrew
```

### pacman (Arch Linux)

```bash
chmod +x pacman/logpacman
sudo cp pacman/logpacman /usr/local/bin/logpacman
```

---

## Usage

```bash
# apt
logapt update
logapt install curl

# yum
logyum update
logyum install curl

# brew
logbrew update
logbrew upgrade
logbrew install curl

# pacman
logpacman update          # runs: pacman -Syu
logpacman install curl    # runs: pacman -S curl
```

Override the log directory:

```bash
LOGAPT_LOG_DIR=/tmp/logapt logapt update
LOGYUM_LOG_DIR=/tmp/logyum logyum update
LOGBREW_LOG_DIR=/tmp/logbrew logbrew update
LOGPACMAN_LOG_DIR=/tmp/logpacman logpacman update
```

Exclude-file / GUI settings:

```bash
# apt
LOGAPT_EXCLUDE_FILE=/tmp/logapt-exclude.txt logapt update
LOGAPT_GUI=0 logapt update   # disable GUI, terminal summary only

# pacman
LOGPACMAN_EXCLUDE_FILE=/tmp/logpacman-exclude.txt logpacman update
LOGPACMAN_GUI=0 logpacman update
```

---

## Shell integration — run the wrapper automatically

By adding an alias to your shell config, the regular package manager command (e.g. `apt update`) will automatically go through the logging wrapper.

### bash (`~/.bashrc`)

```bash
# apt
alias apt='logapt'

# yum
alias yum='logyum'

# brew
alias brew='logbrew'

# pacman
alias pacman='logpacman'
```

Reload: `source ~/.bashrc`

### zsh (`~/.zshrc`)

```zsh
# apt
alias apt='logapt'

# yum
alias yum='logyum'

# brew
alias brew='logbrew'

# pacman
alias pacman='logpacman'
```

Reload: `source ~/.zshrc`

### fish (`~/.config/fish/config.fish`)

```fish
# apt
alias apt='logapt'

# yum
alias yum='logyum'

# brew
alias brew='logbrew'

# pacman
alias pacman='logpacman'
```

Reload: `source ~/.config/fish/config.fish`

> **Note:** After setting an alias, `apt update` will call `logapt update` transparently — you will see the timestamped log output and a saved log file every time.

---

## Running as a cron job

```cron
# apt — every morning at 07:00
0 7 * * * /usr/local/bin/logapt update >> /var/log/logapt.log 2>&1

# yum — every morning at 07:00
0 7 * * * /usr/local/bin/logyum update >> /var/log/logyum.log 2>&1

# brew — every morning at 07:00
0 7 * * * /usr/local/bin/logbrew update >> /var/log/logbrew.log 2>&1

# pacman — every morning at 07:00
0 7 * * * /usr/local/bin/logpacman update >> /var/log/logpacman.log 2>&1
```

---

## Running the tests

Each package manager has its own test suite that mocks the underlying command and requires no root access.

```bash
bash apt/tests/test_logapt.sh
bash yum/tests/test_logyum.sh
bash brew/tests/test_logbrew.sh
bash pacman/tests/test_logpacman.sh

```

---

## Repository structure

```
linux-update/
├── apt/
│   ├── logapt                      # apt wrapper
│   └── tests/
│       └── test_logapt.sh
├── yum/
│   ├── logyum                      # yum wrapper
│   └── tests/
│       └── test_logyum.sh
├── brew/
│   ├── logbrew                     # Homebrew wrapper
│   └── tests/
│       └── test_logbrew.sh
├── pacman/
│   ├── logpacman                   # pacman wrapper
│   └── tests/
│       └── test_logpacman.sh
└── tests/
```

---

## License

MIT
