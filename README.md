# Fedora - Kompleksowy Skrypt Konfiguracyjny (Post-Install)

Automatyczny skrypt Bash przeznaczony do szybkiej konfiguracji, optymalizacji i instalacji oprogramowania na świeżym systemie **Fedora**. Skrypt automatyzuje powtarzalne czynności, przyspiesza menedżer pakietów DNF5, dodaje kluczowe repozytoria oraz przygotowuje system pod kątem deweloperskim, gamingowym i codziennego użytku.

---

## 🚀 Główne Funkcje Skryptu

### 1. Przygotowanie i Optymalizacja Systemu
* **Optymalizacja DNF5:** Konfiguruje `/etc/dnf/dnf.conf` oraz `/etc/dnf/dnf5.conf` pod kątem szybszego pobierania (zwiększenie liczby równoległych połączeń do 10, wyłączenie najwolniejszych luster, optymalizacja czasu oczekiwania oraz wymuszenie IPv4).
* **Zarządzanie blokadami RPM:** Automatycznie zatrzymuje i maskuje usługi tła takie jak `PackageKit` oraz `dnf5-makecache`, zapobiegając irytującym blokadom bazy danych podczas instalacji.
* **Usuwanie Bloatware:** Oczyszcza system z niepotrzebnych lub zdublowanych pakietów (np. Nano, Konqueror, KMail, Akonadi, Kontact i inne pozostałości środowiska KDE/Plasma).
* **Bezpieczeństwo i Wygoda:** Nadaje tymczasowy wyjątek `NOPASSWD` w sudoers dla instalatora, dzięki czemu długa instalacja nie zostanie przerwana w oczekiwaniu na hasło (wpis jest całkowicie usuwany na końcu).

### 2. Repozytoria i Oprogramowanie
* **Repozytoria firm trzecich:** Automatycznie instaluje repozytoria **RPM Fusion (Free & Nonfree)**, oficjalne repozytorium **Google Chrome** oraz **Brave Browser**.
* **Bogaty pakiet aplikacji:** Instaluje najpopularniejsze narzędzia systemowe (`git`, `mc`, `7zip`, `fastfetch`, `rsync`), multimedialne (`GIMP`, `Audacity`, `Kdenlive`), komunikatory (`Telegram`, `Discord`), narzędzia do czyszczenia (`BleachBit`) oraz środowisko uruchomieniowe `Wine` wraz z `Winetricks`.

### 3. Inteligentne Wykrywanie GPU & Gaming (Early KMS)
* **Wykrywanie sprzętu:** Skrypt automatycznie sprawdza model karty graficznej (NVIDIA, AMD lub Intel).
* **Sterowniki i biblioteki 32-bitowe:** Instaluje dedykowany zestaw bibliotek `.i686` dopasowany do Twojego GPU (w tym sterowniki własnościowe NVIDIA CUDA lub otwartoźródłową Mesę), kluczowych do uruchamiania gier Windows/Steam przez Proton/Wine.
* **Early KMS (Dracut):** Wymusza wczesne ładowanie sterowników wideo na poziomie initramfs za pomocą konfiguracji Dracut i automatycznie regeneruje obraz rozruchowy.
* **Narzędzia wydajnościowe:** Instaluje pakiety wspierające gaming, m.in. `gamemode`, `mangohud`, `gamescope` oraz `goverlay`.

### 4. Wirtualizacja (KVM/QEMU)
* Pełna konfiguracja platformy wirtualizacji: `virt-manager`, `qemu-kvm`, `libvirt`.
* Automatyczne dodanie aktualnego użytkownika do grup systemowych `libvirt` oraz `kvm`.
* Konfiguracja zapory sieciowej `firewalld` (przepuszczenie podsieci dla wirtualnych maszyn).

### 5. Personalizacja i Tweakowanie Systemu
* **Nowoczesna powłoka:** Zmienia domyślną powłokę użytkownika na `ZSH`, automatycznie instaluje framework **Oh My Zsh** (w trybie bezobsługowym) oraz popularny motyw **Powerlevel10k**.
* **Szybki DNS:** Nadpisuje serwery DNS dla aktywnego połączenia w NetworkManager na bezpieczne i szybkie adresy Cloudflare (`1.1.1.1` i `1.0.0.1`).
* **Zarządzanie zasobami:** Włącza `fstrim.timer` dla dysków SSD, skraca czas oczekiwania w menu GRUB do zera (`GRUB_TIMEOUT=0`) oraz ogranicza rozmiar logów systemowych (czyszczenie `journalctl` powyżej 2 dni).

---

## 📁 Wymagana Struktura Projektu

Skrypt `install.sh` do pełnego działania (w tym opcjonalnych kroków kopiowania konfiguracji) oczekuje następującej struktury plików w swoim katalogu uruchomieniowym:

```text
📁 fedora-postinstall/
├── 📄 install.sh                    # Główny skrypt (ten plik)
├── 📄 .update.sh                    # (Opcjonalnie) Skrypt aktualizacji środowiska
├── 📄 Konserwacja systemu.desktop   # (Opcjonalnie) Skrót aplikacji dodawany do menu
└── 📁 bleachbit/                    # (Opcjonalnie) Gotowe pliki konfiguracyjne czyszczenia dla root
```

---

## 🛠 Wymagania Przed Uruchomieniem

1. Zainstalowany system **Fedora 44** z dostępem do Internetu.
2. Konto użytkownika z uprawnieniami administratora (`sudo`).
3. **⚠️ WAŻNE:** Skryptu **NIE WOLNO** uruchamiać bezpośrednio z konta root (np. poprzez `sudo ./install.sh`). Skrypt należy uruchomić jako zwykły użytkownik – w razie potrzeby sam poprosi o uprawnienia administratora.

---

## 💻 Instrukcja Uruchomienia

Wykonaj poniższe polecenia w terminalu:

```bash
# 1. Sklonuj swoje repozytorium
git clone https://github.com/bartko4321/fedora-config.git
cd fedora-config

# 2. Nadaj uprawnienia do wykonywania skryptu install.sh
chmod +x install.sh

# 3. Uruchom skrypt jako zwykły użytkownik
./install.sh
```

Wsparcie numer konta: 06291000060000000005038936

> 🚨 **UWAGA:** Po pomyślnym zakończeniu wszystkich operacji, skrypt odczeka 3 sekundy i **automatycznie zrestartuje komputer**, aby poprawnie załadować nowe moduły jądra, sterowniki wczesnego KMS oraz aktywować powłokę ZSH. Upewnij się, że zapisałeś wszystkie otwarte dokumenty przed uruchomieniem instalatora!

---

## 📄 Licencja

Projekt udostępniany na licencji MIT. Możesz go dowolnie modyfikować i dostosowywać do własnych potrzeb systemowych.
