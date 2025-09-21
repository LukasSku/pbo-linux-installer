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

    # Check for unzip
    if ! command -v unzip >/dev/null 2>&1; then
        print_info "Installing unzip..."
        case "$DISTRO" in
            ubuntu|debian|pop|mint|elementary|linuxmint)
                sudo apt update && sudo apt install -y unzip
                ;;
            fedora)
                sudo dnf install -y unzip
                ;;
            rhel|centos|rocky|almalinux)
                if command -v dnf >/dev/null 2>&1; then
                    sudo dnf install -y unzip
                elif command -v yum >/dev/null 2>&1; then
                    sudo yum install -y unzip
                fi
                ;;
            opensuse*|sles)
                sudo zypper install -y unzip
                ;;
            arch|manjaro|endeavouros|garuda)
                sudo pacman -S --noconfirm unzip
                ;;
            alpine)
                sudo apk add unzip
                ;;
            gentoo)
                sudo emerge app-arch/unzip
                ;;
            void)
                sudo xbps-install -S unzip
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

    # Check for download tool
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        print_info "Installing curl..."
        case "$DISTRO" in
            ubuntu|debian|pop|mint|elementary|linuxmint)
                sudo apt install -y curl
                ;;
            fedora)
                sudo dnf install -y curl
                ;;
            rhel|centos|rocky|almalinux)
                if command -v dnf >/dev/null 2>&1; then
                    sudo dnf install -y curl
                elif command -v yum >/dev/null 2>&1; then
                    sudo yum install -y curl
                fi
                ;;
            opensuse*|sles)
                sudo zypper install -y curl
                ;;
            arch|manjaro|endeavouros|garuda)
                sudo pacman -S --noconfirm curl
                ;;
            alpine)
                sudo apk add curl
                ;;
            gentoo)
                sudo emerge net-misc/curl
                ;;
            void)
                sudo xbps-install -S curl
                ;;
        esac
    fi

    # Check for Java
    if ! command -v java >/dev/null 2>&1; then
        print_warning "Java is not installed. Installing OpenJDK..."
        case "$DISTRO" in
            ubuntu|debian|pop|mint|elementary|linuxmint)
                sudo apt install -y openjdk-17-jre-headless
                ;;
            fedora)
                sudo dnf install -y java-17-openjdk-headless
                ;;
            rhel|centos|rocky|almalinux)
                if command -v dnf >/dev/null 2>&1; then
                    sudo dnf install -y java-17-openjdk-headless
                elif command -v yum >/dev/null 2>&1; then
                    sudo yum install -y java-17-openjdk-headless
                fi
                ;;
            opensuse*|sles)
                sudo zypper install -y java-17-openjdk-headless
                ;;
            arch|manjaro|endeavouros|garuda)
                sudo pacman -S --noconfirm jre17-openjdk-headless
                ;;
            alpine)
                sudo apk add openjdk17-jre-headless
                ;;
            gentoo)
                sudo emerge virtual/jre:17
                ;;
            void)
                sudo xbps-install -S openjdk17-jre
                ;;
            *)
                print_warning "Could not install Java automatically. Please install Java 17 or higher manually."
                ;;
        esac
    else
        print_success "Java is already installed"
        JAVA_VERSION=$(java -version 2>&1 | head -n1 | cut -d'"' -f2 | cut -d'.' -f1-2)
        JAVA_MAJOR=$(echo "$JAVA_VERSION" | cut -d'.' -f1)
        if [ "$JAVA_MAJOR" -lt 17 ] 2>/dev/null; then
            print_warning "Java version $JAVA_VERSION detected. Java 17+ is recommended for best performance."
        fi
    fi
}

download_and_extract() {
    print_info "Creating temporary directory..."
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR" || exit 1

    print_info "Downloading PBO from $DOWNLOAD_URL..."
    if command -v curl >/dev/null 2>&1; then
        if ! curl -L -f -o pbo-windows.zip "$DOWNLOAD_URL"; then
            print_error "Download failed with curl"
            exit 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -O pbo-windows.zip "$DOWNLOAD_URL"; then
            print_error "Download failed with wget"
            exit 1
        fi
    else
        print_error "Neither curl nor wget is available. Please install one of them."
        exit 1
    fi

    print_info "Extracting archive..."
    if ! unzip -q pbo-windows.zip; then
        print_error "Failed to extract archive"
        exit 1
    fi

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

    # Check if pbo.jar exists
    if [ ! -f "$INSTALL_DIR/pbo.jar" ]; then
        print_error "pbo.jar not found in installation directory"
        print_info "Available files:"
        ls -la "$INSTALL_DIR"
        exit 1
    fi

    print_info "Creating desktop entry..."
    mkdir -p "$(dirname "$DESKTOP_FILE")"

    print_info "Using icon: $HOME/Applications/pbo/assets/icons/48.png"

    # Create desktop entry with proper exec path
    cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$APP_NAME
Comment=Pokemon Blaze Online Game
Exec=bash -c 'cd "$HOME/Applications/pbo" && java -jar pbo.jar'
Path=$HOME/Applications/pbo/
Icon=$HOME/Applications/pbo/assets/icons/48.png
Terminal=false
Categories=Game;
StartupWMClass=pbo
StartupNotify=true
MimeType=application/x-java-archive;
EOF

    chmod +x "$DESKTOP_FILE"

    # Restart desktop environment services to recognize new application
    if command -v systemctl >/dev/null 2>&1; then
        # For systemd-based desktop environments
        systemctl --user daemon-reload 2>/dev/null || true
    fi

    # Update desktop database if available
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true
    fi

    # Force refresh icon cache
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -f -t "$HOME/.icons/" 2>/dev/null || true
        gtk-update-icon-cache -f -t "$HOME/.local/share/icons/" 2>/dev/null || true
    fi

    # For KDE Plasma
    if command -v kbuildsycoca5 >/dev/null 2>&1; then
        kbuildsycoca5 2>/dev/null || true
    elif command -v kbuildsycoca6 >/dev/null 2>&1; then
        kbuildsycoca6 2>/dev/null || true
    fi

    # Make the desktop file executable and try to register it
    gio set "$DESKTOP_FILE" metadata::trusted true 2>/dev/null || true

    print_success "$APP_NAME installed successfully!"
    print_info "Installation directory: $INSTALL_DIR"
    print_info "Desktop file: $DESKTOP_FILE"
    print_info "Icon path: $HOME/Applications/pbo/assets/icons/48.png"
    print_info "You can now find '$APP_NAME' in your application menu"
    
    # Test if the application can be started manually
    print_info "Testing manual execution..."
    cd "$INSTALL_DIR"
    if java -jar pbo.jar --help >/dev/null 2>&1 || java -jar pbo.jar --version >/dev/null 2>&1 || timeout 3s java -jar pbo.jar >/dev/null 2>&1; then
        print_success "Manual execution test passed"
    else
        print_warning "Manual execution test failed, but the application might still work"
        print_info "You can test manually with: cd '$INSTALL_DIR' && java -jar pbo.jar"
    fi

    # Verify icon exists
    if [ -f "$HOME/Applications/pbo/assets/icons/48.png" ]; then
        print_success "Icon file found and ready"
    else
        print_warning "Icon file not found at expected location"
        print_info "Available icons:"
        ls -la "$HOME/Applications/pbo/assets/icons/" 2>/dev/null || print_warning "Icons directory not found"
    fi
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

    # Update desktop database if available
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true
    fi

    print_success "$APP_NAME uninstalled successfully!"
}

cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        print_info "Cleaned up temporary files"
    fi
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help        Show this help message"
    echo "  -u, --uninstall   Uninstall Pokemon Blaze Online"
    echo "  --test-java       Test Java installation without installing PBO"
    echo ""
    echo "Example:"
    echo "  $0                Install Pokemon Blaze Online"
    echo "  $0 --uninstall    Uninstall Pokemon Blaze Online"
}

test_java() {
    print_info "Testing Java installation..."
    
    if ! command -v java >/dev/null 2>&1; then
        print_error "Java is not installed"
        return 1
    fi
    
    print_success "Java is installed"
    
    JAVA_VERSION=$(java -version 2>&1 | head -n1)
    print_info "Java version: $JAVA_VERSION"
    
    JAVA_MAJOR=$(echo "$JAVA_VERSION" | cut -d'"' -f2 | cut -d'.' -f1)
    if [ "$JAVA_MAJOR" -ge 17 ] 2>/dev/null; then
        print_success "Java version is compatible (17+)"
    else
        print_warning "Java version might be too old. Java 17+ is recommended."
    fi
}

main() {
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -u|--uninstall)
            uninstall_pbo
            exit 0
            ;;
        --test-java)
            test_java
            exit 0
            ;;
        "")
            # Normal installation
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac

    print_info "Starting $APP_NAME installer..."

    detect_distro

    install_dependencies

    download_and_extract

    install_pbo

    cleanup

    print_success "Installation completed successfully!"
    print_info ""
    print_info "To start the game:"
    print_info "1. Look for '$APP_NAME' in your application menu, or"
    print_info "2. Run: cd '$INSTALL_DIR' && java -jar pbo.jar"
    print_info ""
    print_info "To uninstall, run this script with --uninstall option"
}

# Set up cleanup trap
trap cleanup EXIT

# Run main function
main "$@"
