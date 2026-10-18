#!/bin/bash
# Script de reparación automática para Arch Linux (systemd-boot)

echo "==> Montando particiones..."
mount /dev/nvme0n1p2 /mnt
mount --mkdir /dev/nvme0n1p1 /mnt/boot

echo "==> Reinstalando kernel y configurando systemd-boot en chroot..."
arch-chroot /mnt /bin/bash <<EOF
pacman -S --noconfirm linux
mkdir -p /boot/loader/entries
echo -e "title Arch Linux\nlinux /vmlinuz-linux\ninitrd /initramfs-linux.img\noptions root=/dev/nvme0n1p2 rw" > /boot/loader/entries/arch.conf
EOF

echo "==> Limpiando y reiniciando..."
umount -R /mnt
reboot
