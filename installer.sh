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
        DISTRO=$ID
        DISTRO_LIKE=${ID_LIKE:-}
    elif command -v lsb_release >/dev/null 2>&1; then
        DISTRO=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        DISTRO_LIKE=""
    else
        DISTRO="unknown"
        DISTRO_LIKE=""
    fi
    print_info "Detected distribution: $DISTRO"
}

check_or_install_package() {
    local pkg="$1"
    if ! command -v "$pkg" >/dev/null 2>&1; then
        print_info "Installing $pkg..."
        case "$DISTRO" in
            ubuntu|debian|pop|mint|elementary)
                sudo apt update && sudo apt install -y "$2"
                ;;
            fedora|rhel|centos)
                sudo dnf install -y "$2"
                ;;
            opensuse*|sles)
                sudo zypper install -y "$2"
                ;;
            arch|manjaro|endeavouros)
                sudo pacman -S --noconfirm "$2"
                ;;
            alpine)
                sudo apk add "$2"
                ;;
            *)
                if [[ -n "$DISTRO_LIKE" ]]; then
                    print_warning "Trying installation via DISTRO_LIKE: $DISTRO_LIKE"
                    DISTRO="$DISTRO_LIKE"
                    check_or_install_package "$pkg" "$2"
                else
                    print_error "Unsupported distribution for installing '$pkg'. Install it manually."
                    exit 1
                fi
                ;;
        esac
        if ! command -v "$pkg" >/dev/null 2>&1; then
            print_error "Failed to install '$pkg'."
            exit 1
        fi
    else
        print_success "$pkg is already installed"
    fi
}

install_dependencies() {
    print_info "Checking and installing dependencies..."
    check_or_install_package unzip unzip

    if ! command -v java >/dev/null 2>&1; then
        print_warning "Java not found. Installing OpenJDK 17..."
        case "$DISTRO" in
            ubuntu|debian|pop|mint|elementary)
                sudo apt install -y openjdk-17-jre
                ;;
            fedora|rhel|centos)
                sudo dnf install -y java-17-openjdk
                ;;
            opensuse*|sles)
                sudo zypper install -y java-17-openjdk
                ;;
            arch|manjaro|endeavouros)
                sudo pacman -S --noconfirm jre-openjdk
                ;;
            alpine)
                sudo apk add openjdk17-jre
                ;;
            *)
                print_error "Automatic Java installation not supported. Please install Java 17+ manually."
                exit 1
                ;;
        esac
    fi

    if ! command -v java >/dev/null 2>&1; then
        print_error "Java installation failed."
        exit 1
    fi

    JAVA_VERSION_RAW=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
    JAVA_MAJOR=$(echo "$JAVA_VERSION_RAW" | awk -F. '{print ($1 == 1 ? $2 : $1)}')

    if [ "$JAVA_MAJOR" -lt 17 ]; then
        print_error "Java version $JAVA_VERSION_RAW detected. Java 17+ is required."
        exit 1
    else
        print_success "Java $JAVA_VERSION_RAW is installed and compatible."
    fi
}

download_and_extract() {
    print_info "Creating temporary directory..."
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"

    print_info "Downloading PBO from $DOWNLOAD_URL..."
    if command -v curl >/dev/null 2>&1; then
        curl -fL -o pbo-windows.zip "$DOWNLOAD_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -O pbo-windows.zip "$DOWNLOAD_URL"
    else
        print_error "Neither curl nor wget is available."
        exit 1
    fi

    if [ ! -s pbo-windows.zip ]; then
        print_error "Download failed or empty file."
        exit 1
    fi

    print_info "Extracting archive..."
    unzip -q pbo-windows.zip

    print_info "Removing .exe files..."
    find . -name "*.exe" -type f -delete

    print_success "Download and extraction completed"
}

install_pbo() {
    print_info "Creating installation directory..."
    mkdir -p "$(dirname "$INSTALL_DIR")"

    if [ -d "$INSTALL_DIR" ]; then
        print_warning "Installation directory already exists. Removing old installation..."
        rm -rf "$INSTALL_DIR"
    fi

    print_info "Moving files to installation directory..."
    mv pbo-windows "$INSTALL_DIR"

    print_info "Creating desktop entry..."
    mkdir -p "$(dirname "$DESKTOP_FILE")"

    cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$APP_NAME
Comment=PBO
Exec=java -jar $INSTALL_DIR/pbo.jar
Path=$INSTALL_DIR/
Icon=$INSTALL_DIR/assets/icons/pbo_icon.ico
Terminal=false
Categories=Game;
EOF

    chmod +x "$DESKTOP_FILE"

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$HOME/.local/share/applications/"
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
        print_success "Removed desktop file: $DESKTOP_FILE"
    else
        print_warning "Desktop file not found: $DESKTOP_FILE"
    fi

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$HOME/.local/share/applications/"
    fi

    print_success "$APP_NAME uninstalled successfully!"
}

cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        print_info "Cleaned up temporary files"
    fi
}

main() {
    print_info "Starting $APP_NAME installer..."

    if [ "${1:-}" = "--uninstall" ] || [ "${1:-}" = "-u" ]; then
        uninstall_pbo
        exit 0
    fi

    detect_distro
    install_dependencies
    download_and_extract
    install_pbo
    cleanup

    print_success "Installation completed successfully!"
    print_info "To uninstall, run: curl -fsS https://raw.githubusercontent.com/LukasSku/pbo-linux-installer/refs/heads/main/installer.sh | bash -s -- --uninstall"
}

trap cleanup EXIT INT TERM

main "$@"
