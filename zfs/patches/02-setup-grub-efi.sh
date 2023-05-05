#!/bin/sh
DISK="$@"
rm -f /etc/zfs/zpool.cache
touch /etc/zfs/zpool.cache
chmod a-w /etc/zfs/zpool.cache
chattr +i /etc/zfs/zpool.cache
for directory in /lib/modules/*; do
  kernel_version=$(basename $directory)
  dracut --force --kver $kernel_version
done
mkdir -p /boot/efi/EFI/rocky        # EFI GRUB dir
mkdir -p /boot/efi/EFI/rocky/grub2  # legacy GRUB dir
mkdir -p /boot/grub2
for i in ${DISK}; do
  grub2-install --boot-directory /boot/efi/EFI/rocky --target=i386-pc $i
done
for i in ${DISK}; do
  efibootmgr -cgp 1 -l "\EFI\rocky\shimx64.efi" -L "rocky-${i##*/}" -d ${i}
done
cp -r /usr/lib/grub/x86_64-efi/ /boot/efi/EFI/rocky
