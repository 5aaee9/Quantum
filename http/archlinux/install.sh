#!/usr/bin/env bash

set -euxo pipefail

DISK=/dev/sda
ROOT_PARTITION=${DISK}3
EFI_PARTITION=${DISK}2
loadkeys us || true
timedatectl set-ntp true || true

sgdisk --zap-all "${DISK}"
partprobe "${DISK}" || true

parted -s "${DISK}" mklabel gpt
parted -s "${DISK}" mkpart primary 1MiB 2MiB
parted -s "${DISK}" set 1 bios_grub on
parted -s "${DISK}" mkpart primary fat32 2MiB 514MiB
parted -s "${DISK}" set 2 esp on
parted -s "${DISK}" mkpart primary ext4 514MiB 100%
partprobe "${DISK}"
udevadm settle

mkfs.fat -F32 "${EFI_PARTITION}"
mkfs.ext4 -F "${ROOT_PARTITION}"

mount "${ROOT_PARTITION}" /mnt
mkdir -p /mnt/boot/efi
mount "${EFI_PARTITION}" /mnt/boot/efi

pacstrap -K /mnt base linux linux-firmware grub efibootmgr openssh sudo

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<'CHROOT'
set -euxo pipefail

ln -sf /usr/share/zoneinfo/Asia/Hong_Kong /etc/localtime
hwclock --systohc

cat > /etc/locale.gen <<'LOCALE'
en_US.UTF-8 UTF-8
LOCALE
locale-gen
cat > /etc/locale.conf <<'LOCALECFG'
LANG=en_US.UTF-8
LOCALECFG
cat > /etc/vconsole.conf <<'VCONSOLE'
KEYMAP=us
VCONSOLE

echo archlinux > /etc/hostname
cat > /etc/hosts <<'HOSTS'
127.0.0.1 localhost
::1 localhost
127.0.1.1 archlinux.localdomain archlinux
HOSTS

cat > /etc/systemd/network/20-wired.network <<'NETWORK'
[Match]
Type=ether

[Network]
DHCP=yes
NETWORK

systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl enable sshd

echo 'root:4tH2F34cEDRApj8Y@B26' | chpasswd
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="net.ifnames=0 console=tty0 console=ttyS0,115200 earlyprintk=ttyS0,115200 consoleblank=0"/' /etc/default/grub
printf '%s\n' 'GRUB_RECORDFAIL_TIMEOUT=3' >> /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --removable --recheck
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck
grub-install --target=i386-pc /dev/sda --recheck
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT

sync
umount -R /mnt
systemctl reboot
