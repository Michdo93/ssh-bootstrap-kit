#!/bin/sh
#
# SSH Bootstrap & Hardening Script for Debian-based Distributions
# Supports: Ubuntu, Debian, Kali Linux, Kali Purple, DietPi, Raspberry Pi OS
#
#   wget -qO- https://raw.githubusercontent.com/Michdo93/ssh-bootstrap-kit/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/Michdo93/ssh-bootstrap-kit/main/install.sh | sh
#
# Works with "| sh" and "| bash", as root or as a sudo user, with and without systemd
# (Docker/LXC). The whole script is wrapped in main() which is only called on the last
# line, so a piped script is read completely before anything runs; prompts read from
# /dev/tty and apt never sees the pipe.
#
# Non-interactive use (no terminal, or ASSUME_DEFAULTS=1): the values come from the
# environment, otherwise the defaults are used:
#   SSH_PORT=22  SSH_ROOT_LOGIN=no  SSH_PASS_AUTH=yes
#   wget -qO- .../install.sh | SSH_PORT=2222 SSH_PASS_AUTH=no sh

set -eu

main() {
    if [ -t 1 ]; then
        RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
    else
        RED=''; GREEN=''; YELLOW=''; NC=''
    fi

    # ---------- privileges: run as root, or prefix root commands with sudo ----------
    if [ "$(id -u)" -eq 0 ]; then
        SUDO=""
    elif command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
        info "Not running as root - administrative commands use sudo."
        if have_tty; then
            sudo -v </dev/tty || error "sudo authentication failed."
        else
            sudo -n true 2>/dev/null || error "sudo needs a password but no terminal is available."
        fi
    else
        error "This script must be run as root or with sudo privileges."
    fi

    # ---------- OS ----------
    [ -r /etc/os-release ] || error "Cannot detect operating system (/etc/os-release missing)."
    # shellcheck disable=SC1091
    . /etc/os-release
    case " ${ID:-} ${ID_LIKE:-} " in
        *" debian "*|*" ubuntu "*|*" kali "*|*" raspbian "*|*" dietpi "*) ;;
        *) command -v apt-get >/dev/null 2>&1 || error "Unsupported OS '${ID:-unknown}' (apt-get not found)."
           warn "OS '${ID:-unknown}' is not officially tested; continuing because apt-get exists." ;;
    esac
    info "Detected OS: ${PRETTY_NAME:-$ID}"

    # ---------- install ----------
    if [ -x /usr/sbin/sshd ]; then
        info "OpenSSH server is already installed."
    else
        info "Updating package lists and installing OpenSSH server..."
        $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -qq </dev/null
        $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openssh-server </dev/null >/dev/null
    fi

    if is_active dropbear; then
        warn "Dropbear is running (DietPi default) and may already use port 22."
        warn "Switch DietPi's SSH server with 'dietpi-software' if OpenSSH cannot bind its port."
    fi

    # ---------- questions ----------
    if have_tty && [ "${ASSUME_DEFAULTS:-0}" != 1 ]; then
        info "Please configure your SSH settings (press Enter for defaults):"
        SSH_PORT=$(ask "Enter SSH Port [Default: ${SSH_PORT:-22}]: " "${SSH_PORT:-22}")
        SSH_ROOT_LOGIN=$(ask_yes_no "Allow root login? (yes/no) [Default: ${SSH_ROOT_LOGIN:-no}]: " "${SSH_ROOT_LOGIN:-no}")
        SSH_PASS_AUTH=$(ask_yes_no "Allow password-based authentication? (yes/no) [Default: ${SSH_PASS_AUTH:-yes}]: " "${SSH_PASS_AUTH:-yes}")
    else
        info "No terminal - using SSH_PORT/SSH_ROOT_LOGIN/SSH_PASS_AUTH from the environment or defaults."
        SSH_PORT=${SSH_PORT:-22}
        SSH_ROOT_LOGIN=$(normalize_yes_no "${SSH_ROOT_LOGIN:-no}") || error "SSH_ROOT_LOGIN must be yes or no."
        SSH_PASS_AUTH=$(normalize_yes_no "${SSH_PASS_AUTH:-yes}") || error "SSH_PASS_AUTH must be yes or no."
    fi
    case "$SSH_PORT" in ''|*[!0-9]*) error "Invalid port number '$SSH_PORT'." ;; esac
    [ "$SSH_PORT" -ge 1 ] && [ "$SSH_PORT" -le 65535 ] || error "Invalid port number. Must be between 1 and 65535."

    if [ "$SSH_PASS_AUTH" = no ] && ! any_authorized_keys; then
        warn "Password authentication will be disabled, but no authorized_keys file with a key was found."
        warn "You could lock yourself out."
        if have_tty && [ "${ASSUME_DEFAULTS:-0}" != 1 ]; then
            [ "$(ask_yes_no "Continue anyway? (yes/no) [Default: no]: " no)" = yes ] || error "Aborted - nothing was changed."
        else
            error "Refusing to disable password authentication without any authorized key (no terminal to confirm)."
        fi
    fi

    # ---------- configuration ----------
    SSHD_CONFIG=/etc/ssh/sshd_config
    BACKUP="$SSHD_CONFIG.bak.$(date +%Y-%m-%d_%H-%M-%S)"
    info "Backing up $SSHD_CONFIG to $BACKUP..."
    $SUDO cp -p "$SSHD_CONFIG" "$BACKUP"

    # sshd uses the FIRST value it reads. Debian/Ubuntu include sshd_config.d/*.conf at the
    # very top of sshd_config (e.g. 50-cloud-init.conf), so a drop-in that sorts first is
    # the only place where our values reliably win.
    DROPIN=""
    if grep -Eqi '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' "$SSHD_CONFIG"; then
        DROPIN=/etc/ssh/sshd_config.d/00-ssh-bootstrap-kit.conf
        info "Writing settings to $DROPIN (takes precedence over other drop-ins)..."
        printf '# Managed by ssh-bootstrap-kit\nPort %s\nPermitRootLogin %s\nPasswordAuthentication %s\n' \
            "$SSH_PORT" "$SSH_ROOT_LOGIN" "$SSH_PASS_AUTH" | $SUDO tee "$DROPIN" >/dev/null
        $SUDO chmod 644 "$DROPIN"
        # Keep an explicit "Port" in the main file from adding a second listener.
        $SUDO sed -i -E 's/^([[:space:]]*Port[[:space:]].*)$/#\1  # moved to sshd_config.d by ssh-bootstrap-kit/' "$SSHD_CONFIG"
    else
        info "Applying settings to $SSHD_CONFIG..."
        set_key Port "$SSH_PORT"
        set_key PermitRootLogin "$SSH_ROOT_LOGIN"
        set_key PasswordAuthentication "$SSH_PASS_AUTH"
    fi

    # sshd -t fails without the privilege separation directory or host keys (containers)
    $SUDO install -d -m 0755 -o root -g root /run/sshd
    ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1 || $SUDO ssh-keygen -A >/dev/null
    info "Testing SSH configuration syntax..."
    if ! $SUDO /usr/sbin/sshd -t; then
        warn "SSH configuration test failed! Restoring backup..."
        $SUDO cp -p "$BACKUP" "$SSHD_CONFIG"
        [ -z "$DROPIN" ] || $SUDO rm -f "$DROPIN"
        error "Configuration restored; nothing was changed."
    fi

    effective=$($SUDO /usr/sbin/sshd -T 2>/dev/null | grep -Ei '^(port|permitrootlogin|passwordauthentication) ' | tr '\n' ' ')
    info "Effective settings: $effective"

    # ---------- firewall (before the restart, so a new port is never blocked) ----------
    if command -v ufw >/dev/null 2>&1 && $SUDO ufw status 2>/dev/null | grep -q "Status: active"; then
        info "Opening port $SSH_PORT/tcp in UFW..."
        $SUDO ufw allow "$SSH_PORT"/tcp >/dev/null
    fi

    # ---------- (re)start ----------
    restart_ssh
    info "SSH setup completed successfully!"
    info "You can now connect via: ssh <user>@<ip> -p $SSH_PORT"
    [ -n "$SUDO" ] || [ "$SSH_ROOT_LOGIN" = yes ] || warn "Root login is disabled - log in with a regular user."
}

info()  { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1" >&2; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; exit 1; }

have_tty() { (exec </dev/tty) 2>/dev/null; }

ask() {  # prompt default
    printf '%s' "$1" >/dev/tty
    IFS= read -r reply </dev/tty || reply=""
    printf '%s' "${reply:-$2}"
}

normalize_yes_no() {
    case "$1" in
        y|Y|yes|Yes|YES) printf yes ;;
        n|N|no|No|NO) printf no ;;
        *) return 1 ;;
    esac
}

ask_yes_no() {  # prompt default
    while :; do
        if normalize_yes_no "$(ask "$1" "$2")"; then return 0; fi
        printf "${YELLOW}[WARN]${NC} Please answer yes, Yes, y or no, No, n.\n" >/dev/tty
    done
}

set_key() {  # key value - replace the first (possibly commented) occurrence or append
    if grep -Eq "^[[:space:]]*#?[[:space:]]*$1([[:space:]]|\$)" "$SSHD_CONFIG"; then
        # only the first occurrence: later ones may belong to Match blocks
        $SUDO sed -i -E "0,/^[[:space:]]*#?[[:space:]]*$1([[:space:]]|\$).*/s//$1 $2/" "$SSHD_CONFIG"
    else
        printf '%s %s\n' "$1" "$2" | $SUDO tee -a "$SSHD_CONFIG" >/dev/null
    fi
}

any_authorized_keys() {
    for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
        $SUDO test -s "$f" 2>/dev/null && return 0
    done
    return 1
}

systemd_running() { [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; }

is_active() {
    if systemd_running; then systemctl is-active --quiet "$1" 2>/dev/null
    else pgrep -x "$1" >/dev/null 2>&1; fi
}

restart_ssh() {
    if systemd_running; then
        if systemctl list-unit-files ssh.socket >/dev/null 2>&1 && \
           { systemctl is-enabled --quiet ssh.socket 2>/dev/null || systemctl is-active --quiet ssh.socket 2>/dev/null; }; then
            # Ubuntu >= 22.10: socket activation. The listening port comes from a generator
            # that reads sshd_config, so it needs daemon-reload + socket restart.
            info "Socket activation detected - reloading ssh.socket..."
            $SUDO systemctl daemon-reload
            $SUDO systemctl restart ssh.socket
            $SUDO systemctl try-restart ssh.service 2>/dev/null || true
        else
            $SUDO systemctl enable ssh >/dev/null 2>&1 || true
            $SUDO systemctl restart ssh
        fi
        sleep 1
    elif command -v service >/dev/null 2>&1 && [ -x /etc/init.d/ssh ]; then
        $SUDO service ssh restart >/dev/null
    else
        warn "No init system found - starting sshd directly."
        if [ -s /run/sshd.pid ]; then $SUDO kill "$(cat /run/sshd.pid)" 2>/dev/null || true; sleep 1; fi
        $SUDO /usr/sbin/sshd
    fi

    if command -v ss >/dev/null 2>&1; then
        ss -Htln "sport = :$SSH_PORT" 2>/dev/null | grep -q . || error "sshd is not listening on port $SSH_PORT - check 'journalctl -u ssh'."
        info "sshd is listening on port $SSH_PORT."
    fi
}

main "$@"
