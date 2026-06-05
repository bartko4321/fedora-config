#!/bin/bash

# Kolory dla lepszej czytelności
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}       KOMPLEKSOWY SKRYPT AKTUALIZACJI I CZYSZCZENIA  ${NC}"
echo -e "${BLUE}======================================================${NC}"

# 1. ZAPYTANIE O HASŁO TYLKO RAZ
echo -e "${YELLOW}Proszę podać hasło administratora (sudo):${NC}"
sudo -v

# Utrzymanie aktywnej sesji sudo w tle
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEP_ALIVE_PID=$!

echo -e "\n${GREEN}==> Odświeżanie repozytoriów i pełna aktualizacja systemu (DNF)...${NC}"
sudo dnf upgrade --refresh -y

# Opcjonalna aktualizacja firmware (często spotykana w Fedorze)
if command -v fwupdmgr &> /dev/null; then
    echo -e "${GREEN}==> Odświeżanie metadanych i sprawdzanie aktualizacji firmware...${NC}"
    sudo fwupdmgr refresh -y
    sudo fwupdmgr update -y
fi

# AKTUALIZACJA FLATPAK
if command -v flatpak &> /dev/null; then
    echo -e "\n${GREEN}==> Aktualizacja pakietów Flatpak (System i Użytkownik)...${NC}"
    sudo flatpak update --system -y
    flatpak update --user -y
fi

echo -e "\n${BLUE}======================================================${NC}"
echo -e "${BLUE}       FAZA 1: SYSTEM (SUDO)                         ${NC}"
echo -e "${BLUE}======================================================${NC}"

echo -e "${GREEN}==> Usuwanie niepotrzebnych zależności (Autoremove)...${NC}"
sudo dnf autoremove -y

echo -e "${GREEN}==> Czyszczenie cache DNF...${NC}"
sudo dnf clean all

echo -e "${GREEN}==> Czyszczenie starych logów Journalctl (starsze niż 7 dni)...${NC}"
sudo journalctl --vacuum-time=7d

echo -e "${GREEN}==> Usuwanie starych plików logów (.gz i .1) z /var/log...${NC}"
sudo find /var/log -type f \( -name "*.gz" -o -name "*.1" \) -delete

# BEZPIECZNE CZYSZCZENIE FLATPAK (SYSTEM)
if command -v flatpak &> /dev/null; then
    echo -e "${GREEN}==> Kompleksowe czyszczenie Flatpak (System)...${NC}"
    sudo flatpak uninstall --unused --system -y

    # Dodatkowe usunięcie danych po odinstalowanych aplikacjach w trybie systemowym
    sudo flatpak uninstall --unused --delete-data -y 2>/dev/null
    sudo flatpak repair --system

    # Usuwanie nieużywanych źródeł (remotes) i powiązanego cache
    USED_REMOTES=$(flatpak list --columns=origin 2>/dev/null | sort -u)
    ALL_REMOTES=$(flatpak remotes --columns=name 2>/dev/null | tail -n +1)

    while IFS= read -r remote; do
        if [ -n "$remote" ] && ! echo "$USED_REMOTES" | grep -qx "$remote"; then
            echo -e "${YELLOW}Usuwanie nieużywanego źródła Flatpak: $remote${NC}"
            sudo flatpak remote-delete --force "$remote" 2>/dev/null && \
            sudo rm -rf /var/tmp/flatpak-cache-* 2>/dev/null
        fi
    done <<< "$ALL_REMOTES"

    # Głębsze czyszczenie śmieci systemowych Flatpaka
    echo -e "${GREEN}==> Usuwanie plików .tmp i historii Flatpak (System)...${NC}"
    sudo find /var/lib/flatpak -name "*.tmp" -delete 2>/dev/null
    sudo rm -f /var/lib/flatpak/history 2>/dev/null

    # Inteligentne czyszczenie /var/app (tylko osierocone dane)
    echo -e "${GREEN}==> Czyszczenie osieroconych danych po usuniętych aplikacjach w /var/app...${NC}"
    INSTALLED_FLATPAKS=$(flatpak list --app --columns=application 2>/dev/null)
    if [ -d "/var/app" ]; then
        for app_dir in /var/app/*; do
            if [ -d "$app_dir" ]; then
                app_id=$(basename "$app_dir")
                if ! echo "$INSTALLED_FLATPAKS" | grep -qx "$app_id"; then
                    echo -e "${YELLOW}Usuwanie osieroconych danych systemowych w /var/app: $app_id${NC}"
                    sudo rm -rf "$app_dir"
                fi
            fi
        done
    fi
fi

echo -e "${GREEN}==> Czyszczenie /tmp i /var/tmp (starsze niż 3 dni)...${NC}"
sudo find /tmp -type f -atime +3 -delete 2>/dev/null
sudo find /var/tmp -type f -atime +3 -delete 2>/dev/null

echo -e "${GREEN}==> Sprawdzanie osieroconych modułów kernela...${NC}"
CURRENT_KERNEL=$(uname -r)
for module_dir in /usr/lib/modules/*; do
    if [ -d "$module_dir" ]; then
        version=$(basename "$module_dir")
        if [ "$version" != "$CURRENT_KERNEL" ] && [ ! -f "/boot/vmlinuz-$version" ]; then
            echo "Usuwanie pozostałości po starym kernelu: $version"
            sudo rm -rf "$module_dir"
        fi
    fi
done

echo -e "\n${BLUE}======================================================${NC}"
echo -e "${BLUE}       FAZA 2: UŻYTKOWNIK (BEZ SUDO)                 ${NC}"
echo -e "${BLUE}======================================================${NC}"

echo -e "${GREEN}==> Czyszczenie cache użytkownika (z wyłączeniem przeglądarek)...${NC}"
find ~/.cache -type f -atime +14 \
    ! -path "*/mozilla/*" \
    ! -path "*/google-chrome/*" \
    ! -path "*/chromium/*" \
    ! -path "*/BraveSoftware/*" \
    ! -path "*/opera/*" \
    -exec rm -f {} + 2>/dev/null

echo -e "${GREEN}==> Czyszczenie starych miniatur (thumbnails)...${NC}"
find ~/.cache/thumbnails -type f -atime +7 -exec rm -f {} + 2>/dev/null

if command -v flatpak &> /dev/null; then
    echo -e "${GREEN}==> Czyszczenie Flatpak (Użytkownik)...${NC}"
    flatpak uninstall --unused --user -y

    # Dodatkowe usunięcie danych po odinstalowanych aplikacjach w trybie użytkownika
    flatpak uninstall --unused --delete-data -y 2>/dev/null || flatpak uninstall --delete-data -y 2>/dev/null
    flatpak repair --user

    # Czyszczenie historii użytkownika
    rm -f ~/.local/share/flatpak/history 2>/dev/null

    # Inteligentne czyszczenie ~/.var/app (tylko osierocone dane)
    echo -e "${GREEN}==> Czyszczenie osieroconych danych po usuniętych aplikacjach w ~/.var/app...${NC}"
    INSTALLED_FLATPAKS=$(flatpak list --app --columns=application 2>/dev/null)
    if [ -d "$HOME/.var/app" ]; then
        for app_dir in "$HOME/.var/app"/*; do
            if [ -d "$app_dir" ]; then
                app_id=$(basename "$app_dir")
                if ! echo "$INSTALLED_FLATPAKS" | grep -qx "$app_id"; then
                    echo -e "${YELLOW}Usuwanie osieroconych danych użytkownika w ~/.var/app: $app_id${NC}"
                    rm -rf "$app_dir"
                fi
            fi
        done
    fi
fi

echo -e "${GREEN}==> Przebudowa cache czcionek...${NC}"
fc-cache -r

echo -e "${GREEN}==> Czyszczenie konfiguracji virt-manager...${NC}"
USER_ID=$(id -u)
if [ -S "/run/user/$USER_ID/bus" ]; then
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" dconf reset /org/virt-manager/virt-manager/urls/isos 2>/dev/null
fi
rm -rf "$HOME/.cache/virt-manager" 2>/dev/null

echo -e "\n${BLUE}======================================================${NC}"
echo -e "${BLUE}       FAZA 3: SPRAWDZANIE STANU SYSTEMU             ${NC}"
echo -e "${BLUE}======================================================${NC}"

echo -e "${GREEN}==> Sprawdzanie konieczności restartu...${NC}"
# Sprawdzamy, czy DNF obsługuje wtyczkę needs-restarting
if dnf help needs-restarting &> /dev/null; then
    if ! sudo dnf needs-restarting -r -q; then
        echo -e "\n${RED}******************************************************${NC}"
        echo -e "${RED} UWAGA: Zaktualizowano kernel lub kluczowe pakiety!   ${NC}"
        echo -e "${YELLOW} ZALECANY JEST RESTART KOMPUTERA!                     ${NC}"
        echo -e "${RED}******************************************************${NC}\n"
    else
        echo -e "${GREEN}==> Restart systemu nie jest aktualnie wymagany.${NC}"
    fi
else
    echo -e "${YELLOW}Brak wtyczki 'needs-restarting'. Upewnij się, że masz zainstalowany pakiet 'dnf-plugins-core'.${NC}"
fi

# Zatrzymanie procesu podtrzymującego sudo
kill $SUDO_KEEP_ALIVE_PID 2>/dev/null

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}       AKTUALIZACJA I CZYSZCZENIE ZAKOŃCZONE!          ${NC}"
echo -e "${GREEN}======================================================${NC}"
echo "Naciśnij [ENTER], aby zakończyć..."
read -r
