#!/bin/bash

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

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        DISTRO_LIKE=$ID_LIKE
    elif command -v lsb_release >/dev/null 2>&1; then
        DISTRO=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    else
        DISTRO="unknown"
    fi

    print_info "Detected distribution: $DISTRO"
}

install_dependencies() {
    print_info "Checking and installing dependencies..."

    if ! command -v unzip >/dev/null 2>&1; then
        print_info "Installing unzip..."
        case "$DISTRO" in
            ubuntu|debian|pop|mint|elementary)
                sudo apt update && sudo apt install -y unzip
                ;;
            fedora|rhel|centos)
                sudo dnf install -y unzip
                ;;
            opensuse*|sles)
                sudo zypper install -y unzip
                ;;
            arch|manjaro|endeavouros)
                sudo pacman -S --noconfirm unzip
                ;;
            alpine)
                sudo apk add unzip
                ;;
            *)
                print_error "Unsupported distribution for automatic dependency installation"
                print_info "Please install 'unzip' manually and run this script again"
                exit 1
                ;;
        esac
    else
        print_success "unzip is already installed"
    fi

    if ! command -v java >/dev/null 2>&1; then
        print_warning "Java is not installed. Installing OpenJDK 17..."
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
                sudo pacman -S --noconfirm jre17-openjdk
                ;;
            alpine)
                sudo apk add openjdk17-jre
                ;;
            *)
                print_warning "Could not install Java automatically. Please install Java 17 or higher manually."
                ;;
        esac
    else
        print_success "Java is already installed"
        JAVA_VERSION=$(java -version 2>&1 | head -n1 | cut -d'"' -f2 | cut -d'.' -f1)
        if [ "$JAVA_VERSION" -lt 17 ] 2>/dev/null; then
            print_warning "Java version $JAVA_VERSION detected. Java 17+ is recommended for best performance."
        fi
    fi
}

download_and_extract() {
    print_info "Creating temporary directory..."
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"

    print_info "Downloading PBO from $DOWNLOAD_URL..."
    if command -v curl >/dev/null 2>&1; then
        curl -L -o pbo-windows.zip "$DOWNLOAD_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -O pbo-windows.zip "$DOWNLOAD_URL"
    else
        print_error "Neither curl nor wget is available. Please install one of them."
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
    print_info "You can now find '$APP_NAME' in your application menu"
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

    if [ "$1" = "--uninstall" ] || [ "$1" = "-u" ]; then
        uninstall_pbo
        exit 0
    fi

    detect_distro

    install_dependencies

    download_and_extract

    install_pbo

    cleanup

    print_success "Installation completed successfully!"
    print_info "To uninstall, run: curl -fsS https://raw.githubusercontent.com/LukasSku/pbo-linux-installer/main/install.sh | bash -s -- --uninstall"
}

trap cleanup EXIT

main "$@"
