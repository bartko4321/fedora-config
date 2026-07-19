#!/bin/bash

# ==========================================================
# KOMPLEKSOWY SKRYPT KONFIGURACYJNY SYSTEMU FEDORA
# ==========================================================

set -euo pipefail

# --- Kolory i logowanie ---
INFO='\033[0;34m'
SUCCESS='\033[0;32m'
ERROR='\033[0;31m'
WARN='\033[0;33m'
NC='\033[0m'

log_info()  { echo -e "${INFO}==> $*${NC}"; }
log_ok()    { echo -e "${SUCCESS}✔ $*${NC}"; }
log_err()   { echo -e "${ERROR}✖ BŁĄD: $*${NC}" >&2; }
log_warn()  { echo -e "${WARN}⚠ UWAGA: $*${NC}"; }

# Pułapka błędów
trap 'log_err "Skrypt zakończył się błędem w linii $LINENO. Polecenie: $BASH_COMMAND"' ERR

# Sprawdzenie uprawnień
if [[ "$EUID" -eq 0 ]]; then
    log_err "Nie uruchamiaj skryptu jako root. Uruchom jako zwykły użytkownik z uprawnieniami sudo."
    exit 1
fi

# --- Zmienne globalne ---
CURRENT_USER=$(whoami)
ACTUAL_USER="${SUDO_USER:-$USER}"
OLD_USER_PLACEHOLDER="bartek"
RPM_DIR="/tmp/rpms_$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Tymczasowy wyjątek sudo dla DNF/RPM (by nie pytało o hasło podczas długiej instalacji)
sudo -v
echo "$CURRENT_USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/99-temp-installer > /dev/null


# ==========================================================
# 1. PRZYGOTOWANIE ŚRODOWISKA UŻYTKOWNIKA
# ==========================================================
log_info "Przygotowanie środowiska użytkownika..."

if [ -f "$SCRIPT_DIR/.update.sh" ]; then
    cp -af "$SCRIPT_DIR/.update.sh" ~/.update.sh
    chmod +x ~/.update.sh
fi

if [ -f "$SCRIPT_DIR/System Maintenance.desktop" ]; then
    mkdir -p ~/.local/share/applications/
    cp -af "$SCRIPT_DIR/System Maintenance.desktop" ~/.local/share/applications/
    chmod +x ~/.local/share/applications/"System Maintenance.desktop"
    log_ok "Skopiowano 'System Maintenance.desktop'"
else
    log_warn "Brak pliku 'System Maintenance.desktop' w katalogu skryptu – pominięto"
fi


# ==========================================================
# 2. KONFIGURACJA SYSTEMOWA (SUDO)
# ==========================================================
log_info "Przechodzę do konfiguracji systemowej..."

# Agresywne zatrzymanie usług w tle, w tym nowoczesnego dnf5-makecache
log_info "Zatrzymywanie usług w tle (PackageKit, dnf5-makecache)..."
sudo systemctl stop packagekit.service dnf-makecache.timer dnf-makecache.service dnf5-makecache.timer dnf5-makecache.service 2>/dev/null || true
sudo systemctl mask packagekit.service dnf-makecache.timer dnf-makecache.service dnf5-makecache.timer dnf5-makecache.service 2>/dev/null || true
sudo killall -9 packagekitd dnf dnf5 rpm 2>/dev/null || true

# Optymalizacja DNF5 pod kątem sieci (Fedora 44 używa dnf5 jako domyślnego)
log_info "Optymalizacja menedżera pakietów DNF5..."
for DNF_CONF in /etc/dnf/dnf.conf /etc/dnf/dnf5.conf; do
    if [[ -f "$DNF_CONF" ]]; then
        sudo sed -i '/^fastestmirror=/d; /^retries=/d; /^timeout=/d; /^max_parallel_downloads=/d; /^ip_resolve=/d' "$DNF_CONF"
        echo -e "fastestmirror=False\nmax_parallel_downloads=10\nretries=10\ntimeout=120\nip_resolve=4" | sudo tee -a "$DNF_CONF" > /dev/null
    fi
done

# Poczekaj na zwolnienie blokady RPM/DNF5
wait_for_rpm_lock() {
    local i=0
    while pgrep -x dnf >/dev/null || pgrep -x dnf5 >/dev/null || pgrep -x packagekitd >/dev/null || pgrep -x rpm >/dev/null; do
        if (( i++ >= 24 )); then
            log_warn "Blokada RPM nadal zajęta po 120s — wymuszam czyszczenie..."
            sudo systemctl stop packagekit.service dnf-makecache.service dnf5-makecache.service 2>/dev/null || true
            sudo killall -9 dnf dnf5 rpm packagekitd 2>/dev/null || true
            sudo rm -f /var/lib/rpm/.rpm.lock /usr/lib/sysimage/rpm/.rpm.lock /var/cache/libdnf5/*.lock 2>/dev/null || true
            break
        fi
        log_info "Czekam na zwolnienie procesów w tle (DNF/RPM)... ($((i*5))s)"
        sleep 5
    done
}

# Instalacja podstawowych narzędzi skryptowych (KRYTYCZNE)
wait_for_rpm_lock
sudo dnf5 install -y wget curl pciutils

# --- Repozytoria RPM Fusion ---
FEDORA_VER=$(rpm -E %fedora)
log_info "Wykryta wersja Fedory: $FEDORA_VER"

wait_for_rpm_lock
sudo dnf5 install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm" \
    || log_warn "Część repozytoriów RPM Fusion już zainstalowana lub niedostępna"

# --- Chrome ---
log_info "Konfiguracja repozytorium i instalacja Google Chrome..."
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

# --- Brave (Origin) - wg https://brave.com/origin/linux/ ---
log_info "Konfiguracja repozytorium i instalacja Brave Origin..."
wait_for_rpm_lock
sudo dnf5 install -y dnf-plugins-core
sudo dnf5 config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo

wait_for_rpm_lock
sudo dnf5 install -y brave-origin

# --- Narzędzia deweloperskie ---
wait_for_rpm_lock
sudo dnf5 install -y @development-tools @c-development || log_warn "Część grup deweloperskich nie powiodła się"
sudo dnf5 install -y gcc gcc-c++ make || log_warn "Część narzędzi deweloperskich nie powiodła się"

# --- Czyszczenie zbędnych pakietów ---
log_info "Usuwanie zbędnych pakietów..."
TO_REMOVE=(
    nano konqueror plasma-browser-integration plasma-vault
    krdp plasma-thunderbolt kontact kmail kontrast plasma-welcome
    kaddressbook kdepim-runtime akonadi
    krfb krdc
)
wait_for_rpm_lock
sudo dnf5 remove -y "${TO_REMOVE[@]}" 2>/dev/null \
    || log_warn "Część pakietów do usunięcia nie była zainstalowana"
sudo dnf5 autoremove -y

# --- Główna lista pakietów ---
PACKAGES=(
    # Narzędzia systemowe
    dconf-editor hunspell-pl fastfetch unrar git mc exfatprogs ntfs-3g
    os-prober android-tools fsarchiver inxi pv rsync python3-defusedxml
    python3-packaging python3-pip pipx 7zip zenity innoextract makeself
    dnf-plugins-core bleachbit timeshift flatseal

    # Multimedia
    audacity gimp gmic mixxx kdenlive

    # Internet / komunikatory
    telegram-desktop qbittorrent thunderbird thunderbird-i18n-pl

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
log_info "Instalacja głównej listy pakietów..."
sudo dnf5 install -y --skip-unavailable "${PACKAGES[@]}" \
    || log_warn "Część pakietów nie powiodła się — kontynuuję"


# ==========================================================
# 3. WYKRYWANIE GPU: BIBLIOTEKI 32-BIT I DRACUT (EARLY KMS)
# ==========================================================
log_info "Wykrywanie GPU: instalacja bibliotek 32-bitowych i konfiguracja dracut..."
PACKAGES_32=(
    # Podstawowe biblioteki systemowe
    glibc.i686 libstdc++.i686 libgcc.i686 vulkan-loader.i686

    # Wine 32-bit
    wine.i686

    # Dźwięk (PipeWire zastępuje PulseAudio, ale libs są dla kompatybilności)
    alsa-lib.i686 pipewire-alsa.i686 pipewire-libs.i686
    pulseaudio-libs.i686 openal-soft.i686

    # Nakładki i wydajność
    mangohud.i686 gamemode.i686

    # Sieć i SSL
    openssl-libs.i686 nss.i686 nspr.i686

    # GTK / Qt (Wine i starsze aplikacje X11/XWayland)
    libXcomposite.i686 libXcursor.i686 libXdamage.i686
    libXext.i686 libXfixes.i686 libXi.i686
    libXrandr.i686 libXrender.i686 libXtst.i686
    libxkbcommon.i686
)

GPU_INFO=$(lspci -nn | grep -iE "VGA|3D|Display" || true)
DRACUT_CONF="/etc/dracut.conf.d/90-gpu.conf"

if echo "$GPU_INFO" | grep -iq "NVIDIA"; then
    log_info "Wykryto kartę graficzną NVIDIA. Dodaję 32-bitowe biblioteki własnościowe i moduły dracut..."
    PACKAGES_32+=(xorg-x11-drv-nvidia-libs.i686 xorg-x11-drv-nvidia-cuda-libs.i686)
    echo 'force_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "' | sudo tee "$DRACUT_CONF" > /dev/null

elif echo "$GPU_INFO" | grep -iqE "AMD|Radeon"; then
    log_info "Wykryto kartę graficzną AMD. Dodaję 32-bitowe biblioteki Mesa i moduł dracut amdgpu..."
    PACKAGES_32+=(mesa-dri-drivers.i686 mesa-vulkan-drivers.i686 mesa-libGL.i686)
    echo 'force_drivers+=" amdgpu "' | sudo tee "$DRACUT_CONF" > /dev/null

elif echo "$GPU_INFO" | grep -iq "Intel"; then
    log_info "Wykryto kartę graficzną Intel. Dodaję 32-bitowe biblioteki Mesa i moduł dracut i915..."
    PACKAGES_32+=(mesa-dri-drivers.i686 mesa-vulkan-drivers.i686 mesa-libGL.i686)
    echo 'force_drivers+=" i915 "' | sudo tee "$DRACUT_CONF" > /dev/null

else
    log_warn "Nie rozpoznano jednoznacznie karty graficznej. Instaluję pakiety Mesa jako domyślne."
    PACKAGES_32+=(mesa-dri-drivers.i686 mesa-vulkan-drivers.i686 mesa-libGL.i686)
    sudo rm -f "$DRACUT_CONF"
fi

wait_for_rpm_lock
sudo dnf5 install -y --skip-unavailable "${PACKAGES_32[@]}" \
    || log_warn "Część bibliotek 32-bitowych nie powiodła się — kontynuuję"

# Przebudowa initramfs, jeśli utworzono konfigurację dla dracut
if [[ -f "$DRACUT_CONF" ]]; then
    log_info "Przebudowa obrazu initramfs (dracut) dla wczesnego KMS..."
    sudo dracut --force
fi

# --- Pakiety RPM (Discord, ls-fg, Faugus) ---
log_info "Pobieranie i instalacja pakietów RPM..."
mkdir -p "$RPM_DIR"

download_rpm() {
    local name="$1" url="$2" dldest="$3"
    if wget -q --timeout=30 -O "$dldest" "$url"; then
        log_ok "Pobrano: $name"
    else
        log_warn "Nie udało się pobrać: $name ($url) — pomijam"
        rm -f "$dldest"
    fi
}

# Discord
log_info "Instalacja Discord..."
wait_for_rpm_lock
if sudo dnf5 repolist 2>/dev/null | grep -iq "rpmfusion-nonfree"; then
    if sudo dnf5 install -y discord; then
        log_ok "Discord zainstalowany przez dnf5."
    else
        log_err "Błąd podczas instalacji Discorda przez dnf5."
    fi
else
    log_warn "Repozytorium RPM Fusion Nonfree nie jest włączone. Próbuję pobrać RPM ręcznie..."
    dest="/tmp/discord.rpm"
    if wget -q --user-agent="Mozilla/5.0" \
        "https://discord.com/api/download?platform=linux&format=rpm" -O "$dest"; then
        if file "$dest" | grep -q "RPM"; then
            sudo dnf5 install -y "$dest"
            rm -f "$dest"
        else
            log_err "Pobrany plik nie jest poprawną paczką RPM. Discord blokuje automatyczne pobieranie."
            rm -f "$dest"
        fi
    else
        log_err "Nie udało się połączyć z serwerem Discord."
    fi
fi

# ls-fg i ls-fg-vk (przez GitHub)
LSFG_URL=$(curl -sf https://api.github.com/repos/YuriSizov/ls-fg/releases/latest \
    | grep "browser_download_url.*ls-fg_.*rpm" | cut -d '"' -f 4 || true)
[[ -n "$LSFG_URL" ]] && download_rpm "ls-fg" "$LSFG_URL" "$RPM_DIR/lsfg.rpm"

LSFG_VK_URL=$(curl -sf https://api.github.com/repos/YuriSizov/ls-fg-vk/releases/latest \
    | grep "browser_download_url.*rpm" | cut -d '"' -f 4 || true)
[[ -n "$LSFG_VK_URL" ]] && download_rpm "ls-fg-vk" "$LSFG_VK_URL" "$RPM_DIR/lsfg-vk.rpm"

# Faugus Launcher przez COPR
log_info "Instalacja Faugus Launcher przez COPR..."
wait_for_rpm_lock
sudo dnf5 -y copr enable faugus/faugus-launcher \
    && sudo dnf5 --refresh -y install faugus-launcher \
    && log_ok "Faugus Launcher zainstalowany" \
    || log_warn "Instalacja Faugus Launcher nie powiodła się (ignoruję)"

# Instaluj pobrane pliki RPM
shopt -s nullglob
RPM_FILES=("$RPM_DIR"/*.rpm)
if [[ ${#RPM_FILES[@]} -gt 0 ]]; then
    wait_for_rpm_lock
    sudo dnf5 install -y "${RPM_FILES[@]}"
else
    log_warn "Brak pobranych pakietów RPM do zainstalowania."
fi
shopt -u nullglob
rm -rf "$RPM_DIR"

# --- Wirtualizacja ---
log_info "Konfiguracja wirtualizacji..."
wait_for_rpm_lock
sudo dnf5 install -y --skip-unavailable \
    virt-manager qemu-kvm qemu-img libvirt libvirt-daemon-kvm \
    edk2-ovmf dnsmasq \
    || log_warn "Część pakietów wirtualizacji nie powiodła się — kontynuuję"

# libvirt — Fedora używa virtqemud (modular daemon) — uruchamiamy PRZED firewalld, żeby virbr0 już istniał
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
    log_ok "Uruchomiono serwis: $LIBVIRT_SVC"
else
    log_warn "Nie znaleziono serwisu libvirt (libvirtd/virtqemud) — pomijam"
fi

# Upewnij się, że sieć "default" (NAT dla maszyn wirtualnych) istnieje i wystartuje przy boocie
if ! sudo virsh net-info default &>/dev/null; then
    log_warn "Sieć 'default' nie jest zdefiniowana - definiuję z domyślnego XML..."
    sudo virsh net-define /usr/share/libvirt/networks/default.xml || true
fi
sudo virsh net-start default 2>/dev/null || true
sudo virsh net-autostart default || log_warn "Nie udało się ustawić autostartu sieci 'default' - sprawdź 'virsh net-list --all'."

# --- Firewalld ---
if command -v firewall-cmd &>/dev/null; then
    log_info "Konfiguracja firewalld..."
    sudo systemctl enable --now firewalld
    sudo firewall-cmd --permanent --zone=libvirt --add-interface=virbr0 2>/dev/null || true
    sudo firewall-cmd --permanent --add-source=192.168.122.0/24
    sudo firewall-cmd --reload
    log_ok "firewalld skonfigurowany"
fi

# Dodanie użytkownika do grup wirtualizacji
for grp in libvirt kvm; do
    if getent group "$grp" &>/dev/null; then
        sudo usermod -aG "$grp" "$CURRENT_USER" \
            && log_ok "Dodano $CURRENT_USER do grupy $grp"
    fi
done
sudo usermod -aG libvirt $USER && log_ok "Dodano $USER do grupy libvirt"

# ==========================================================
# 3b. FLATPAK / FLATHUB
# ==========================================================
log_info "Konfiguracja Flatpak i repozytorium Flathub..."
wait_for_rpm_lock
sudo dnf5 install -y flatpak || log_warn "Błąd instalacji Flatpak"

if ! flatpak remote-list | grep -q "^flathub"; then
    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

log_info "Instalacja Gear Lever z Flathub..."
sudo flatpak install -y flathub it.mijorus.gearlever || log_warn "Błąd instalacji Gear Lever"

# ==========================================================
# 4. FINALIZACJA I OPTYMALIZACJA
# ==========================================================
log_info "Finalizacja i optymalizacja..."

# Odmaskowanie usług, by system mógł znów z nich korzystać po naszym restarcie
sudo systemctl unmask packagekit.service dnf-makecache.timer dnf-makecache.service dnf5-makecache.timer dnf5-makecache.service 2>/dev/null || true

# --- BleachBit ---
if [[ -d "$SCRIPT_DIR/bleachbit" ]]; then
    sudo mkdir -p /root/.config/bleachbit
    sudo cp -af "$SCRIPT_DIR/bleachbit/." /root/.config/bleachbit/
    log_ok "Skopiowano konfigurację BleachBit"
else
    log_warn "Folder $SCRIPT_DIR/bleachbit nie istnieje — pomijam"
fi

# --- Optymalizacja systemu ---
sudo systemctl enable fstrim.timer || true
sudo journalctl --vacuum-time=2d || true

# Ustaw GRUB_TIMEOUT=0 (idempotentne)
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub

# Regeneruj konfigurację GRUB (Od Fedory 34 uniwersalna ścieżka to /boot/grub2/grub.cfg)
sudo grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true

# --- DNS przez NetworkManager ---
ACTIVE_CONN=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null \
    | grep -v "^lo" | head -n 1 | cut -d: -f1 || true)
if [[ -n "$ACTIVE_CONN" ]]; then
    sudo nmcli connection modify "$ACTIVE_CONN" \
        ipv4.dns "1.1.1.1,1.0.0.1" \
        ipv6.dns "2606:4700:4700::1112,2606:4700:4700::1002"
    sudo nmcli connection up "$ACTIVE_CONN" || true
else
    log_warn "Brak aktywnego połączenia NetworkManager — pominięto konfigurację DNS"
fi

# --- ZSH + Oh My Zsh + Powerlevel10k ---
log_info "Konfiguracja ZSH..."

ZSH_BIN=$(command -v zsh || true)
if [[ -z "$ZSH_BIN" ]]; then
    log_err "zsh nie jest zainstalowany — nie można ustawić jako domyślna powłoka"
else
    sudo chsh -s "$ZSH_BIN" "$CURRENT_USER" \
        && log_ok "Ustawiono zsh ($ZSH_BIN) jako domyślną powłokę" \
        || log_warn "Nie udało się ustawić zsh jako domyślnej powłoki"

    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
            "" --unattended
    fi

    P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ ! -d "$P10K_DIR" ]]; then
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
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

# ── Sprzątanie wyjątków ───────────────────────────────────────
sudo rm -f /etc/sudoers.d/99-temp-installer

log_ok "KONFIGURACJA ZAKOŃCZONA SUKCESEM!"
sleep 3
systemctl reboot
