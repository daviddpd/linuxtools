blkid  | grep EFI | awk '{print $6}' | awk -F= '{print $1"="$2" /boot/efi vfat x-systemd.idle-timeout=1min,x-systemd.automount,noauto,umask=0022,fmask=0022,dmask=0022 0 1"}' | sed -E 's/"//g'
