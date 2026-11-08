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

You can run the script directly via `wget` (or `curl -fsSL`) and pipe it into `sh` or `bash` – as root or as a user with `sudo`:

```bash
wget https://bit.ly/3UIY9oK -O - | sh
```

Or with:

```bash
wget https://raw.githubusercontent.com/Michdo93/ssh-bootstrap-kit/refs/heads/main/install.sh -O - | sh
```

---

## Features

* **Automatic Privilege Check:** runs as `root` or prefixes the administrative commands with `sudo` (the sudo password is asked once).
* **Pipe-safe:** the whole script is read before anything runs, questions are read from the terminal (`/dev/tty`) and `apt` never consumes the piped script.
* **Interactive Prompts:**
  * Custom **SSH Port** (defaults to `22` if left blank).
  * **Root Login** permissions (`yes`/`no` support with shorthand inputs like `y`, `Y`, `n`, `N`).
  * **Password-based Authentication** control – refused if no `authorized_keys` exists yet (lock-out protection).
* **Settings that really apply:** on systems with `/etc/ssh/sshd_config.d/` (Debian 12, Ubuntu 22.04+) the values go into `00-ssh-bootstrap-kit.conf`, which sshd reads before other drop-ins such as `50-cloud-init.conf` (sshd uses the first value). The effective values are shown (`sshd -T`).
* **Socket activation:** on Ubuntu ≥ 22.10 a new port is applied via `daemon-reload` and a restart of `ssh.socket`.
* **Containers:** works without systemd (Docker/LXC); creates `/run/sshd` and missing host keys.
* **Safety First:** backs up `/etc/ssh/sshd_config`, validates the syntax (`sshd -t`) and restores the backup on errors; checks that sshd listens on the new port.
* **Firewall Integration:** opens the chosen port in UFW (if active) *before* sshd is restarted.

## Non-interactive

Without a terminal (or with `ASSUME_DEFAULTS=1`) the values come from the environment, otherwise the defaults apply:

```bash
wget -qO- https://raw.githubusercontent.com/Michdo93/ssh-bootstrap-kit/main/install.sh \
  | SSH_PORT=2222 SSH_ROOT_LOGIN=no SSH_PASS_AUTH=yes sh
```

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
