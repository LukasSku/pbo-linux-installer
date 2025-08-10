#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

APP_NAME="Pokemon Blaze Online"
INSTALL_DIR="$HOME/Applications/pbo"
DESKTOP_FILE="$HOME/.local/share/applications/pbo.desktop"
TEMP_DIR="/tmp/pbo-installer"
DOWNLOAD_URL="https://pbo-downloads.s3.eu-central-003.backblazeb2.com/pbo-windows.zip"

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

detect_package_manager() {
    if command -v apt >/dev/null; then
        PKG_MGR="apt"
    elif command -v dnf >/dev/null; then
        PKG_MGR="dnf"
    elif command -v yum >/dev/null; then
        PKG_MGR="yum"
    elif command -v pacman >/dev/null; then
        PKG_MGR="pacman"
    elif command -v zypper >/dev/null; then
        PKG_MGR="zypper"
    elif command -v apk >/dev/null; then
        PKG_MGR="apk"
    else
        PKG_MGR="unknown"
    fi
    print_info "Package manager detected: $PKG_MGR"
}

install_package() {
    local pkg=$1
    case "$PKG_MGR" in
        apt)
            sudo apt update
            sudo apt install -y "$pkg"
            ;;
        dnf)
            sudo dnf install -y "$pkg"
            ;;
        yum)
            sudo yum install -y "$pkg"
            ;;
        pacman)
            sudo pacman -Syu --noconfirm "$pkg"
            ;;
        zypper)
            sudo zypper install -y "$pkg"
            ;;
        apk)
            sudo apk add "$pkg"
            ;;
        *)
            print_warning "Kein unterstützter Paketmanager gefunden. Bitte installiere '$pkg' manuell."
            return 1
            ;;
    esac
}

check_java() {
    if ! command -v java >/dev/null 2>&1; then
        return 1
    fi
    # Prüfe Java Version (mindestens 17)
    local ver=$(java -version 2>&1 | head -n1 | grep -oP '"\K[0-9]+')
    if [[ "$ver" -ge 17 ]]; then
        return 0
    else
        return 1
    fi
}

install_java() {
    print_info "Java 17+ nicht gefunden. Versuche Java zu installieren..."

    case "$PKG_MGR" in
        apt)
            sudo apt update
            sudo apt install -y openjdk-17-jre
            ;;
        dnf|yum)
            sudo "$PKG_MGR" install -y java-17-openjdk
            ;;
        pacman)
            sudo pacman -Syu --noconfirm jre-openjdk
            ;;
        zypper)
            sudo zypper install -y java-17-openjdk
            ;;
        apk)
            sudo apk add openjdk17
            ;;
        *)
            print_warning "Automatische Installation für Java nicht möglich."
            print_info "Versuche portable OpenJDK von Adoptium zu installieren..."

            install_portable_java
            ;;
    esac
}

install_portable_java() {
    local jdk_dir="$HOME/.local/java"
    local jdk_url="https://github.com/adoptium/temurin17-binaries/releases/latest/download/OpenJDK17U-jre_x64_linux_hotspot.tar.gz"

    mkdir -p "$jdk_dir"
    print_info "Lade OpenJDK 17 von Adoptium herunter..."
    if command -v curl >/dev/null 2>&1; then
        curl -L -o "$TEMP_DIR/jdk.tar.gz" "$jdk_url"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$TEMP_DIR/jdk.tar.gz" "$jdk_url"
    else
        print_error "Kein curl oder wget verfügbar, kann OpenJDK nicht herunterladen."
        exit 1
    fi

    print_info "Entpacke OpenJDK..."
    tar -xzf "$TEMP_DIR/jdk.tar.gz" -C "$jdk_dir" --strip-components=1

    export PATH="$jdk_dir/bin:$PATH"
    print_success "Portable Java 17 installiert und im PATH hinzugefügt."
}

download_pbo() {
    print_info "Erstelle temporäres Verzeichnis: $TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    print_info "Lade PBO herunter..."
    if command -v curl >/dev/null 2>&1; then
        curl -L -o pbo.zip "$DOWNLOAD_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -O pbo.zip "$DOWNLOAD_URL"
    else
        print_error "Kein curl oder wget gefunden. Bitte installieren."
        exit 1
    fi
}

extract_pbo() {
    print_info "Entpacke PBO..."
    unzip -q pbo.zip -d pbo-temp
    print_info "Entferne Windows .exe Dateien..."
    find pbo-temp -type f -name "*.exe" -delete
}

install_pbo() {
    print_info "Installiere PBO nach $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALL_DIR"/*
    mv pbo-temp/* "$INSTALL_DIR"
}

create_desktop_entry() {
    print_info "Erstelle Desktop-Verknüpfung..."

    mkdir -p "$(dirname "$DESKTOP_FILE")"

    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Name=$APP_NAME
Comment=Pokemon Blaze Online Client
Exec=java -jar "$INSTALL_DIR/pbo.jar"
Icon=$INSTALL_DIR/pbo.png
Terminal=false
Type=Application
Categories=Game;
EOF

    chmod +x "$DESKTOP_FILE"

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$HOME/.local/share/applications/"
    fi
    print_success "Desktop-Verknüpfung erstellt"
}

cleanup() {
    print_info "Bereinige temporäre Dateien..."
    rm -rf "$TEMP_DIR"
}

main() {
    print_info "Starte Installation von $APP_NAME..."

    detect_package_manager

    # Grundtools prüfen
    for tool in unzip curl java; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            if [ "$tool" = "java" ]; then
                print_warning "Java nicht gefunden"
            else
                print_info "Installiere fehlendes Tool: $tool"
                install_package "$tool" || print_warning "Bitte installiere $tool manuell"
            fi
        fi
    done

    # Java Version prüfen
    if ! check_java; then
        install_java
        if ! check_java; then
            print_error "Java 17+ konnte nicht installiert werden. Bitte manuell installieren."
            exit 1
        fi
    else
        print_success "Java 17+ ist installiert"
    fi

    download_pbo
    extract_pbo
    install_pbo
    create_desktop_entry
    cleanup

    print_success "$APP_NAME wurde erfolgreich installiert!"
    print_info "Starte das Spiel mit: java -jar $INSTALL_DIR/pbo.jar"
}

trap cleanup EXIT
main "$@"
