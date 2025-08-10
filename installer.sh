#!/usr/bin/env bash
set -euo pipefail

# Farbcode für Ausgaben
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
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO=${ID,,}
        DISTRO_LIKE=${ID_LIKE,,}
        # Falls ID_LIKE leer: Spezielle Behandlung
        if [[ -z "$DISTRO_LIKE" ]]; then
            if [[ "$DISTRO" == "cachyos" ]]; then
                DISTRO_LIKE="arch"
            fi
        fi
    else
        DISTRO="unknown"
        DISTRO_LIKE=""
    fi
    print_info "Detected distribution: $DISTRO (ID_LIKE=$DISTRO_LIKE)"
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

install_pkg_generic() {
    # install_pkg_generic <command_hint> <apt_pkg> <dnf_pkg> <pacman_pkg> <zypper_pkg> <apk_pkg>
    local cmd_hint="$1"; shift
    local apt_pkg="$1"; shift
    local dnf_pkg="$1"; shift
    local pacman_pkg="$1"; shift
    local zypper_pkg="$1"; shift
    local apk_pkg="$1"; shift

    if has_cmd "$cmd_hint"; then
        print_success "$cmd_hint is already installed"
        return 0
    fi

    print_info "Attempting to install '$cmd_hint' via package manager..."

    case "$DISTRO" in
        ubuntu|debian|pop|linuxmint|elementary)
            if [ -n "$apt_pkg" ]; then
                sudo apt-get update -y
                if ! sudo apt-get install -y "$apt_pkg"; then
                    print_warning "apt install of $apt_pkg failed."
                    return 1
                fi
            fi
            ;;
        fedora|rhel|centos)
            if [ -n "$dnf_pkg" ]; then
                if ! sudo dnf install -y "$dnf_pkg"; then
                    print_warning "dnf install of $dnf_pkg failed."
                    return 1
                fi
            fi
            ;;
        opensuse*|sles)
            if [ -n "$zypper_pkg" ]; then
                if ! sudo zypper install -y "$zypper_pkg"; then
                    print_warning "zypper install of $zypper_pkg failed."
                    return 1
                fi
            fi
            ;;
        arch|manjaro|endeavouros|garuda|arcolinux|cachyos)
            if [ -n "$pacman_pkg" ]; then
                sudo pacman -Sy --noconfirm "$pacman_pkg" || {
                    print_warning "pacman install of $pacman_pkg failed."
                    return 1
                }
            fi
            ;;
        alpine)
            if [ -n "$apk_pkg" ]; then
                if ! sudo apk add --no-cache "$apk_pkg"; then
                    print_warning "apk add of $apk_pkg failed."
                    return 1
                fi
            fi
            ;;
        *)
            # Versuche anhand ID_LIKE heuristisch
            if [[ "$DISTRO_LIKE" == *"debian"* ]] && [ -n "$apt_pkg" ]; then
                sudo apt-get update -y
                if ! sudo apt-get install -y "$apt_pkg"; then
                    print_warning "apt install of $apt_pkg failed."
                    return 1
                fi
            elif [[ "$DISTRO_LIKE" == *"arch"* ]] && [ -n "$pacman_pkg" ]; then
                sudo pacman -Sy --noconfirm "$pacman_pkg" || {
                    print_warning "pacman install of $pacman_pkg failed."
                    return 1
                }
            else
                print_warning "Unsupported distro $DISTRO for installing $cmd_hint"
                return 1
            fi
            ;;
    esac

    # nochmal prüfen, ob cmd_hint jetzt da ist
    if has_cmd "$cmd_hint"; then
        print_success "$cmd_hint installed successfully"
        return 0
    else
        print_warning "$cmd_hint installation not successful"
        return 1
    fi
}

ensure_basic_tools() {
    if ! has_cmd curl && ! has_cmd wget; then
        print_info "curl oder wget fehlt, versuche curl zu installieren"
        install_pkg_generic curl curl curl curl curl curl || print_warning "curl konnte nicht installiert werden."
    fi
    if ! has_cmd unzip; then
        install_pkg_generic unzip unzip unzip unzip unzip unzip || print_warning "unzip konnte nicht installiert werden."
    fi
}

try_install_java_pkg() {
    print_info "Versuche Java 17 via Paketmanager zu installieren..."
    case "$DISTRO" in
        ubuntu|debian|pop|linuxmint|elementary)
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
            print_warning "Automatische Java-Installation nicht für $DISTRO unterstützt."
            return 1
            ;;
    esac
}

install_temurin() {
    print_info "Temurin JRE 17 wird als Fallback installiert..."

    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) arch_t="x64" ;;
        aarch64|arm64) arch_t="aarch64" ;;
        *)
            print_error "Architektur $arch wird nicht unterstützt. Bitte manuell Java 17 installieren."
            return 1
            ;;
    esac

    JRE_TAR="OpenJDK17U-jre_${arch_t}_linux_hotspot.tar.gz"
    URL="https://github.com/adoptium/temurin17-binaries/releases/latest/download/$JRE_TAR"
    OUT="$TEMP_DIR/$JRE_TAR"

    print_info "Lade $JRE_TAR herunter..."
    if has_cmd curl; then
        curl -fL -o "$OUT" "$URL" || { print_error "Download fehlgeschlagen"; return 1; }
    elif has_cmd wget; then
        wget -O "$OUT" "$URL" || { print_error "Download fehlgeschlagen"; return 1; }
    else
        print_error "Weder curl noch wget zum Download vorhanden."
        return 1
    fi

    sudo mkdir -p "$TEMURIN_DIR"
    sudo tar -xzf "$OUT" -C /opt
    local_dir=$(tar -tf "$OUT" | head -1 | cut -f1 -d"/")
    if [ -z "$local_dir" ]; then
        print_error "Konnte entpacktes Verzeichnis nicht bestimmen."
        return 1
    fi
    sudo rm -rf "$TEMURIN_DIR"
    sudo mv "/opt/$local_dir" "$TEMURIN_DIR"
    sudo chown -R root:root "$TEMURIN_DIR"

    if [ -f "$TEMURIN_DIR/bin/java" ]; then
        sudo ln -sf "$TEMURIN_DIR/bin/java" /usr/local/bin/java
        print_success "Temurin JRE 17 wurde installiert."
        return 0
    else
        print_error "Java-Binary nicht gefunden nach Temurin Installation."
        return 1
    fi
}

check_java_version() {
    if ! has_cmd java; then
        return 1
    fi
    version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
    major=$(echo "$version" | awk -F. '{if ($1 == "1") print $2; else print $1}')
    if [[ $major =~ ^[0-9]+$ ]] && [ "$major" -ge 17 ]; then
        print_success "Java Version $version gefunden (>=17)."
        return 0
    else
        print_warning "Java Version $version gefunden (<17)."
        return 2
    fi
}

ensure_java() {
    check_java_version
    local rv=$?
    if [ $rv -eq 0 ]; then
        return 0
    fi

    print_warning "Java 17+ nicht gefunden. Versuche automatische Installation..."

    if try_install_java_pkg; then
        check_java_version && return 0
    fi

    print_warning "Paketmanager konnte Java 17 nicht installieren, installiere Temurin fallback..."

    if install_temurin; then
        check_java_version && return 0
    fi

    print_error "Automatische Java-Installation gescheitert. Bitte installiere Java 17+ manuell."
    exit 1
}

download_pbo() {
    print_info "Lade PBO Archiv herunter..."
    ZIP="$TEMP_DIR/pbo-windows.zip"
    if has_cmd curl; then
        curl -fL -o "$ZIP" "$DOWNLOAD_URL"
    elif has_cmd wget; then
        wget -O "$ZIP" "$DOWNLOAD_URL"
    else
        print_error "Kein curl oder wget gefunden zum Download."
        exit 1
    fi
    if [ ! -s "$ZIP" ]; then
        print_error "Download fehlgeschlagen oder Archiv ist leer."
        exit 1
    fi
}

extract_pbo() {
    print_info "Entpacke Archiv..."
    unzip -q "$TEMP_DIR/pbo-windows.zip" -d "$TEMP_DIR"
    if [ ! -d "$TEMP_DIR/pbo-windows" ]; then
        print_warning "pbo-windows Verzeichnis nicht gefunden, versuche alternative Struktur..."
        found=$(find "$TEMP_DIR" -name "pbo.jar" -print -quit || true)
        if [ -z "$found" ]; then
            print_error "pbo.jar nicht gefunden, Archivstruktur unbekannt."
            exit 1
        fi
        mkdir -p "$TEMP_DIR/pbo-windows"
        shopt -s dotglob
        for f in "$TEMP_DIR"/*; do
            if [[ "$f" != "$TEMP_DIR/pbo-windows.zip" && "$f" != "$TEMP_DIR/pbo-windows" ]]; then
                mv "$f" "$TEMP_DIR/pbo-windows/"
            fi
        done
        shopt -u dotglob
    fi
    print_info "Entferne Windows-Executables..."
    find "$TEMP_DIR" -name "*.exe" -type f -delete
}

install_pbo() {
    print_info "Installiere PBO nach $INSTALL_DIR..."
    if [ -d "$INSTALL_DIR" ]; then
        print_warning "Alte Installation gefunden, lösche..."
        rm -rf "$INSTALL_DIR"
    fi
    mkdir -p "$(dirname "$INSTALL_DIR")"
    mv "$TEMP_DIR/pbo-windows" "$INSTALL_DIR"
}

create_desktop_entry() {
    print_info "Erstelle Desktop-Verknüpfung..."

    mkdir -p "$(dirname "$DESKTOP_FILE")"

    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Name=Pokemon Blaze Online
Comment=Pokemon Blaze Online Client
Exec=java -jar "$INSTALL_DIR/pbo.jar"
Icon=$INSTALL_DIR/pbo.png
Terminal=false
Type=Application
Categories=Game;
EOF

    chmod +x "$DESKTOP_FILE"
    print_success "Desktop-Verknüpfung erstellt: $DESKTOP_FILE"
}

main() {
    print_info "Starte $APP_NAME Installer..."

    detect_distro

    ensure_basic_tools

    ensure_java

    download_pbo

    extract_pbo

    install_pbo

    create_desktop_entry

    print_success "$APP_NAME wurde erfolgreich installiert!"
}

main
