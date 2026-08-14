#!/bin/bash

# ==========================================================
# KOMPLEKSOWY SKRYPT KONFIGURACYJNY SYSTEMU FEDORA
# ==========================================================

set -euo pipefail

# ── Wykrywanie języka systemu ──────────────────────────────────
# Jeśli system jest ustawiony na polski (pl_PL/pl_*) -> komunikaty PL,
# w każdym innym przypadku -> komunikaty EN.
detect_system_lang() {
    local sys_lang="${LANG:-}"
    [[ -z "$sys_lang" ]] && sys_lang="${LC_ALL:-${LC_MESSAGES:-}}"
    if [[ "$sys_lang" == pl_PL* || "$sys_lang" == pl* ]]; then
        echo "pl"
    else
        echo "en"
    fi
}
SCRIPT_LANG="$(detect_system_lang)"

# ── Kolory ────────────────────────────────────────────────────
INFO='\033[0;34m'
SUCCESS='\033[0;32m'
WARN='\033[0;33m'
ERR='\033[0;31m'
NC='\033[0m'

# ── System logowania ───────────────────────────────────────────
# Zasada: na ekranie widoczne są TYLKO ważne komunikaty ogólne (log_info / log_ok / log_error).
# Wszystko inne (log_warn, wyjście poleceń, dnf, rpm itp.) trafia WYŁĄCZNIE do pliku logu.
# Plik logu jest tworzony na stałe tylko wtedy, gdy wystąpi błąd.
TMP_LOG="$(mktemp /tmp/fedora-install-log.XXXXXX)"
LOG_FILE="$HOME/install_error_$(date +%Y%m%d_%H%M%S).log"

# fd 3 = prawdziwy terminal (do wyświetlania ważnych komunikatów),
# fd 1/2 od teraz lądują wyłącznie w pliku tymczasowym (ukryte).
exec 3>&1
exec >>"$TMP_LOG" 2>&1

cleanup_on_exit() {
    local exit_code=$?
    if [ "$exit_code" -ne 0 ]; then
        cp -f "$TMP_LOG" "$LOG_FILE" 2>/dev/null || true
        if [[ "$SCRIPT_LANG" == "pl" ]]; then
            echo -e "${ERR}✘ Wystąpił błąd (kod: $exit_code). Szczegółowy log zapisano w: $LOG_FILE${NC}" >&3
        else
            echo -e "${ERR}✘ An error occurred (code: $exit_code). Detailed log saved to: $LOG_FILE${NC}" >&3
        fi
    fi
    rm -f "$TMP_LOG"
}
trap cleanup_on_exit EXIT

# ── Pomocnicze funkcje logowania ──────────────────────────────
# Każda funkcja przyjmuje: "$1" = tekst PL, "$2" = tekst EN
_pick_msg() { [[ "$SCRIPT_LANG" == "pl" ]] && echo "$1" || echo "$2"; }

log_info()  { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${INFO}==> $m${NC}" >&3; echo -e "${INFO}==> $m${NC}"; }
log_ok()    { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${SUCCESS}✔ $m${NC}" >&3; echo -e "${SUCCESS}✔ $m${NC}"; }
log_error() { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${ERR}✘ $m${NC}" >&3; echo -e "${ERR}✘ $m${NC}"; }
# log_warn: celowo NIE trafia na ekran (fd 3) - tylko do logu w tle
log_warn()  { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${WARN}⚠ $m${NC}"; }

# Sprawdzenie uprawnień (skrypt NIE może być uruchamiany bezpośrednio jako root)
if [[ "$EUID" -eq 0 ]]; then
    log_error "Nie uruchamiaj skryptu jako root. Uruchom jako zwykły użytkownik z uprawnieniami sudo." \
              "Do not run this script as root. Run as a regular user with sudo privileges."
    exit 1
fi

# ── Zmienne globalne ───────────────────────────────────────────
CURRENT_USER=$(whoami)
ACTUAL_USER="${SUDO_USER:-$USER}"
RPM_DIR="/tmp/rpms_$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"


# ==========================================================
# 1. PRZYGOTOWANIE ŚRODOWISKA UŻYTKOWNIKA
# ==========================================================
log_info "Przygotowanie środowiska użytkownika..." \
         "Preparing user environment..."

if [ -f "$SCRIPT_DIR/.update.sh" ]; then
    cp -af "$SCRIPT_DIR/.update.sh" ~/.update.sh
    chmod +x ~/.update.sh
fi

# Kopiowanie .local i .config do katalogu domowego
if [ -d "$SCRIPT_DIR/.local" ]; then
    mkdir -p ~/.local
    cp -afT "$SCRIPT_DIR/.local" ~/.local
    log_ok "Skopiowano katalog '.local' do \$HOME" \
           "Copied '.local' directory to \$HOME"
else
    log_warn "Brak katalogu '.local' w katalogu skryptu – pominięto" \
             "No '.local' directory in script folder – skipped"
fi

if [ -d "$SCRIPT_DIR/.config" ]; then
    mkdir -p ~/.config
    cp -afT "$SCRIPT_DIR/.config" ~/.config
    log_ok "Skopiowano katalog '.config' do \$HOME" \
           "Copied '.config' directory to \$HOME"
else
    log_warn "Brak katalogu '.config' w katalogu skryptu – pominięto" \
             "No '.config' directory in script folder – skipped"
fi


# ==========================================================
# 2. KONFIGURACJA SYSTEMOWA (SUDO)
# ==========================================================
log_info "Rozpoczynanie konfiguracji systemowej..." \
         "Starting system configuration..."

# Tymczasowy wyjątek sudo dla DNF/RPM (by nie pytało o hasło podczas długiej instalacji)
sudo -v
echo "$CURRENT_USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/99-temp-installer > /dev/null

# Agresywne zatrzymanie usług w tle, w tym dnf5-makecache
log_info "Zatrzymywanie usług w tle (PackageKit, DNF5)..." \
         "Stopping background services (PackageKit, DNF5)..."
sudo systemctl stop packagekit.service dnf-makecache.timer dnf-makecache.service dnf5-makecache.timer dnf5-makecache.service 2>/dev/null || true
sudo systemctl mask packagekit.service dnf-makecache.timer dnf-makecache.service dnf5-makecache.timer dnf5-makecache.service 2>/dev/null || true
sudo killall -9 packagekitd dnf dnf5 rpm 2>/dev/null || true

# Optymalizacja DNF5 pod kątem sieci
log_info "Optymalizacja menedżera pakietów DNF5..." \
         "Optimizing DNF5 package manager..."
for DNF_CONF in /etc/dnf/dnf.conf /etc/dnf/dnf5.conf; do
    if [[ -f "$DNF_CONF" ]]; then
        sudo sed -i '/^fastestmirror=/d; /^retries=/d; /^timeout=/d; /^max_parallel_downloads=/d; /^ip_resolve=/d' "$DNF_CONF"
        echo -e "fastestmirror=False\nmax_parallel_downloads=10\nretries=10\ntimeout=120\nip_resolve=4" | sudo tee -a "$DNF_CONF" > /dev/null
    fi
done

wait_for_rpm_lock() {
    local i=0
    while pgrep -x dnf >/dev/null || pgrep -x dnf5 >/dev/null || pgrep -x packagekitd >/dev/null || pgrep -x rpm >/dev/null; do
        if (( i++ >= 24 )); then
            log_warn "Blokada RPM nadal zajęta po 120s — wymuszam czyszczenie..." \
                     "RPM lock still busy after 120s — forcing cleanup..."
            sudo systemctl stop packagekit.service dnf-makecache.service dnf5-makecache.service 2>/dev/null || true
            sudo killall -9 dnf dnf5 rpm packagekitd 2>/dev/null || true
            sudo rm -f /var/lib/rpm/.rpm.lock /usr/lib/sysimage/rpm/.rpm.lock /var/cache/libdnf5/*.lock 2>/dev/null || true
            break
        fi
        sleep 5
    done
}

# Instalacja podstawowych narzędzi skryptowych
wait_for_rpm_lock
sudo dnf5 install -y wget curl pciutils

# --- Repozytoria RPM Fusion ---
FEDORA_VER=$(rpm -E %fedora)
log_info "Wykryta wersja Fedory: $FEDORA_VER" \
         "Detected Fedora version: $FEDORA_VER"

wait_for_rpm_lock
sudo dnf5 install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm" \
    || log_warn "Część repozytoriów RPM Fusion już zainstalowana lub niedostępna" \
                "Some RPM Fusion repositories are already installed or unavailable"

# --- Chrome ---
log_info "Konfiguracja repozytorium i instalacja Google Chrome..." \
         "Configuring repository and installing Google Chrome..."

OLD_GOOGLE_KEYS=$(rpm -qa 'gpg-pubkey*' --qf '%{NAME}-%{VERSION}-%{RELEASE} %{PACKAGER}\n' 2>/dev/null \
    | grep -i 'linux-packages-keymaster@google.com\|Google, Inc' \
    | cut -d' ' -f1 || true)
if [[ -n "$OLD_GOOGLE_KEYS" ]]; then
    sudo rpm -e $OLD_GOOGLE_KEYS 2>/dev/null || true
fi
sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub || log_warn "Błąd pobierania klucza Google, pomijam." "Error downloading Google key, skipping."

sudo tee /etc/yum.repos.d/google-chrome.repo > /dev/null <<'EOF'
[google-chrome]
name=Google Chrome
baseurl=http://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF

wait_for_rpm_lock
sudo dnf5 install -y google-chrome-stable

# --- Brave (Origin) ---
log_info "Konfiguracja repozytorium i instalacja Brave Origin..." \
         "Configuring repository and installing Brave Origin..."
wait_for_rpm_lock
sudo dnf5 install -y dnf-plugins-core gnupg2

BRAVE_KEY_ID="0686B78420038257"
if ! sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc 2>/dev/null; then
    BRAVE_GNUPGHOME="$(mktemp -d)"
    if ! gpg --homedir "$BRAVE_GNUPGHOME" --keyserver hkps://keyserver.ubuntu.com --recv-keys "$BRAVE_KEY_ID" 2>/dev/null; then
        gpg --homedir "$BRAVE_GNUPGHOME" --keyserver hkps://keys.openpgp.org --recv-keys "$BRAVE_KEY_ID" || true
    fi
    gpg --homedir "$BRAVE_GNUPGHOME" --armor --export "$BRAVE_KEY_ID" > "$BRAVE_GNUPGHOME/brave-core.asc" 2>/dev/null || true
    sudo rpm --import "$BRAVE_GNUPGHOME/brave-core.asc" 2>/dev/null || log_warn "Nie udało się zaimportować klucza GPG dla Brave" "Failed to import Brave GPG key"
    rm -rf "$BRAVE_GNUPGHOME"
fi

sudo dnf5 config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo

wait_for_rpm_lock
sudo dnf5 install -y brave-origin

# --- Narzędzia deweloperskie ---
wait_for_rpm_lock
sudo dnf5 install -y @development-tools @c-development || log_warn "Część grup deweloperskich nie powiodła się" "Some development groups failed to install"
sudo dnf5 install -y gcc gcc-c++ make || log_warn "Część narzędzi deweloperskich nie powiodła się" "Some development tools failed to install"

# --- Czyszczenie zbędnych pakietów ---
log_info "Usuwanie zbędnych pakietów..." \
         "Removing unnecessary packages..."
TO_REMOVE=(
    nano konqueror plasma-browser-integration plasma-vault krdp krfb
    plasma-thunderbolt kontact kmail kontrast plasma-welcome imagemagick
    kaddressbook kdepim-runtime akonadi-server akregator korganizer
    epiphany decibels rhythmbox showtime cosmic-player parole kwalletmanager
)
wait_for_rpm_lock
sudo dnf5 remove -y "${TO_REMOVE[@]}" 2>/dev/null \
    || log_warn "Część pakietów do usunięcia nie była zainstalowana" "Some packages to remove were not installed"
sudo dnf5 autoremove -y

# Czyszczenie danych po Akonadi/KMail/Kontact
rm -rf ~/.local/share/akonadi ~/.local/share/kmail2 ~/.local/share/local-mail
rm -rf ~/.local/share/contacts ~/.local/share/korganizer ~/.local/share/akregator ~/.local/share/kontact
rm -rf ~/.config/akonadi* ~/.config/kmail* ~/.config/kontact* ~/.config/korganizer*
rm -rf ~/.config/kaddressbook* ~/.config/akregator* ~/.config/emailidentities ~/.config/mailtransports

# Wyłączenie KDE Wallet (Portfela)
log_info "Wyłączanie usługi KDE Wallet..." \
         "Disabling KDE Wallet service..."
mkdir -p ~/.config
if [[ -f ~/.config/kwalletrc ]]; then
    if grep -q "^\[Wallet\]" ~/.config/kwalletrc; then
        sed -i '/^\[Wallet\]/,/^\[/{s/^Enabled=.*/Enabled=false/}' ~/.config/kwalletrc
        grep -q "^Enabled=" ~/.config/kwalletrc || sed -i '/^\[Wallet\]/a Enabled=false' ~/.config/kwalletrc
    else
        printf '[Wallet]\nEnabled=false\n' >> ~/.config/kwalletrc
    fi
else
    printf '[Wallet]\nEnabled=false\n' > ~/.config/kwalletrc
fi

# --- Główna lista pakietów ---
PACKAGES=(
    # Narzędzia systemowe
    dconf-editor hunspell-pl fastfetch unrar git mc exfatprogs ntfs-3g vim
    os-prober android-tools fsarchiver inxi pv rsync python3-defusedxml
    python3-packaging python3-pip pipx 7zip zenity innoextract makeself
    dnf-plugins-core bleachbit timeshift cdemu-daemon cdemu-client

    # Multimedia
    audacity gimp gmic mixxx kdenlive soundconverter handbrake-gui vlc elisa krita

    # Internet / komunikatory
    telegram-desktop qbittorrent thunderbird

    # Wine
    wine winetricks

    # Gaming / Vulkan / render
    gamemode vulkan-tools gamescope mangohud goverlay

    # Kompilatory i build tools
    cmake meson ninja-build python3-tqdm just

    # GStreamer
    gstreamer1-plugins-good gstreamer1-plugins-bad-free gstreamer1-plugins-ugly

    # Bluetooth
    bluez-tools

    # Powłoka
    zsh zsh-syntax-highlighting zsh-autosuggestions

    # Appindicator
    libayatana-appindicator
)

wait_for_rpm_lock
log_info "Instalacja głównej listy pakietów..." \
         "Installing main package list..."
sudo dnf5 install -y --skip-unavailable "${PACKAGES[@]}" \
    || log_warn "Część pakietów nie powiodła się — kontynuuję" "Some packages failed — continuing"


# ==========================================================
# 3. WYKRYWANIE GPU: BIBLIOTEKI 32-BIT I DRACUT (EARLY KMS)
# ==========================================================
log_info "Wykrywanie GPU oraz konfiguracja bibliotek 32-bit i dracut..." \
         "Detecting GPU and configuring 32-bit libraries & dracut..."

PACKAGES_32=(
    glibc.i686 libstdc++.i686 libgcc.i686 vulkan-loader.i686
    wine.i686
    alsa-lib.i686 pipewire-alsa.i686 pipewire-libs.i686
    pulseaudio-libs.i686 openal-soft.i686
    mangohud.i686 gamemode.i686
    openssl-libs.i686 nss.i686 nspr.i686
    libXcomposite.i686 libXcursor.i686 libXdamage.i686
    libXext.i686 libXfixes.i686 libXi.i686
    libXrandr.i686 libXrender.i686 libXtst.i686
    libxkbcommon.i686
)

GPU_INFO=$(lspci -nn | grep -iE "VGA|3D|Display" || true)
DRACUT_CONF="/etc/dracut.conf.d/90-gpu.conf"

if echo "$GPU_INFO" | grep -iq "NVIDIA"; then
    log_info "Wykryto kartę graficzną NVIDIA." "Detected NVIDIA GPU."
    PACKAGES_32+=(xorg-x11-drv-nvidia-libs.i686 xorg-x11-drv-nvidia-cuda-libs.i686)
    echo 'force_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "' | sudo tee "$DRACUT_CONF" > /dev/null

elif echo "$GPU_INFO" | grep -iqE "AMD|Radeon"; then
    log_info "Wykryto kartę graficzną AMD." "Detected AMD GPU."
    PACKAGES_32+=(mesa-dri-drivers.i686 mesa-vulkan-drivers.i686 mesa-libGL.i686)
    echo 'force_drivers+=" amdgpu "' | sudo tee "$DRACUT_CONF" > /dev/null

elif echo "$GPU_INFO" | grep -iq "Intel"; then
    log_info "Wykryto kartę graficzną Intel." "Detected Intel GPU."
    PACKAGES_32+=(mesa-dri-drivers.i686 mesa-vulkan-drivers.i686 mesa-libGL.i686)
    echo 'force_drivers+=" i915 "' | sudo tee "$DRACUT_CONF" > /dev/null

else
    log_warn "Nie rozpoznano jednoznacznie karty graficznej. Instaluję pakiety Mesa jako domyślne." \
             "Unrecognized GPU. Installing default Mesa packages."
    PACKAGES_32+=(mesa-dri-drivers.i686 mesa-vulkan-drivers.i686 mesa-libGL.i686)
    sudo rm -f "$DRACUT_CONF"
fi

wait_for_rpm_lock
sudo dnf5 install -y --skip-unavailable "${PACKAGES_32[@]}" \
    || log_warn "Część bibliotek 32-bitowych nie powiodła się — kontynuuję" "Some 32-bit libraries failed — continuing"

# Przebudowa initramfs dla dracut
if [[ -f "$DRACUT_CONF" ]]; then
    log_info "Przebudowa obrazu initramfs (dracut) dla wczesnego KMS..." \
             "Rebuilding initramfs image (dracut) for early KMS..."
    sudo dracut --force
fi

# --- Pakiety RPM (Discord, ls-fg, Faugus) ---
log_info "Pobieranie i instalacja pakietów RPM..." \
         "Downloading and installing RPM packages..."
mkdir -p "$RPM_DIR"

download_rpm() {
    local name="$1" url="$2" dldest="$3"
    if wget -q --timeout=30 -O "$dldest" "$url"; then
        log_ok "Pobrano: $name" "Downloaded: $name"
    else
        log_warn "Nie udało się pobrać: $name ($url) — pomijam" "Failed to download: $name ($url) — skipping"
        rm -f "$dldest"
    fi
}

# Discord
wait_for_rpm_lock
if sudo dnf5 repolist 2>/dev/null | grep -iq "rpmfusion-nonfree"; then
    if sudo dnf5 install -y discord; then
        log_ok "Discord zainstalowany przez dnf5." "Discord installed via dnf5."
    else
        log_warn "Błąd podczas instalacji Discorda przez dnf5." "Error installing Discord via dnf5."
    fi
else
    log_warn "Repozytorium RPM Fusion Nonfree nie jest włączone. Próbuję pobrać RPM ręcznie..." \
             "RPM Fusion Nonfree is not enabled. Attempting manual RPM download..."
    dest="/tmp/discord.rpm"
    if wget -q --user-agent="Mozilla/5.0" "https://discord.com/api/download?platform=linux&format=rpm" -O "$dest"; then
        if file "$dest" | grep -q "RPM"; then
            sudo dnf5 install -y "$dest"
            rm -f "$dest"
        else
            log_warn "Pobrany plik nie jest poprawną paczką RPM." "Downloaded file is not a valid RPM package."
            rm -f "$dest"
        fi
    fi
fi

# ls-fg i ls-fg-vk
LSFG_URL=$(curl -sf https://api.github.com/repos/YuriSizov/ls-fg/releases/latest \
    | grep "browser_download_url.*ls-fg_.*rpm" | cut -d '"' -f 4 || true)
[[ -n "$LSFG_URL" ]] && download_rpm "ls-fg" "$LSFG_URL" "$RPM_DIR/lsfg.rpm"

LSFG_VK_URL=$(curl -sf https://api.github.com/repos/YuriSizov/ls-fg-vk/releases/latest \
    | grep "browser_download_url.*rpm" | cut -d '"' -f 4 || true)
[[ -n "$LSFG_VK_URL" ]] && download_rpm "ls-fg-vk" "$LSFG_VK_URL" "$RPM_DIR/lsfg-vk.rpm"

# Faugus Launcher
wait_for_rpm_lock
sudo dnf5 -y copr enable faugus/faugus-launcher \
    && sudo dnf5 --refresh -y install faugus-launcher \
    && log_ok "Faugus Launcher zainstalowany" "Faugus Launcher installed" \
    || log_warn "Instalacja Faugus Launcher nie powiodła się" "Faugus Launcher installation failed"

# Instaluj pobrane pliki RPM
shopt -s nullglob
RPM_FILES=("$RPM_DIR"/*.rpm)
if [[ ${#RPM_FILES[@]} -gt 0 ]]; then
    wait_for_rpm_lock
    sudo dnf5 install -y "${RPM_FILES[@]}"
else
    log_warn "Brak pobranych pakietów RPM do zainstalowania." "No downloaded RPM packages to install."
fi
shopt -u nullglob
rm -rf "$RPM_DIR"

# --- Wirtualizacja ---
log_info "Konfiguracja wirtualizacji..." \
         "Configuring virtualization..."
wait_for_rpm_lock
sudo dnf5 install -y --skip-unavailable \
    virt-manager qemu-kvm qemu-img libvirt libvirt-daemon-kvm \
    edk2-ovmf dnsmasq \
    || log_warn "Część pakietów wirtualizacji nie powiodła się — kontynuuję" "Some virtualization packages failed — continuing"

LIBVIRT_SVC=""
for svc in libvirtd virtqemud; do
    if systemctl list-unit-files "$svc.service" &>/dev/null 2>&1 \
        && systemctl list-unit-files "$svc.service" | grep -q "$svc"; then
        LIBVIRT_SVC="$svc"
        break
    fi
done

if [[ -n "$LIBVIRT_SVC" ]]; then
    sudo systemctl enable --now "$LIBVIRT_SVC.service"
fi

if ! sudo virsh net-info default &>/dev/null; then
    sudo virsh net-define /usr/share/libvirt/networks/default.xml || true
fi
sudo virsh net-start default 2>/dev/null || true
sudo virsh net-autostart default || log_warn "Nie udało się ustawić autostartu sieci 'default'." "Failed to enable autostart for network 'default'."

# Firewalld
if command -v firewall-cmd &>/dev/null; then
    sudo systemctl enable --now firewalld
    sudo firewall-cmd --permanent --zone=libvirt --add-interface=virbr0 2>/dev/null || true
    sudo firewall-cmd --permanent --add-source=192.168.122.0/24
    sudo firewall-cmd --reload
fi

# Dodanie użytkownika do grup wirtualizacji
for grp in libvirt kvm; do
    if getent group "$grp" &>/dev/null; then
        sudo usermod -aG "$grp" "$CURRENT_USER"
    fi
done


# ==========================================================
# 3b. FLATPAK / FLATHUB
# ==========================================================
wait_for_rpm_lock
sudo dnf5 install -y flatpak || log_warn "Błąd instalacji Flatpak" "Error installing Flatpak"

if ! flatpak remote-list | grep -q "^flathub"; then
    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

sudo flatpak update --appstream || true

sudo flatpak install -y flathub com.github.tchx84.Flatseal || log_warn "Błąd instalacji Flatseal" "Error installing Flatseal"
sudo flatpak install -y flathub it.mijorus.gearlever || log_warn "Błąd instalacji Gear Lever" "Error installing Gear Lever"


# ==========================================================
# 4. FINALIZACJA I OPTYMALIZACJA
# ==========================================================
log_info "Finalizacja i optymalizacja..." \
         "Finalization and optimization..."

# Odmaskowanie usług
sudo systemctl unmask packagekit.service dnf-makecache.timer dnf-makecache.service dnf5-makecache.timer dnf5-makecache.service 2>/dev/null || true

# BleachBit
if [[ -d "$SCRIPT_DIR/bleachbit" ]]; then
    sudo mkdir -p /root/.config/bleachbit
    sudo cp -af "$SCRIPT_DIR/bleachbit/." /root/.config/bleachbit/
fi

# Optymalizacja systemu
sudo systemctl enable fstrim.timer || true
sudo journalctl --vacuum-time=2d || true

# Ustaw GRUB_TIMEOUT=0
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
sudo grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true

# DNS przez NetworkManager
ACTIVE_CONN=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null \
    | grep -v "^lo" | head -n 1 | cut -d: -f1 || true)
if [[ -n "$ACTIVE_CONN" ]]; then
    sudo nmcli connection modify "$ACTIVE_CONN" \
        ipv4.dns "1.1.1.1,1.0.0.1" \
        ipv6.dns "2606:4700:4700::1112,2606:4700:4700::1002"
    sudo nmcli connection up "$ACTIVE_CONN" || true
fi

# ZSH + Oh My Zsh + Powerlevel10k
log_info "Konfiguracja ZSH..." \
         "Configuring ZSH..."

ZSH_BIN=$(command -v zsh || true)
if [[ -n "$ZSH_BIN" ]]; then
    sudo chsh -s "$ZSH_BIN" "$CURRENT_USER" || true

    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
            "" --unattended || true
    fi

    P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ ! -d "$P10K_DIR" ]]; then
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR" || true
    fi

    ZSHRC="$HOME/.zshrc"
    if [[ -f "$ZSHRC" ]]; then
        sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC"
        sed -i 's/^plugins=(.*/plugins=(git sudo systemd fedora dnf)/' "$ZSHRC"
        grep -q "LC_ALL=pl_PL.UTF-8" "$ZSHRC" || echo "export LC_ALL=pl_PL.UTF-8" >> "$ZSHRC"
        grep -q "^fastfetch"         "$ZSHRC" || echo "fastfetch"                  >> "$ZSHRC"
        grep -q "zsh-syntax-highlighting.zsh" "$ZSHRC" || echo "source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >> "$ZSHRC"
        grep -q "zsh-autosuggestions.zsh"     "$ZSHRC" || echo "source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh"         >> "$ZSHRC"
    fi
fi

# Usuwanie wyjątku sudo
sudo rm -f /etc/sudoers.d/99-temp-installer

log_ok "KONFIGURACJA ZAKOŃCZONA SUKCESEM!" \
       "CONFIGURATION COMPLETED SUCCESSFULLY!"
sleep 3
systemctl reboot
