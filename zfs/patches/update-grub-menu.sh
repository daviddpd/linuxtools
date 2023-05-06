#!/bin/sh
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export ZPOOL_VDEV_NAME_PATH=YES
source /etc/os-release
FSLABEL=`grub2-probe -t fs_label /boot/efi`
if [ "x${FSLABEL}" != "EFI" ]; then
    mount /boot/efi
fi
grub2-mkconfig -o /boot/efi/EFI/${ID}/grub.cfg
cp /boot/efi/EFI/${ID}/grub.cfg /boot/efi/EFI/${ID}/grub2/grub.cfg
cp /boot/efi/EFI/${ID}/grub.cfg /boot/grub2/grub.cfg
