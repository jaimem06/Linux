#!/bin/bash
LOG_FILE="/tmp/repair_debug.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "==> [1/3] Montando particiones..."
mount /dev/nvme0n1p2 /mnt
mount --mkdir /dev/nvme0n1p1 /mnt/boot

echo "==> [2/3] Instalando kernel dentro del chroot..."
arch-chroot /mnt /bin/bash <<EOF
pacman -Sy --noconfirm linux
mkdir -p /boot/loader/entries
echo -e "title Arch Linux\nlinux /vmlinuz-linux\ninitrd /initramfs-linux.img\noptions root=/dev/nvme0n1p2 rw" > /boot/loader/entries/arch.conf
EOF

echo "==> [3/3] Proceso finalizado. Revisa si hubo errores arriba."
read -p "Presiona [Enter] para desmontar y reiniciar manualmente..."

umount -R /mnt
reboot
