# SSH Bootstrap Kit

A lightweight, robust, and interactive shell script to install, enable, and configure OpenSSH on Debian-based Linux distributions. Designed to run seamlessly on real hardware, Docker containers, LXCs, and VMs.

## Supported Operating Systems

- **Ubuntu**
- **Debian**
- **Kali Linux** & **Kali Purple**
- **DietPi OS**
- **Raspberry Pi OS**

---

## Quick Installation (One-Liner)

You can run the script directly via `wget` and pipe it into `sh`:

```bash
wget https://bit.ly/3UIY9oK -O - | sh
```

Or with:

```bash
wget https://raw.githubusercontent.com/Michdo93/ssh-bootstrap-kit/refs/heads/main/install.sh -O - | sh
```

---

## Features

* **Automatic Privilege Check:** Detects whether you are running as root or via `sudo` and safely handles execution permissions.
* **Interactive Prompts:**
* Custom **SSH Port** (Defaults to `22` if left blank).
* **Root Login** permissions (`yes`/`no` support with shorthand inputs like `y`, `Y`, `n`, `N`).
* **Password-based Authentication** control.


* **Safety First:** Automatically backs up your original `/etc/ssh/sshd_config` before making changes and validates syntax (`sshd -t`) before restarting the service.
* **Firewall Integration:** Automatically opens the chosen port in UFW if the firewall is active.

---

## Manual Execution

If you prefer to inspect the script before running it:

```bash
git clone https://github.com/Michdo93/ssh-bootstrap-kit
cd ssh-bootstrap-kit
chmod +x install.sh
sudo ./install.sh
```

## License

MIT License. Feel free to use and modify it for your projects.
