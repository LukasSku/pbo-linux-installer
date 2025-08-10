#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

APP_NAME="Pokemon Blaze Online"
DOWNLOAD_URL="https://pbo-downloads.s3.eu-central-003.backblazeb2.com/pbo-windows.zip"
INSTALL_DIR="$HOME/Applications/pbo"
DESKTOP_FILE="$HOME/.local/share/applications/pbo.desktop"
TEMP_DIR="$(mktemp -d /tmp/pbo-installer-XXXX)"
TEMURIN_DIR="/opt/temurin-17"
FORCE=false

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT INT TERM

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=${ID,,}
        DISTRO_LIKE=${ID_LIKE:-}
    else
        DISTRO="unknown"
        DISTRO_LIKE=""
    fi
    print_info "Detected distribution: $DISTRO (ID_LIKE=${DISTRO_LIKE})"
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

install_pkg_generic() {
    # install_pkg_generic <package_hint> <pkg_name_for_apt> <pkg_name_for_dnf> <pkg_name_for_pacman> <pkg_name_for_zypper> <pkg_name_for_apk>
    local hint="$1"; shift
    local apt_pkg="$1"; shift || true
    local dnf_pkg="$1"; shift || true
    local pacman_pkg="$1"; shift || true
    local zypper_pkg="$1"; shift || true
    local apk_pkg="$1"; shift || true

    # If command already exists by hint, skip
    if has_cmd "$hint"; then
        print_success "$hint is already available"
        return 0
    fi

    print_info "Trying to install package for '$hint'..."

    case "$DISTRO" in
        ubuntu|debian|pop|mint|elementary)
            if [ -n "$apt_pkg" ]; then
                sudo apt-get update -y
                sudo apt-get install -y "$apt_pkg"
            fi
            ;;
        fedora|rhel|centos)
            if [ -n "$dnf_pkg" ]; then
                sudo dnf install -y "$dnf_pkg"
            fi
            ;;
        opensuse*|sles)
            if [ -n "$zypper_pkg" ]; then
                sudo zypper install -y "$zypper_pkg"
            fi
            ;;
        arch|manjaro|endeavouros|garuda|arcolinux|cachyos)
            if [ -n "$pacman_pkg" ]; then
                sudo pacman -Sy --noconfirm "$pacman_pkg"
            fi
            ;;
        alpine)
            if [ -n "$apk_pkg" ]; then
                sudo apk add "$apk_pkg"
            fi
            ;;
        *)
            # try using ID_LIKE heuristics
            if [[ "$DISTRO_LIKE" == *"debian"* ]] && [ -n "$apt_pkg" ]; then
                sudo apt-get update -y
                sudo apt-get install -y "$apt_pkg"
            elif [[ "$DISTRO_LIKE" == *"arch"* ]] && [ -n "$pacman_pkg" ]; then
                sudo pacman -Sy --noconfirm "$pacman_pkg"
            else
                print_warning "Unsupported distribution for automatic installation of $hint (DISTRO=$DISTRO)."
            fi
            ;;
    esac

    if has_cmd "$hint"; then
        print_success "Installed/available: $hint"
    else
        print_warning "Could not install '$hint' automatically. You may need to install it manually."
    fi
}

ensure_basic_tools() {
    # Ensure at least one of curl|wget exists, and unzip exists
    if ! has_cmd curl && ! has_cmd wget; then
        print_info "Neither curl nor wget found — attempting to install curl"
        install_pkg_generic curl curl curl curl curl curl
    fi
    if ! has_cmd unzip; then
        install_pkg_generic unzip unzip unzip unzip unzip unzip
    fi
}

try_java_via_package_manager() {
    # Try to install Java 17 using package manager friendly names
    case "$DISTRO" in
        ubuntu|debian|pop|mint|elementary)
            sudo apt-get update -y
            sudo apt-get install -y openjdk-17-jre || sudo apt-get install -y openjdk-17-jdk
            ;;
        fedora|rhel|centos)
            sudo dnf install -y java-17-openjdk || sudo dnf install -y java-17-openjdk-devel
            ;;
        opensuse*|sles)
            sudo zypper install -y java-17-openjdk
            ;;
        arch|manjaro|endeavouros|garuda|arcolinux|cachyos)
            sudo pacman -Sy --noconfirm jre-openjdk || sudo pacman -Sy --noconfirm jdk-openjdk
            ;;
        alpine)
            sudo apk add --no-cache openjdk17-jre
            ;;
        *)
            return 1
            ;;
    esac
}

install_temurin_fallback() {
    print_info "Falling back to Temurin (Adoptium) JRE 17 installation..."

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) TF_ARCH="x64" ;;
        aarch64|arm64) TF_ARCH="aarch64" ;;
        *)
            print_error "Unrecognized architecture: $ARCH. Manual Java installation required."
            return 1
            ;;
    esac

    # Temurin GitHub latest-download path (x64/aarch64 hotspot builds)
    # Example: OpenJDK17U-jre_x64_linux_hotspot.tar.gz
    JRE_NAME="OpenJDK17U-jre_${TF_ARCH}_linux_hotspot.tar.gz"
    DOWNLOAD_URL_TEMURIN="https://github.com/adoptium/temurin17-binaries/releases/latest/download/${JRE_NAME}"
    OUT="$TEMP_DIR/$JRE_NAME"

    print_info "Downloading Temurin JRE 17 for arch=$TF_ARCH ..."
    if has_cmd curl; then
        curl -fL -o "$OUT" "$DOWNLOAD_URL_TEMURIN" || { print_error "Temurin download failed"; return 1; }
    elif has_cmd wget; then
        wget -O "$OUT" "$DOWNLOAD_URL_TEMURIN" || { print_error "Temurin download failed"; return 1; }
    else
        print_error "No curl/wget available to download Temurin."
        return 1
    fi

    if [ ! -s "$OUT" ]; then
        print_error "Downloaded Temurin archive is empty."
        return 1
    fi

    sudo mkdir -p "$TEMURIN_DIR"
    sudo tar -xzf "$OUT" -C /opt
    # The tarball unpacks to a directory like "jdk-17.0.x+xx-jre" or similar; find it
    unpacked_dir=$(tar -tzf "$OUT" | head -n1 | cut -f1 -d"/")
    if [ -z "$unpacked_dir" ]; then
        print_error "Could not identify unpacked Temurin directory."
        return 1
    fi

    sudo rm -rf "${TEMURIN_DIR}"
    sudo mv "/opt/${unpacked_dir}" "${TEMURIN_DIR}"
    sudo chown -R root:root "${TEMURIN_DIR}"

    # Ensure /usr/local/bin/java points to the temurin java
    if [ -f "${TEMURIN_DIR}/bin/java" ]; then
        sudo ln -sf "${TEMURIN_DIR}/bin/java" /usr/local/bin/java
        print_success "Temurin JRE 17 installed to ${TEMURIN_DIR}"
        return 0
    else
        print_error "Temurin bin/java not found after extraction."
        return 1
    fi
}

check_java_version() {
    if ! has_cmd java; then
        return 1
    fi
    JAVA_VERSION_RAW=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
    JAVA_MAJOR=$(echo "$JAVA_VERSION_RAW" | awk -F. '{print ($1 == 1 ? $2 : $1)}' 2>/dev/null || echo "$JAVA_VERSION_RAW")
    if [[ "$JAVA_MAJOR" =~ ^[0-9]+$ ]]; then
        if [ "$JAVA_MAJOR" -ge 17 ]; then
            print_success "Java $JAVA_VERSION_RAW detected (>=17)"
            return 0
        else
            print_warning "Java $JAVA_VERSION_RAW detected (<17)"
            return 2
        fi
    else
        print_warning "Could not parse Java version string: $JAVA_VERSION_RAW"
        return 3
    fi
}

ensure_java_present() {
    # 0 = ok, else try to install
    check_java_version
    rv=$?
    if [ $rv -eq 0 ]; then
        return 0
    fi

    print_warning "Java 17+ not available. Attempting installation via package manager..."
    # try to install via package manager
    if try_java_via_package_manager; then
        print_info "Package-manager install attempted. Re-checking Java..."
        check_java_version
        if [ $? -eq 0 ]; then return 0; fi
    fi

    # if here, package manager didn't produce Java 17
    print_warning "Package manager install didn't provide Java 17. Attempting Temurin fallback..."
    if install_temurin_fallback; then
        check_java_version || { print_error "Java still not available after Temurin install."; exit 1; }
        return 0
    fi

    print_error "Automatic Java installation failed. Please install Java 17+ manually and re-run the script."
    exit 1
}

download_and_prepare_pbo() {
    print_info "Downloading PBO archive..."
    ZIP_OUT="$TEMP_DIR/pbo-windows.zip"
    if has_cmd curl; then
        curl -fL -o "$ZIP_OUT" "$DOWNLOAD_URL"
    elif has_cmd wget; then
        wget -O "$ZIP_OUT" "$DOWNLOAD_URL"
    fi

    if [ ! -s "$ZIP_OUT" ]; then
        print_error "PBO download failed or archive is empty."
        exit 1
    fi

    print_info "Extracting archive..."
    unzip -q "$ZIP_OUT" -d "$TEMP_DIR"
    if [ ! -d "$TEMP_DIR/pbo-windows" ]; then
        # maybe archive layout different: try to move extracted files
        print_warning "Expected directory pbo-windows not present; attempting to find pbo.jar..."
        found=$(find "$TEMP_DIR" -maxdepth 3 -name "pbo.jar" -print -quit || true)
        if [ -z "$found" ]; then
            print_error "pbo.jar not found in the archive. Extraction failed or unexpected layout."
            exit 1
        else
            # create pbo-windows and move all files there
            mkdir -p "$TEMP_DIR/pbo-windows"
            # move everything except zip into pbo-windows
            shopt -s dotglob
            for f in "$TEMP_DIR"/*; do
                if [ "$f" != "$ZIP_OUT" ] && [ "$f" != "$TEMP_DIR/pbo-windows" ]; then
                    mv "$f" "$TEMP_DIR/pbo-windows/" || true
                fi
            done
            shopt -u dotglob
        fi
    fi

    print_info "Removing Windows executables..."
    find "$TEMP_DIR" -name "*.exe" -type f -delete
}

install_pbo() {
    print_info "Installing to $INSTALL_DIR ..."
    # remove old
    if [ -d "$INSTALL_DIR" ]; then
        print_warning "Existing installation found; removing..."
        rm -rf "$INSTALL_DIR"
    fi
    mkdir -p "$(dirname "$INSTALL_DIR")"
    mv "$TEMP_DIR/pbo-windows" "$INSTALL_DIR" || (mkdir -p "$INSTALL_DIR" && mv "$TEMP_DIR"/* "$INSTALL_DIR"/ || true)

    print_info "Creating desktop entry..."
    mkdir -p "$(dirname "$DESKTOP_FILE")"
    cat > "$DESKTOP_FILE" <<EOF
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
    if has_cmd update-desktop-database; then
        update-desktop-database "$HOME/.local/share/applications/" || true
    fi

    print_success "$APP_NAME installed successfully!"
    print_info "Installation directory: $INSTALL_DIR"
}

uninstall_pbo() {
    print_info "Uninstalling $APP_NAME ..."
    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
        print_success "Removed $INSTALL_DIR"
    else
        print_warning "No installation directory found at $INSTALL_DIR"
    fi
    if [ -f "$DESKTOP_FILE" ]; then
        rm -f "$DESKTOP_FILE"
        print_success "Removed desktop file $DESKTOP_FILE"
    fi
    if has_cmd update-desktop-database; then
        update-desktop-database "$HOME/.local/share/applications/" || true
    fi
}

# --------------------
# Main
# --------------------
if [[ "${1:-}" == "--uninstall" || "${1:-}" == "-u" ]]; then
    detect_distro
    uninstall_pbo
    exit 0
fi

# allow --force to bypass some checks
if [[ "${1:-}" == "--force" || "${2:-}" == "--force" ]]; then
    FORCE=true
fi

print_info "Starting $APP_NAME installer..."
detect_distro
ensure_basic_tools
ensure_java_present
download_and_prepare_pbo
install_pbo
print_success "Installation completed. Viel Spaß!"

# End of script
