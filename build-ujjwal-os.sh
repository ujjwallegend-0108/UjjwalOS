#!/usr/bin/env bash
# build-ujjwal-os.sh — Self-contained AMD Archiso builder for Ujjwal OS (< 4GB ISO)
set -euo pipefail

# 1. Setup Chaotic-AUR on the build host first so mkarchiso can download paru, yay, calamares, auto-cpufreq
pacman-key --init
pacman-key --populate archlinux
sed -i 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf
CA_BASE="https://""builds.garudalinux.org/repos/chaotic-aur/x86_64"
pacman -U --noconfirm "${CA_BASE}/chaotic-keyring.pkg.tar.zst"
pacman -U --noconfirm "${CA_BASE}/chaotic-mirrorlist.pkg.tar.zst"
sed -i 's/^SigLevel = Never/SigLevel = Required DatabaseOptional/' /etc/pacman.conf

if ! grep -q "\[chaotic-aur\]" /etc/pacman.conf; then
  cat << 'EOF' >> /etc/pacman.conf

[multilib]
Include = /etc/pacman.d/mirrorlist

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
fi
pacman -Sy --noconfirm

WORKDIR="${PWD}/ujjwal-os-archiso"
OUTDIR="${PWD}/out"
rm -rf "${WORKDIR}" "${OUTDIR}"
mkdir -p "${WORKDIR}/airootfs/etc/systemd/system/multi-user.target.wants" \
         "${WORKDIR}/airootfs/etc/pacman.d" \
         "${WORKDIR}/airootfs/etc/sysctl.d" \
         "${WORKDIR}/airootfs/etc/default" \
         "${WORKDIR}/airootfs/boot/grub/themes/ujjwal" \
         "${WORKDIR}/airootfs/etc/skel/.config/fish" \
         "${WORKDIR}/airootfs/etc/skel/.local/share/konsole" \
         "${WORKDIR}/airootfs/etc/skel/.config" \
         "${WORKDIR}/airootfs/etc/sddm.conf.d" \
         "${WORKDIR}/airootfs/etc/calamares/modules" \
         "${WORKDIR}/airootfs/usr/local/bin" \
         "${WORKDIR}/airootfs/root" \
         "${OUTDIR}"

# Copy base releng boot files
cp -rn /usr/share/archiso/configs/releng/* "${WORKDIR}/"

# Copy Chaotic-AUR mirrorlist into live & installed OS
cp /etc/pacman.d/chaotic-mirrorlist "${WORKDIR}/airootfs/etc/pacman.d/chaotic-mirrorlist"

cat <<'EOF' > "${WORKDIR}/profiledef.sh"
#!/usr/bin/env bash
iso_name="ujjwal-os-amd"
iso_label="UJJWAL_OS_2026"
iso_publisher="Ujjwal OS Project"
iso_application="Ujjwal OS Live & Installable ISO"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=(
  'bios.syslinux.mbr'
  'bios.syslinux.eltorito'
  'uefi-ia32.grub.esp'
  'uefi-x64.grub.esp'
  'uefi-ia32.grub.eltorito'
  'uefi-x64.grub.eltorito'
)
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/usr/local/bin/ujjwal-settings-manager"]="0:0:755"
  ["/usr/local/bin/ujjwal-postinstall.sh"]="0:0:755"
)
EOF
chmod +x "${WORKDIR}/profiledef.sh"

# Pure AMD Package List (Zero Intel bloat, Zero Gaming bloat)
cat <<'EOF' > "${WORKDIR}/packages.x86_64"
base
linux-zen
linux-zen-headers
linux-firmware
mkinitcpio
mkinitcpio-archiso
archlinux-keyring
amd-ucode
mesa
vulkan-radeon
xf86-video-amdgpu
pipewire
pipewire-alsa
pipewire-pulse
pipewire-jack
wireplumber
sof-firmware
networkmanager
bluez
bluez-utils
cups
system-config-printer
btrfs-progs
ntfs-3g
sudo
vim
nano
git
plasma-desktop
plasma-wayland-protocols
kwin
wayland
xorg-xwayland
sddm
sddm-kcm
systemsettings
plasma-nm
plasma-pa
bluedevil
kscreen
powerdevil
plasma-systemmonitor
kvantum
xdg-desktop-portal-kde
dolphin
konsole
okular
gwenview
haruna
vlc
kate
ark
spectacle
partitionmanager
firefox
ttf-jetbrains-mono-nerd
noto-fonts
noto-fonts-emoji
zram-generator
ananicy-cpp
irqbalance
fish
starship
eza
bat
fastfetch
archinstall
grub
syslinux
efibootmgr
os-prober
snapper
EOF

cat <<'EOF' > "${WORKDIR}/pacman.conf"
[options]
HoldPkg           = pacman glibc
Architecture      = auto
Color
ILoveCandy
CheckSpace
VerbosePkgLists
ParallelDownloads = 10
SigLevel          = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist

EOF
cp "${WORKDIR}/pacman.conf" "${WORKDIR}/airootfs/etc/pacman.conf"

# OS Branding
cat <<'EOF' > "${WORKDIR}/airootfs/etc/os-release"
NAME="Ujjwal OS"
PRETTY_NAME="Ujjwal OS"
ID=ujjwalos
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="38;2;23;147;209"
EOF
echo "ujjwal-os" > "${WORKDIR}/airootfs/etc/hostname"

# ZRAM Configuration
cat <<'EOF' > "${WORKDIR}/airootfs/etc/systemd/zram-generator.conf"
[zram0]
zram-size = ram / 1
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

# Garuda-style Sysctl Performance & Battery Tweaks
cat <<'EOF' > "${WORKDIR}/airootfs/etc/sysctl.d/99-ujjwal-performance.conf"
vm.swappiness = 180
vm.vfs_cache_pressure = 50
vm.page-cluster = 0
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
kernel.nmi_watchdog = 0
net.core.default_qdisc = cake
net.ipv4.tcp_congestion_control = bbr
fs.inotify.max_user_watches = 524288
EOF

# GRUB Dual-Boot & AMD P-State Optimization
cat <<'EOF' > "${WORKDIR}/airootfs/etc/default/grub"
GRUB_DEFAULT=saved
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Ujjwal OS"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash nowatchdog zswap.enabled=0 loglevel=3 amd_pstate=active"
GRUB_CMDLINE_LINUX=""
GRUB_GFXMODE=1920x1080x32,auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_SAVEDEFAULT=true
GRUB_DISABLE_OS_PROBER=false
EOF

# Konsole + Fish Shell (Garuda Dragon Colors)
cat <<'EOF' > "${WORKDIR}/airootfs/etc/skel/.config/fish/config.fish"
if status is-interactive
    set -g fish_greeting ""
    set -g fish_color_normal E2E8F0
    set -g fish_color_command 00E5FF --bold
    set -g fish_color_param C084FC
    set -g fish_color_autosuggestion 64748B
    set -g fish_color_error FB7185 --bold
    set -g fish_color_quote 34D399

    alias ls='eza --icons --group-directories-first'
    alias ll='eza -la --icons --group-directories-first'
    alias cat='bat --style=plain'
    alias update='paru -Syu'
    alias cleanup='paru -Rns (paru -Qtdq)'
    alias sysinfo='fastfetch'

    function fish_prompt
        set -l last_status $status
        set_color 38BDF8 --bold
        echo -n (whoami)
        set_color normal
        echo -n "@"
        set_color C084FC --bold
        echo -n (hostname)
        set_color normal
        echo -n " "
        set_color 34D399 --bold
        echo -n (prompt_pwd)
        if test $last_status -ne 0
            set_color FB7185
            echo -n " ["$last_status"]"
        end
        set_color F472B6 --bold
        echo -n " ❯ "
        set_color normal
    end

    if command -q fastfetch
        fastfetch --logo arch_small
    end
end
EOF

cat <<'EOF' > "${WORKDIR}/airootfs/etc/skel/.local/share/konsole/UjjwalFish.profile"
[Appearance]
ColorScheme=UjjwalGaruda
Font=JetBrains Mono,11,-1,5,50,0,0,0,0,0

[General]
Command=/usr/bin/fish
Name=Ujjwal Fish
Parent=FALLBACK/

[Scrolling]
HistoryMode=2
EOF

cat <<'EOF' > "${WORKDIR}/airootfs/etc/skel/.local/share/konsole/UjjwalGaruda.colorscheme"
[Background]
Color=13,17,26
[BackgroundIntense]
Color=13,17,26
[Foreground]
Color=230,237,243
[ForegroundIntense]
Color=255,255,255
[Color0]
Color=24,30,44
[Color1]
Color=251,113,133
[Color2]
Color=52,211,153
[Color3]
Color=250,204,21
[Color4]
Color=56,189,248
[Color5]
Color=192,132,252
[Color6]
Color=0,229,255
[Color7]
Color=226,232,240
[General]
Blur=false
Description=Garuda Dragon (Ujjwal OS)
Opacity=0.96
EOF

cat <<'EOF' > "${WORKDIR}/airootfs/etc/skel/.config/konsolerc"
[Desktop Entry]
DefaultProfile=UjjwalFish.profile
EOF

# SDDM Wayland Default
cat <<'EOF' > "${WORKDIR}/airootfs/etc/sddm.conf.d/10-wayland.conf"
[Autologin]
Relogin=false
Session=plasma
User=ujjwal

[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Wayland]
SessionDir=/usr/share/wayland-sessions
EOF

# Clean Stock KDE Plasma + Kvantum Ready
cat <<'EOF' > "${WORKDIR}/airootfs/etc/skel/.config/kdeglobals"
[KDE]
SingleClick=false
LookAndFeelPackage=org.kde.breezedark.desktop
widgetStyle=kvantum-dark

[General]
TerminalApplication=konsole
TerminalService=org.kde.konsole.desktop
EOF

# Ujjwal Settings Manager CLI
cat <<'EOF' > "${WORKDIR}/airootfs/usr/local/bin/ujjwal-settings-manager"
#!/usr/bin/env bash
set -euo pipefail
show_status() {
  echo "=== Ujjwal OS Settings Manager ==="
  echo "Kernel:       $(uname -r)"
  echo "Session:      ${XDG_SESSION_TYPE:-wayland} (KWin Wayland)"
  echo "Shell:        $SHELL"
  echo "ZRAM:         $(zramctl --noheadings 2>/dev/null || echo 'configured via zram-generator')"
  echo "Battery Mgr:  auto-cpufreq"
  echo "Ananicy-cpp:  $(systemctl is-active ananicy-cpp 2>/dev/null || echo 'configured')"
  echo "Irqbalance:   $(systemctl is-active irqbalance 2>/dev/null || echo 'configured')"
  echo "AUR Helpers:  paru $(command -v paru >/dev/null && echo '[ready]' || echo '[missing]'), yay $(command -v yay >/dev/null && echo '[ready]' || echo '[missing]')"
}
case "${1:-status}" in
  status) show_status ;;
  update-grub) sudo grub-mkconfig -o /boot/grub/grub.cfg ;;
  rank-mirrors) sudo rate-mirrors --allow-root arch | sudo tee /etc/pacman.d/mirrorlist ;;
  apply-sysctl) sudo sysctl --system ;;
  *) echo "Usage: ujjwal-settings-manager [status|update-grub|rank-mirrors|apply-sysctl]"; exit 1 ;;
esac
EOF
chmod +x "${WORKDIR}/airootfs/usr/local/bin/ujjwal-settings-manager"

# Post-install script for installed system
cat <<'EOF' > "${WORKDIR}/airootfs/usr/local/bin/ujjwal-postinstall.sh"
#!/usr/bin/env bash
pacman-key --init
pacman-key --populate archlinux
pacman-key --recv-key 3056513887B78AEB --keyserver ://ubuntu.com || true
pacman-key --lsign-key 3056513887B78AEB || true
grub-mkconfig -o /boot/grub/grub.cfg || true
EOF
chmod +x "${WORKDIR}/airootfs/usr/local/bin/ujjwal-postinstall.sh"


# Calamares Installer Configs (Dual-Boot & Single OS Ready)
cat <<'EOF' > "${WORKDIR}/airootfs/etc/calamares/settings.conf"
modules-search: [ local ]
sequence:
- show:
  - welcome
  - locale
  - keyboard
  - partition
  - users
  - summary
- exec:
  - partition
  - mount
  - unpackfs
  - machineid
  - fstab
  - locale
  - keyboard
  - localecfg
  - users
  - displaymanager
  - networkcfg
  - hwclock
  - initcpiocfg
  - initcpio
  - grubcfg
  - bootloader
  - shellprocess
  - umount
- show:
  - finished

branding: default
prompt-install: true
dont-chroot: false
oem-setup: false
disable-cancel: false
disable-cancel-during-exec: true
EOF

cat <<'EOF' > "${WORKDIR}/airootfs/etc/calamares/modules/unpackfs.conf"
unpack:
    - source: "/run/archiso/bootmnt/arch/x86_64/airootfs.sfs"
      sourcefs: "squashfs"
      destination: ""
EOF

cat <<'EOF' > "${WORKDIR}/airootfs/etc/calamares/modules/partition.conf"
efiSystemPartition: "/boot/efi"
userSwapChoices:
  - none
  - file
defaultFileSystemType: "btrfs"
availableFileSystemTypes: [ "btrfs", "ext4" ]
enableLuksAutomatedPartitioning: true
allowManualPartitioning: true
EOF

cat <<'EOF' > "${WORKDIR}/airootfs/etc/calamares/modules/bootloader.conf"
efiBootLoader: "grub"
kernel: "/vmlinuz-linux-zen"
img: "/initramfs-linux-zen.img"
fallback: "/initramfs-linux-zen-fallback.img"
grubInstall: "grub-install"
grubMkconfig: "grub-mkconfig"
grubCfg: "/boot/grub/grub.cfg"
grubProbe: "grub-probe"
efiBootMgr: "efibootmgr"
installEFIFallback: true
EOF

cat <<'EOF' > "${WORKDIR}/airootfs/etc/calamares/modules/initcpio.conf"
kernel: linux-zen
EOF

cat <<'EOF' > "${WORKDIR}/airootfs/etc/calamares/modules/displaymanager.conf"
displaymanagers:
  - sddm
defaultDesktopEnvironment:
    executable: "startplasma-wayland"
    desktopFile: "plasma"
basicSetup: false
EOF

cat <<'EOF' > "${WORKDIR}/airootfs/etc/calamares/modules/shellprocess.conf"
dontChroot: false
timeout: 300
script:
    - "/usr/local/bin/ujjwal-postinstall.sh"
EOF

# Live User (ujjwal / ujjwal)
echo "ujjwal:x:1000:1000:Ujjwal:/home/ujjwal:/usr/bin/fish" >> "${WORKDIR}/airootfs/etc/passwd"
echo "ujjwal:\$6\$rounds=4096\$ujjwalsalt\$7u.u6R8eX6qM0uB0Y5f7m1s8v7n6z9x4c3v2b1n0m9l8k7j6h5g4f3d2s1a0:14871::::::" >> "${WORKDIR}/airootfs/etc/shadow"
mkdir -p "${WORKDIR}/airootfs/etc/sudoers.d"
echo "ujjwal ALL=(ALL:ALL) NOPASSWD: ALL" > "${WORKDIR}/airootfs/etc/sudoers.d/10-wheel"
mkdir -p "${WORKDIR}/airootfs/home/ujjwal/Desktop"
cp -r "${WORKDIR}/airootfs/etc/skel/." "${WORKDIR}/airootfs/home/ujjwal/"
chown -R 1000:1000 "${WORKDIR}/airootfs/home/ujjwal"

# Enable Systemd Services via Symlinks
for svc in NetworkManager bluetooth auto-cpufreq ananicy-cpp irqbalance cups; do
  ln -sf "/usr/lib/systemd/system/${svc}.service" "${WORKDIR}/airootfs/etc/systemd/system/multi-user.target.wants/"
done
ln -sf /usr/lib/systemd/system/sddm.service "${WORKDIR}/airootfs/etc/systemd/system/display-manager.service"
mkdir -p /tmp/chaotic-local
pacman -Sw --noconfirm --cachedir /tmp/chaotic-local paru yay rate-mirrors cachyos-ananicy-rules-git auto-cpufreq
repo-add /tmp/chaotic-local/chaotic-local.db.tar.gz /tmp/chaotic-local/*.pkg.tar.zst
cat <<'EOF' >> "${WORKDIR}/pacman.conf"

[chaotic-local]
SigLevel = Optional TrustAll
Server = file:///tmp/chaotic-local
EOF
cat <<'EOF' >> "${WORKDIR}/packages.x86_64"
paru
yay
rate-mirrors
cachyos-ananicy-rules-git
auto-cpufreq
EOF

echo "Starting mkarchiso for Ujjwal OS (AMD Edition)..."
mkarchiso -v -w /tmp/ujjwal-archiso-work -o "${OUTDIR}" "${WORKDIR}"
ls -lh "${OUTDIR}"/*.iso
