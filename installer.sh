#!/bin/bash
set -euo pipefail

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

APP_NAME="Pokemon Blaze Online"
APP_ID="pbo"
DOWNLOAD_URL="https://pbo-downloads.s3.eu-central-003.backblazeb2.com/pbo-windows.zip"
INSTALL_DIR="$HOME/Applications/pbo"
DESKTOP_FILE="$HOME/.local/share/applications/pbo.desktop"
TEMP_DIR="/tmp/pbo-installer"

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=${ID,,}
        DISTRO_LIKE=${ID_LIKE:-}
        DISTRO_LIKE=${DISTRO_LIKE,,}
    else
        DISTRO="unknown"
        DISTRO_LIKE=""
    fi
    print_info "Detected distribution: $DISTRO (ID_LIKE=$DISTRO_LIKE)"
}
detect_package_manager() {
    print_info "Detecting package manager..."

    if command -v apt >/dev/null 2>&1; then
        PKG_MGR="apt"
        PKG_INSTALL="sudo apt install -y"
        PKG_UPDATE="sudo apt update"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MGR="dnf"
        PKG_INSTALL="sudo dnf install -y"
        PKG_UPDATE="sudo dnf check-update || true"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MGR="yum"
        PKG_INSTALL="sudo yum install -y"
        PKG_UPDATE="sudo yum check-update || true"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MGR="pacman"
        PKG_INSTALL="sudo pacman -S --noconfirm"
        PKG_UPDATE="sudo pacman -Sy"
    elif command -v zypper >/dev/null 2>&1; then
        PKG_MGR="zypper"
        PKG_INSTALL="sudo zypper install -y"
        PKG_UPDATE="sudo zypper refresh"
    elif command -v apk >/dev/null 2>&1; then
        PKG_MGR="apk"
        PKG_INSTALL="sudo apk add"
        PKG_UPDATE="sudo apk update"
    else
        PKG_MGR="unknown"
    fi

    print_info "Package manager detected: $PKG_MGR"
}

install_package() {
    PACKAGE_NAME="$1"
    if [ "$PKG_MGR" = "unknown" ]; then
        print_error "Unsupported Linux distribution or no supported package manager found."
        print_error "Please install $PACKAGE_NAME manually."
        exit 1
    fi

    print_info "Installing $PACKAGE_NAME..."
    $PKG_UPDATE
    $PKG_INSTALL "$PACKAGE_NAME"
}

check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        return 1
    else
        return 0
    fi
}

install_dependencies() {
    print_info "Checking dependencies..."

    if ! check_command unzip; then
        install_package unzip
    else
        print_success "unzip is already installed."
    fi

    if ! check_command java; then
        print_warning "Java not found. Attempting to install OpenJDK 17+."

        case "$PKG_MGR" in
            apt)
                install_package openjdk-17-jre
                ;;
            dnf|yum)
                install_package java-17-openjdk
                ;;
            pacman)
                install_package jre-openjdk
                ;;
            zypper)
                install_package java-17-openjdk
                ;;
            apk)
                install_package openjdk17
                ;;
            *)
                print_error "Automatic Java installation not supported on this system."
                print_error "Please install Java 17 or higher manually."
                exit 1
                ;;
        esac

        # No direct version check here, assume package installs correct version
    else
        print_success "Java is already installed."
        JAVA_VERSION_FULL=$(java -version 2>&1 | head -n1)
        JAVA_VERSION_NUM=$(echo "$JAVA_VERSION_FULL" | grep -oP '(?<=version ")[^"]+')
        JAVA_MAJOR=$(echo "$JAVA_VERSION_NUM" | cut -d'.' -f1)

        # Java 8 has versions like "1.8", Java 11+ like "11"
        if [[ "$JAVA_MAJOR" == "1" ]]; then
            JAVA_MAJOR=$(echo "$JAVA_VERSION_NUM" | cut -d'.' -f2)
        fi

        if [ "$JAVA_MAJOR" -lt 17 ]; then
            print_warning "Detected Java version $JAVA_VERSION_NUM. Java 17 or newer is recommended."
        fi
    fi
}

download_and_extract() {
    print_info "Preparing temporary directory..."
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"

    print_info "Downloading $APP_NAME from $DOWNLOAD_URL ..."
    if check_command curl; then
        curl -L -o pbo-windows.zip "$DOWNLOAD_URL"
    elif check_command wget; then
        wget -O pbo-windows.zip "$DOWNLOAD_URL"
    else
        print_error "Neither curl nor wget found. Please install one of them."
        exit 1
    fi

    print_info "Extracting archive..."
    unzip -q pbo-windows.zip

    print_info "Removing .exe files..."
    find . -type f -name "*.exe" -delete

    print_success "Download and extraction completed."
}

install_pbo() {
    print_info "Creating installation directory..."
    mkdir -p "$(dirname "$INSTALL_DIR")"

    if [ -d "$INSTALL_DIR" ]; then
        print_warning "Installation directory already exists. Removing old files..."
        rm -rf "$INSTALL_DIR"
    fi

    mv pbo-windows "$INSTALL_DIR"

    print_info "Creating desktop entry..."
    mkdir -p "$(dirname "$DESKTOP_FILE")"

    cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$APP_NAME
Comment=Pokemon Blaze Online
Exec=java -jar $INSTALL_DIR/pbo.jar
Path=$INSTALL_DIR/
Icon=$INSTALL_DIR/assets/icons/pbo_icon.ico
Terminal=false
Categories=Game;
EOF

    chmod +x "$DESKTOP_FILE"

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$HOME/.local/share/applications/" || true
    fi

    print_success "$APP_NAME installed successfully!"
    print_info "Installation directory: $INSTALL_DIR"
    print_info "Desktop file: $DESKTOP_FILE"
}

uninstall_pbo() {
    print_info "Uninstalling $APP_NAME..."

    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
        print_success "Removed installation directory: $INSTALL_DIR"
    else
        print_warning "Installation directory not found: $INSTALL_DIR"
    fi

    if [ -f "$DESKTOP_FILE" ]; then
        rm -f "$DESKTOP_FILE"
        print_success "Removed desktop entry: $DESKTOP_FILE"
    else
        print_warning "Desktop entry not found: $DESKTOP_FILE"
    fi

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$HOME/.local/share/applications/" || true
    fi

    print_success "$APP_NAME uninstalled successfully!"
}

cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        print_info "Cleaned up temporary files."
    fi
}

main() {
    print_info "Starting $APP_NAME installer..."

    if [[ "${1:-}" == "--uninstall" ]] || [[ "${1:-}" == "-u" ]]; then
        uninstall_pbo
        exit 0
    fi

    detect_distro
    detect_package_manager

    if [ "$PKG_MGR" = "unknown" ]; then
        print_error "Unsupported Linux distribution or no supported package manager found."
        print_error "Please install dependencies manually and rerun this script."
        exit 1
    fi

    install_dependencies
    download_and_extract
    install_pbo
    cleanup

    print_success "Installation completed successfully!"
    print_info "To uninstall, run:"
    echo "curl -fsS https://raw.githubusercontent.com/LukasSku/pbo-linux-installer/refs/heads/main/installer.sh | bash -s -- --uninstall"
}

trap cleanup EXIT

main "$@"
