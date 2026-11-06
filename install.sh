#!/usr/bin/env bash
#
# SSH Bootstrap & Hardening Script for Debian-based Distributions
# Supports: Ubuntu, Debian, Kali Linux, Kali Purple, DietPi, Raspberry Pi OS
# Usage: wget https://bit.ly/YOUR_BITLY_HASH -O - | bash
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Ensure script is run with root privileges (supporting sudo or direct root)
if [ "$EUID" -ne 0 ]; then
    if command -v sudo &> /dev/null; then
        print_info "Re-running script with sudo privileges..."
        exec sudo "$0" "$@"
    else
        print_error "This script must be run as root or with sudo privileges."
    fi
fi

print_info "Starting SSH installation and configuration..."

# 1. Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    print_error "Cannot detect operating system (/etc/os-release missing)."
fi

SUPPORTED_OS=("ubuntu" "debian" "kali" "dietpi" "raspbian")
if [[ ! " ${SUPPORTED_OS[@]} " =~ " ${OS} " ]]; then
    print_warn "Detected OS '$OS' is not officially tested, but we will proceed as it is Debian-based."
fi

print_info "Detected OS: $PRETTY_NAME"

# 2. Install OpenSSH Server
print_info "Updating package lists and installing OpenSSH server..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq openssh-server ufw > /dev/null 2>&1

# Enable and start SSH service
systemctl enable ssh > /dev/null 2>&1
systemctl start ssh

# 3. Interactive Configuration Prompts
print_info "Please configure your SSH settings (press Enter for defaults):"

# Prompt 1: SSH Port
read -p "Enter SSH Port [Default: 22]: " SSH_PORT
SSH_PORT=${SSH_PORT:-22}
if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
    print_error "Invalid port number. Must be between 1 and 65535."
fi

# Prompt 2: Root Login
while true; do
    read -p "Allow root login? (yes/no) [Default: no]: " SSH_ROOT_LOGIN
    SSH_ROOT_LOGIN=${SSH_ROOT_LOGIN:-no}
    case "$SSH_ROOT_LOGIN" in
        y|Y|yes|Yes) SSH_ROOT_LOGIN="yes"; break ;;
        n|N|no|No) SSH_ROOT_LOGIN="no"; break ;;
        *) print_warn "Please answer yes, Yes, y or no, No, n." ;;
    esac
done

# Prompt 3: Password Authentication
while true; do
    read -p "Allow password-based authentication? (yes/no) [Default: yes]: " SSH_PASS_AUTH
    SSH_PASS_AUTH=${SSH_PASS_AUTH:-yes}
    case "$SSH_PASS_AUTH" in
        y|Y|yes|Yes) SSH_PASS_AUTH="yes"; break ;;
        n|N|no|No) SSH_PASS_AUTH="no"; break ;;
        *) print_warn "Please answer yes, Yes, y or no, No, n." ;;
    esac
done

# 4. Apply Configuration to sshd_config
SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_CONFIG="/etc/ssh/sshd_config.bak.$(date +%F_%T)"

print_info "Backing up original configuration to $BACKUP_CONFIG..."
cp "$SSHD_CONFIG" "$BACKUP_CONFIG"

print_info "Applying new settings to $SSHD_CONFIG..."

# Function to safely update or append config options
update_config_key() {
    local key="$1"
    local value="$2"
    if grep -qE "^\s*#?\s*${key}\b" "$SSHD_CONFIG"; then
        sed -i -E "s/^\s*#?\s*(${key}\b).*/\1 ${value}/" "$SSHD_CONFIG"
    else
        echo "${key} ${value}" >> "$SSHD_CONFIG"
    fi
}

update_config_key "Port" "$SSH_PORT"
update_config_key "PermitRootLogin" "$SSH_ROOT_LOGIN"
update_config_key "PasswordAuthentication" "$SSH_PASS_AUTH"

# 5. Test configuration and restart service
print_info "Testing SSH configuration syntax..."
if sshd -t; then
    print_info "Configuration syntax is valid. Restarting SSH service..."
    systemctl restart ssh
else
    print_error "SSH configuration test failed! Restoring backup..."
    cp "$BACKUP_CONFIG" "$SSHD_CONFIG"
    exit 1
fi

# 6. Configure UFW Firewall if active/available
if command -v ufw &> /dev/null; then
    if ufw status | grep -q "Status: active"; then
        print_info "Configuring UFW firewall to allow port $SSH_PORT..."
        ufw allow "$SSH_PORT"/tcp > /dev/null 2>&1
    fi
fi

print_info "SSH setup completed successfully!"
print_info "You can now connect via: ssh username@<your-ip> -p $SSH_PORT"
