# PBO Linux Installer

One-line installer for Pokemon Blaze Online on Linux.

## Prerequisites

Install `curl` first:

```bash
# Ubuntu/Debian
sudo apt install curl

# Fedora
sudo dnf install curl

# Arch
sudo pacman -S curl

# Alpine
sudo apk add curl
```

## Install

If Java install not work, run with sudo privileges

```bash
curl -fsS https://raw.githubusercontent.com/LukasSku/pbo-linux-installer/refs/heads/main/installer.sh | bash
```

## Uninstall

```bash
curl -fsS https://raw.githubusercontent.com/LukasSku/pbo-linux-installer/refs/heads/main/installer.sh | bash -s -- --uninstall
```

## What it does

- Downloads and installs PBO to `~/Applications/pbo/`
- Installs Java 17 and unzip if needed
- Creates desktop entry
- Removes Windows .exe files

Find "Pokemon Blaze Online" in your app menu after installation.

## Supported Systems

Ubuntu, Debian, Fedora, Arch, Alpine and derivatives.
