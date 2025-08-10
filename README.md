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
```bash
curl -fsS https://raw.githubusercontent.com/LukasSku/pbo-linux-installer/refs/heads/main/installer.sh | bash
```

## Uninstall
```bash
curl -fsS https://raw.githubusercontent.com/LukasSku/pbo-linux-installer/refs/heads/main/installer.sh | bash -s -- --uninstall
```

## Manual Java Installation
If the automatic Java installation fails, you can install Java 17 manually:

### Ubuntu/Debian:
```bash
sudo apt update
sudo apt install openjdk-17-jre
```

### Fedora:
```bash
sudo dnf install java-17-openjdk
```

### Arch Linux:
```bash
sudo pacman -S jre17-openjdk
```

### Alpine:
```bash
sudo apk add openjdk17-jre
```

## What it does
- Downloads and installs PBO to `~/Applications/pbo/`
- Installs Java 17 and unzip if needed
- Creates desktop entry
- Removes Windows .exe files
