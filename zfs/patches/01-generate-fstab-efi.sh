#!/bin/sh
set -x
EFIDEV=$1
BOOTDEV=$2
ROOTDEV=$3

check()
{

        _blkdev=$1
        _match=$2
        for _subject in `blkid ${_blkdev}`; do
                echo $_subject | grep $_match > /dev/null
                if [ $? -eq 0 ]; then
                        echo $_subject
                fi
        done
}


if [ -n "${ROOTDEV}" ]; then
        x=$(check "${ROOTDEV}" "LVM2_member")
        if [ -n "$x" ]; then
                echo "/dev/mapper/vg0-lv0    /                       xfs     defaults        0 0"
        fi
fi

# Rocky 8.7 default installer
# UUID=3df02bf3-b61b-401f-995d-841dd207b22b /boot                   xfs     defaults        0 0
# UUID=4AA3-E19A          /boot/efi               vfat    defaults,uid=0,gid=0,umask=077,shortname=winnt 0 2

if [ -n "${BOOTDEV}" ]; then
        x=$(check "${BOOTDEV}" "PARTUUID")
        if [ -n "$x" ]; then
                echo $x | awk -F= '{print $1"="$2" /boot                   xfs     defaults        0 0"}' | sed -E 's/"//g'
        fi
fi

if [ -n "${EFIDEV}" ]; then
        x=$(check "${EFIDEV}" "PARTUUID")
        if [ -n "$x" ]; then
                echo $x | awk -F= '{print $1"="$2" /boot/efi vfat x-systemd.idle-timeout=1min,x-systemd.automount,noauto,umask=0022,fmask=0022,dmask=0022 0 1"}' | sed -E 's/"//g'
        fi
fi

