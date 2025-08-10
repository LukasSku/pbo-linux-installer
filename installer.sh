#!/bin/bash
set -euo pipefail

# ===== Farben =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ===== Variablen =====
APP_NAME="Pokemon Blaze Online"
DOWNLOAD_URL="https://pbo-downloads.s3.eu-central-003.backblazeb2.com/pbo-windows.zip"
INSTALL_DIR="$HOME/Applications/pbo"
DESKTOP_FILE="$HOME/.local/share/applications/pbo.desktop"
TEMP_DIR="$(mktemp -d /tmp/pbo-installer-XXXX)"

# ===== Print-Funktionen =====
print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ===== Distro-Erkennung =====
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=${ID,,}
        DISTRO_LIKE=${ID_LIKE,,:-}
    else
        DISTRO="unknown"
        DISTRO_LIKE=""
    fi
    print_info "Detected distribution: $DISTRO"
}

# ===== Generische Paketinstallation =====
install_pkg() {
    local cmd="$1" pkg="$2"
    if ! command -v "$cmd" &>/dev/null; then
        print_info "Installing $pkg..."
        case "$DISTRO" in
            ubuntu|debian|pop|mint|elementary)
                sudo apt update && sudo apt install -y "$pkg"
                ;;
            fedora|rhel|centos)
                sudo dnf install -y "$pkg"
                ;;
            opensuse*|sles)
                sudo zypper install -y "$pkg"
                ;;
            arch|manjaro|endeavouros|garuda|arcolinux|cachyos)
                sudo pacman -S --noconfirm "$pkg"
                ;;
            alpine)
                sudo apk add "$pkg"
                ;;
            *)
                if [[ "$DISTRO_LIKE" == *arch* ]]; then
                    sudo pacman -S --noconfirm "$pkg"
                elif [[ "$DISTRO_LIKE" == *debian* ]]; then
                    sudo apt update && sudo apt install -y "$pkg"
                else
                    print_error "Unsupported distribution for automatic install of $pkg"
                    exit 1
                fi
                ;;
        esac
    else
        print_success "$pkg is already installed"
    fi
}

# ===== Java-Prüfung & Installation =====
check_java() {
    if ! command -v java &>/dev/null; then
        print_warning "Java not found. Installing OpenJDK 17..."
        install_pkg java java-17-openjdk || install_pkg java openjdk-17-jre || install_pkg java jre-openjdk
    fi

    if ! command -v java &>/dev/null; then
        print_error "Java installation failed. Please install Java 17+ manually."
        exit 1
    fi

    JAVA_VERSION_RAW=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
    JAVA_MAJOR=$(echo "$JAVA_VERSION_RAW" | awk -F. '{print ($1 == 1 ? $2 : $1)}')

    if [ "$JAVA_MAJOR" -lt 17 ]; then
        print_error "Java version $JAVA_VERSION_RAW detected. Java 17+ required."
        exit 1
    fi
    print_success "Java $JAVA_VERSION_RAW is installed and compatible."
}

# ===== Download & Extraktion =====
download_and_extract() {
    print_info "Downloading PBO..."
    if command -v curl &>/dev/null; then
        curl -fL -o "$TEMP_DIR/pbo-windows.zip" "$DOWNLOAD_URL"
    elif command -v wget &>/dev/null; then
        wget -O "$TEMP_DIR/pbo-windows.zip" "$DOWNLOAD_URL"
    else
        print_error "Neither curl nor wget installed."
        exit 1
    fi

    if [ ! -s "$TEMP_DIR/pbo-windows.zip" ]; then
        print_error "Download failed or empty file."
        exit 1
    fi

    print_info "Extracting archive..."
    unzip -q "$TEMP_DIR/pbo-windows.zip" -d "$TEMP_DIR"

    print_info "Removing Windows executables..."
    find "$TEMP_DIR" -name "*.exe" -delete

    print_success "Download and extraction completed."
}

# ===== Installation =====
install_pbo() {
    print_info "Installing to $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    mv "$TEMP_DIR"/pbo-windows/* "$INSTALL_DIR"/

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
    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "$HOME/.local/share/applications/"
    fi

    print_success "$APP_NAME installed successfully!"
}

# ===== Deinstallation =====
uninstall_pbo() {
    print_info "Uninstalling $APP_NAME..."
    rm -rf "$INSTALL_DIR" "$DESKTOP_FILE"
    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "$HOME/.local/share/applications/"
    fi
    print_success "$APP_NAME uninstalled successfully!"
}

# ===== Cleanup =====
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT INT TERM

# ===== Main =====
main() {
    if [[ "${1:-}" == "--uninstall" || "${1:-}" == "-u" ]]; then
        uninstall_pbo
        exit 0
    fi

    print_info "Starting $APP_NAME installer..."
    detect_distro
    install_pkg unzip unzip
    check_java
    download_and_extract
    install_pbo
    print_success "Installation completed successfully!"
    print_info "To uninstall: run this script with --uninstall"
}

main "$@"
