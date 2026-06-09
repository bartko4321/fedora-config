# Fedora - Comprehensive Post-Install Configuration Script

An automated Bash script designed for quick configuration, optimization, and software installation on a fresh **Fedora** system. The script automates repetitive tasks, speeds up the DNF5 package manager, adds key repositories, and prepares the system for development, gaming, and everyday use.

---

## 🚀 Main Features

### 1. System Preparation & Optimization
* **DNF5 Optimization:** Configures `/etc/dnf/dnf.conf` and `/etc/dnf/dnf5.conf` for faster downloads (increases parallel connections to 10, disables the slowest mirrors, optimizes timeouts, and forces IPv4).
* **RPM Lock Management:** Automatically stops and masks background services such as `PackageKit` and `dnf5-makecache`, preventing annoying database locks during installation.
* **Bloatware Removal:** Cleans the system of unnecessary or duplicate packages (e.g. Nano, Konqueror, KMail, Akonadi, Kontact, and other KDE/Plasma leftovers).
* **Security & Convenience:** Grants a temporary `NOPASSWD` sudoers exception for the installer, so a long installation won't be interrupted waiting for a password (the entry is completely removed at the end).

### 2. Repositories & Software
* **Third-party repositories:** Automatically sets up **RPM Fusion (Free & Nonfree)**, the official **Google Chrome** repository, and **Brave Browser**.
* **Rich application set:** Installs the most popular system tools (`git`, `mc`, `7zip`, `fastfetch`, `rsync`), multimedia apps (`GIMP`, `Audacity`, `Kdenlive`), messaging clients (`Telegram`, `Discord`), cleanup tools (`BleachBit`), and the `Wine` runtime with `Winetricks`.

### 3. Smart GPU Detection & Gaming (Early KMS)
* **Hardware detection:** The script automatically identifies your graphics card model (NVIDIA, AMD, or Intel).
* **Drivers & 32-bit libraries:** Installs a dedicated set of `.i686` libraries matched to your GPU (including proprietary NVIDIA CUDA drivers or open-source Mesa), essential for running Windows/Steam games via Proton/Wine.
* **Early KMS (Dracut):** Forces early video driver loading at the initramfs level via Dracut configuration and automatically regenerates the boot image.
* **Performance tools:** Installs gaming support packages including `gamemode`, `mangohud`, `gamescope`, and `goverlay`.

### 4. Virtualization (KVM/QEMU)
* Full virtualization platform setup: `virt-manager`, `qemu-kvm`, `libvirt`.
* Automatically adds the current user to the `libvirt` and `kvm` system groups.
* Configures the `firewalld` firewall (opens the subnet for virtual machines).

### 5. Personalization & System Tweaks
* **Modern shell:** Switches the default user shell to `ZSH`, automatically installs the **Oh My Zsh** framework (in unattended mode), and the popular **Powerlevel10k** theme.
* **Fast DNS:** Overrides DNS servers for the active NetworkManager connection with Cloudflare's secure and fast addresses (`1.1.1.1` and `1.0.0.1`).
* **Resource management:** Enables `fstrim.timer` for SSDs, reduces the GRUB menu timeout to zero (`GRUB_TIMEOUT=0`), and limits system log size (clears `journalctl` entries older than 2 days).

---

## 📁 Required Project Structure

The `install.sh` script expects the following file structure in its working directory for full functionality (including optional config-copying steps):

```text
📁 fedora-postinstall/
├── 📄 install.sh                    # Main script (this file)
├── 📄 .update.sh                    # (Optional) Environment update script
├── 📄 Konserwacja systemu.desktop   # (Optional) App shortcut added to the system menu
└── 📁 bleachbit/                    # (Optional) Pre-configured BleachBit cleanup files for root
```

---

## 🛠 Prerequisites

1. A freshly installed **Fedora** system with internet access.
2. A user account with administrator (`sudo`) privileges.
3. **⚠️ IMPORTANT:** Do **NOT** run the script directly from the root account (e.g. via `sudo ./install.sh`). Run it as a regular user — it will request administrator privileges on its own when needed.

---

## 💻 How to Run

Execute the following commands in your terminal:

```bash
# 1. Clone your repository
git clone https://github.com/bartko4321/fedora-config.git

# 2. Enter the downloaded folder
cd fedora-config

# 3. Make the install.sh script executable
chmod +x install.sh

# 4. Run the script as a regular user
./install.sh
```

Bank account for support: 06291000060000000005038936

> 🚨 **NOTE:** After all operations complete successfully, the script will wait 3 seconds and **automatically restart the computer** to properly load the new kernel modules, early KMS drivers, and activate the ZSH shell. Make sure to save all open documents before running the installer!

If you find this project useful, leave a star! ⭐

---

## 📄 License

This project is released under the MIT License. You are free to modify and adapt it to your own system needs.
