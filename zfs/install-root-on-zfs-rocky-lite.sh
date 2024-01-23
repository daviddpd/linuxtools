#!/bin/bash
# Copyright (c) 2022 David P. Discher 
# Release into public domain.

set -xe

# Rocky Linux 8 Root on ZFS
# Based on the documentation at 
#   https://openzfs.github.io/openzfs-docs/Getting%20Started/RHEL-based%20distro/RHEL%208-based%20distro%20Root%20on%20ZFS.html
# When comments per "OpenZFS", it means from this gettings started/how to doc, prior to March 18, 2022. 
#
# The directions didn't directly work, this should be a repeatable script
# for installation of a Root on ZFS for EL8 - probably should work for 
# Rocky, CentOS, Fedora ... but built for Rocky 8.5+
#
# There are a bunch of gotchas in the orignal openzfs directions for EL, like
# how critical the zfs-dracut pkg is, which commands run in chroot and not, that proc,sys & dev
# need to be mounted in the chroot, or for annacoda that "anaconda/product.d/${ID}.conf" is 
# needed in anaconda/conf.d/${ID}.conf

# NOTE: Nothing in here is done trivially, and the order of opperations for the most
#       part is very important.  So tread lightly when modifying or moving sections/blocks

########### Installer System - NOT THE LIVE FS/INSTALLER FORM THE CD ##############
# Before running this, install a standard Rocky Linux EL8 system from the CD, or 
# other favorite method, with standarf xfs/lvm file systems.
# DEPENDANCIES: install these in your installation environment   
#    dnf install -y anaconda-tui gdisk dosfstools grub2-efi-x64 grub2-pc-modules grub2-efi-x64-modules shim-x64 efibootmgr python3-dnf-plugin-post-transaction-actions zfs zfs-dracut
#
# WHY: The live filesystem seem to have too little free space to install zfs, I tried to
#      reroll it, but failed to get something working.  Ideally, if ZFS is included in the
#      installer, this can be adapted into a kickstart file instead of stand alone script.
#  

# This was created to be use for XCP-NG Xen VMs, running on a single
# disk.  The assumption is that you install the live system to  /dev/xvda 
# and the target drive is /dev/xvdb.  Where the /dev/xvdb will be 
# made into a template or used for thin-providing, cloning, in another in VM.

. /etc/os-release
: ${INST_RHEL_VER:=`rpm -E '%{rhel}'`}
: ${INST_ID=${ID}}
: ${INST_SYSTEM_TARGET:="VM"}  # Do if = VM

# Usage:  
# CONFIGURE 
# The disk(s) and the primary disk.  These are NOT auto detected.
# There were some issues in bootstrapping with UUIDs or labels
# so going to use old fashion blk device specs, and linux sytle 
# partition numbers : eg xvdb1, xvdb2, xvdb3, ... 
# Script changes below will be required to move it
: ${DISK:="/dev/xvdb"}
: ${INST_PRIMARY_DISK:='/dev/xvdb'}

if [ -z "${DISK}" -o -z "${INST_PRIMARY_DISK}" ]; then
    echo "You need to configure DISK and INST_PRIMARY_DISK";
    exit 1
fi

# CONFIGURE
#   if you have a need to change the mount point for the zfs file system
#   while building the system
: ${ZFS_ROOT_MOUNT:="/el8zfs"}

# CONFIGURE: 
#    Your partition sizes, and if you want a swap partition 
#    in this partition map.
: ${INST_PARTSIZE_ESP:=1}     # EFI/ESP PARTITION SIZE (GB)
: ${INST_PARTSIZE_BPOOL:=1}   # BOOT POOL (GB)
: ${INST_PARTSIZE_RPOOL:=}    # ROOT POOL (GB)
: ${INST_PARTSIZE_SWAP:=}     # SWAP SIZE (GB)

# CONFIGURE: 
#     Personal Preferences, these are naming conventions, which are 
#     really should be up to you.
#  Root Pool
: ${INST_ROOT_POOL_NAME:="z"}       # Using my "z" instead of "tank" or "rpool"
: ${INST_ROOT_CONATINER:="ROOT"}    # 
: ${INST_ROOT_POOL_TYPE:=""}        # Top level "VDEV", er, "raid" type:  'null|mirror|raidz|raidz1|raidz2|raidz3'
: ${INST_DATA_CONATINER:="DATA"}    # 
#  Boot Pool
: ${INST_BOOT_POOL_NAME:="b"}       # Using "b" instead of "bpool"
: ${INST_BOOT_CONATINER:="BOOT"}    # 
: ${INST_BOOT_POOL_TYPE:=""}        # Top level "VDEV", er, "raid" type:  'null|mirror|raidz|raidz1|raidz2|raidz3'
: ${ZFS_ASHIFT:=12}                 # set ashift to 12(4k);  9(512bytes)

# CONFIGURE: 
#   UUIDs are used in the docs. 
: ${USE_UUID:=""}   # empty for none, ref = how the openzfs doc did it, or 
                    # "real|rfc|rfc4122|uuid|uuidgen" for a libuuid/uuidgen style.

# CONFIGURE: 
# Use anaconda to installe, with the kickstart file
# DEPENDANCIES: Ensure the dependancies are included with the Kickstart set of packages.
: ${USE_ANACONDA:="YES"}
# NOTE: KickStart files needs to be absolute path, otherwise Anaconda can't find it.
: ${USE_ANACONDA_KSFILE:="inst.ks"}
: ${USE_ANACONDA_TMPFS:="/INSTALL"}
: ${USE_RELEASE_TMPFS:="/R"}

# FIXME: well, this check doesn't work if this is http/https.
if [ -z "${USE_ANACONDA_KSFILE}" -o ! -f "${USE_ANACONDA_KSFILE}" ]; then
    echo "USE_ANACONDA_KSFILE is not set or file is not readable."
    exit 1
fi

# FIXME: Hook to use instead of Anaconda, needs to be implemented
: ${INST_INSTALL_SCRIPT:=""}

if [ -f "/etc/os-release" ]; then
    . /etc/os-release
    : ${DISTRO:="${ID}"}
    major=`echo "${VERSION_ID}" | awk -F. '{print $1}'`
    : ${VERSION_MAJOR:="${major}"}
fi

: ${DIR:="/z/dist"}
: ${SNAP:=}
: ${BUILD:=1}
: ${DISTDIR:="${DIR}/${DISTRO}/${VERSION_MAJOR}/${SNAP}"}

if [ -z "${SNAP}" ]; then
    echo "SNAP not set, please set as env : ${SNAP}"
    exit 1;
fi

if [ ! -d "${DISTDIR}" ]; then
    echo "Can't find DISTDIR : ${DISTDIR}"
    exit 1;
fi

ROCKYRELEASE_GLOB="${DISTDIR}/rpms/baseos/Packages/r/rocky-release*"
ROCKYRELEASE=`ls -1 ${ROCKYRELEASE_GLOB} | sed -e 's/.*rocky-release-//g' | awk -F\- '{print $1}' | sed -e 's/\.//g' | head -1`
TARBALL="${DISTRO}-${ROCKYRELEASE}-${SNAP}-v${BUILD}.tgz"

while [ -f "${DISTDIR}/${TARBALL}" ]; do
    TARBALL_LAST="${DISTRO}-${ROCKYRELEASE}-${SNAP}-v${BUILD}.tgz"
    BUILD=$((BUILD+1))
    TARBALL="${DISTRO}-${ROCKYRELEASE}-${SNAP}-v${BUILD}.tgz"
done


#
##
### END OF USER CONFIGURATIONS #################################################################


case "${USE_UUID}" in
    ref)
        INST_UUID=$(dd if=/dev/urandom bs=1 count=100 2>/dev/null | tr -dc 'a-z0-9' | cut -c-6)
        INST_UUID="_${INST_UUID}"
    ;;
    real|rfc|rfc4122|uuid|uuidgen)
        # Use RFC 4122/libuuid to generate a real UUID
        if [ -x "/usr/bin/uuidgen" ]; then
            uuid=`/usr/bin/uuidgen --time`
            INST_UUID="_{$uuid}"
        fi
    ;;
    *)
        # Don't use a UUID string in the pool name
        INST_UUID=
    ;;
esac

## Assuming the Install environment has zfs repos enabled.
# . /etc/os-release
# RHEL_ZFS_REPO_NEW=https://zfsonlinux.org/epel/zfs-release.el${VERSION_ID/./_}.noarch.rpm
# dnf install -y $RHEL_ZFS_REPO_NEW || true
# dnf config-manager --installroot=${ZFS_ROOT_MOUNT} --disable zfs
# dnf config-manager --installroot=${ZFS_ROOT_MOUNT} --enable zfs-kmod

# All this will be taken care via KS install in the "bootstrap" install system.
# rpm -ivh --nodeps https://dl.fedoraproject.org/pub/fedora/linux/releases/35/Everything/x86_64/os/Packages/a/arch-install-scripts-24-2.fc35.noarch.rpm
# dnf -y install gdisk dosfstools
# dnf -y install  grub2-efi-x64 grub2-pc-modules grub2-efi-x64-modules shim-x64 efibootmgr python3-dnf-plugin-post-transaction-actions zfs zfs-dracut

## This is in the OpenZFS Docs, placed here for reference
# for i in ${DISK}; do
#     blkdiscard $i &
# done
# wait

zpool import -R ${ZFS_ROOT_MOUNT} ${INST_ROOT_POOL_NAME} || true 
zpool import -R ${ZFS_ROOT_MOUNT} ${INST_BOOT_POOL_NAME} || true 
zfs umount -a || true 
df | grep ${ZFS_ROOT_MOUNT} | awk '{print $6}' | sort -r | xargs -I % sudo umount %
zpool destroy -f ${INST_BOOT_POOL_NAME} || true 
zpool destroy -f ${INST_ROOT_POOL_NAME} || true 

for i in ${DISK}; do
    sgdisk --zap-all $i
    sgdisk -n1:1M:+${INST_PARTSIZE_ESP}G -t1:EF00 $i
    sgdisk -n2:0:+${INST_PARTSIZE_BPOOL}G -t2:BE00 $i
if [ "${INST_PARTSIZE_SWAP}" != "" ]; then
    sgdisk -n4:0:+${INST_PARTSIZE_SWAP}G -t4:8200 $i
fi
if [ "${INST_PARTSIZE_RPOOL}" = "" ]; then
    sgdisk -n3:0:0   -t3:BF00 $i
else
    sgdisk -n3:0:+${INST_PARTSIZE_RPOOL}G -t3:BF00 $i
fi
    sgdisk -a1 -n5:24K:+1000K -t5:EF02 $i
done


#############################
### Create Root Pool - all features, tuned for linux
### Per OpenZFS doc; diffs changed: mountpoint & top VDEV spec
###
#############################      

/sbin/modprobe zfs
      
zpool create -f \
    -o ashift=${ZFS_ASHIFT} \
    -o autotrim=on \
    -R ${ZFS_ROOT_MOUNT} \
    -O acltype=posixacl \
    -O canmount=off \
    -O compression=zstd \
    -O dnodesize=auto \
    -O normalization=formD \
    -O relatime=on \
    -O xattr=sa \
    -O mountpoint=none \
    ${INST_ROOT_POOL_NAME}${INST_UUID} \
    ${INST_ROOT_POOL_TYPE} \
    $(for i in ${DISK}; do
      printf "${i}3 ";
     done)      
     
     
#############################
### Create Boot Pool
###   The understanding here, grub only supports a subset of zpool
###   features, so the boot pool needs to be different than the main pool
###   IDEA: don't use boot pool, but use ESP/EFI partition to function as the /boot 
###         instead of two zpools.
### Changed: mountpoint, top VDEV spec/selection
#############################

zpool create -f \
-d -o feature@async_destroy=enabled \
-o feature@bookmarks=enabled \
-o feature@embedded_data=enabled \
-o feature@empty_bpobj=enabled \
-o feature@enabled_txg=enabled \
-o feature@extensible_dataset=enabled \
-o feature@filesystem_limits=enabled \
-o feature@hole_birth=enabled \
-o feature@large_blocks=enabled \
-o feature@lz4_compress=enabled \
-o feature@spacemap_histogram=enabled \
    -o ashift=${ZFS_ASHIFT} \
    -o autotrim=on \
    -O acltype=posixacl \
    -O canmount=off \
    -O compression=lz4 \
    -O devices=off \
    -O normalization=formD \
    -O relatime=on \
    -O xattr=sa \
    -O mountpoint=none \
    -R ${ZFS_ROOT_MOUNT} \
    ${INST_BOOT_POOL_NAME}${INST_UUID} \
    ${INST_BOOT_POOL_TYPE} \
    $(for i in ${DISK}; do
       printf "${i}2 ";
      done)

# Create Containers 
# Diffs:  canmount adjusted to make sense; 
#         enable lz4 compression, though this is the default, explicit here.
#         in the zpool create for the Root Pool; the Boot Pool is compression=zstd
#
bootPrefix="${INST_BOOT_POOL_NAME}${INST_UUID}/${INST_ID}/${INST_BOOT_CONATINER}"
rootPrefix="${INST_ROOT_POOL_NAME}${INST_UUID}/${INST_ID}/${INST_ROOT_CONATINER}"
dataPrefix="${INST_ROOT_POOL_NAME}${INST_UUID}/${INST_ID}/${INST_DATA_CONATINER}"

    zfs create -p \
        -o canmount=off \
        -o mountpoint=none \
        ${bootPrefix}/default

    zfs create -p \
        -o compression=lz4 \
        -o canmount=off \
        -o mountpoint=none \
        ${rootPrefix}/default

    zfs create -p \
        -o compression=gzip \
        -o canmount=off \
        -o mountpoint=/ \
        ${dataPrefix}

zfs set mountpoint=/  ${rootPrefix}/default
zfs set canmount=on   ${rootPrefix}/default
zfs set mountpoint=/boot ${bootPrefix}/default 
zfs set canmount=on      ${bootPrefix}/default
zpool set bootfs=${rootPrefix}/default ${INST_ROOT_POOL_NAME}${INST_UUID}


# Create Other Data set - These that would want to carry over from Boot Environments 
#  Note :  root,srv,usr/local,opt - shouldn't this be part of the boot environment?, 
#          so I made it os
#
#  Sigh, if only linux followed freebsd's HIER(7)
#
#  Move into INST_DATA_CONATINER, so to handle/manage mountpoint inheritance with
#  some sort of sanity, and have INST_ROOT_CONATINER only for boot environments. 
#  FIXME:CHECKME : I'm FreeBSD not Linux, so there still may be some paths to be shuffled between 
#                  DATA and ROOT. I'm targeting VMs, so unlikely to use Boot Enviroments, as will 
#                  just deploy VMs with different images ( Different "AMI"s, in AWS terms.) 

#
# Diffs:  canmount adjusted to make sense; 
#         enable lz4 compression, though this is the default, explicit here, because 
#         these might benefit from gzip-9 (on logs), especially if you turn 
#         off per-file compression in logrotate/rotatelogs/etc.
#
for i in {var,var/lib,var/log,var/spool,var/cache,var/db,var/www,home};
do
    zfs create -o canmount=on -o compression=lz4 ${dataPrefix}/${i}
done
for i in {var/log,var/spool,var/www,home};
do
    zfs set compression=gzip-9 ${dataPrefix}/${i}
done

zfs umount ${bootPrefix}/default || true
zfs umount -a || true
zfs umount -a || true


zfs mount ${rootPrefix}/default 
zfs mount ${bootPrefix}/default 
zfs mount -a

# FIXME: This is needed with multiple disks, but since that
# is really not my goal here - this is causing some mount ordering
# issues ... linux and zfs on linux is behaving differently than
# freebsd in these cases.

for i in ${DISK}; do
     mkfs.vfat -n EFI ${i}1
#     mkdir -p ${ZFS_ROOT_MOUNT}/boot/efis/${i##*/}1
#     mount -t vfat ${i}1 ${ZFS_ROOT_MOUNT}/boot/efis/${i##*/}1
done

mkdir -p ${ZFS_ROOT_MOUNT}/boot/efi || true 
mount -t vfat ${INST_PRIMARY_DISK}1 ${ZFS_ROOT_MOUNT}/boot/efi || true

mkdir -p ${ZFS_ROOT_MOUNT}/root
chmod 750 ${ZFS_ROOT_MOUNT}/root

# if [ -n "${USE_ANACONDA}" ]; then
#     # Fix the "The RHSM DBus API is not available.."  error
#     cp -f /etc/anaconda/product.d/${ID}.conf /etc/anaconda/conf.d/ || true
#     
#     # NOTE: don't mount special file systems before anaconda - it does this itself,
#     #       and will fail if mounted.
#     
#     _DIRINSTALL="${ZFS_ROOT_MOUNT}"
#     if [ -n "${USE_ANACONDA_TMPFS}" ]; then 
#         _DIRINSTALL="${USE_ANACONDA_TMPFS}"
#         umount ${USE_ANACONDA_TMPFS} || true 
#         umount ${USE_RELEASE_TMPFS} || true 
#         mkdir -p "${USE_ANACONDA_TMPFS}" || true
#         mkdir -p "${USE_RELEASE_TMPFS}" || true
#         mount -t tmpfs tmpfs "${USE_ANACONDA_TMPFS}"
#         mount -t tmpfs tmpfs "${USE_RELEASE_TMPFS}"
#     fi
#     # Run Annacoda to do the install (why totally re-invite the wheel, right?
#     echo | anaconda --text --cmdline --kickstart ${USE_ANACONDA_KSFILE}  --gpt  --dirinstall ${_DIRINSTALL}
#     # Anaconda is doing something to the zpool, and holding the pool open after everything is unmounted 
#     # to work-around this, install to a TMPFS, then move the files over to the zpool/zfs
#     if [ -n "${USE_ANACONDA_TMPFS}" ]; then 
#         
#         tar -C ${USE_ANACONDA_TMPFS} --ignore-command-error --xattrs -zcf ${USE_RELEASE_TMPFS}/${TARBALL} .
#         cp -v ${USE_RELEASE_TMPFS}/${TARBALL} ${DISTDIR}/${TARBALL} &
#         tar -C ${ZFS_ROOT_MOUNT} --ignore-command-error --xattrs -xf ${USE_RELEASE_TMPFS}/${TARBALL}
#         # umount ${USE_ANACONDA_TMPFS}
#     fi
#     
# elif [ -n "${INST_INSTALL_SCRIPT}" ]; then
#     # FIXME: Hook to use instead of Anaconda, needs to be implemented
#     echo "Error($0): Running ${INST_INSTALL_SCRIPT} is not implemented."
#     exit 1
# else
#     echo "Error($0): No software install will be done"
#     exit 1
# fi

tar -C ${ZFS_ROOT_MOUNT} --ignore-command-error --xattrs -xf ${USE_RELEASE_TMPFS}/${TARBALL_LAST}

mount -t proc proc ${ZFS_ROOT_MOUNT}/proc || true
mount -t sysfs sysfs ${ZFS_ROOT_MOUNT}/sys || true
mount -t devtmpfs devtmpfs ${ZFS_ROOT_MOUNT}/dev || true


echo 'add_dracutmodules+=" zfs "' > ${ZFS_ROOT_MOUNT}/etc/dracut.conf.d/zfs.conf || true
echo 'filesystems+=" virtio_blk "' >> ${ZFS_ROOT_MOUNT}/etc/dracut.conf.d/fs.conf  || true
rm -f ${ZFS_ROOT_MOUNT}/etc/default/grub || true
echo 'GRUB_ENABLE_BLSCFG=false' >> ${ZFS_ROOT_MOUNT}/etc/default/grub  || true
echo 'GRUB_DISABLE_OS_PROBER=true' >> ${ZFS_ROOT_MOUNT}/etc/default/grub  || true
if [ "x${INST_SYSTEM_TARGET}" == "xVM" ]; then
    echo 'GRUB_CMDLINE_LINUX+=" oops=panic call_trace=both mce=off edd=off"' >> ${ZFS_ROOT_MOUNT}/etc/default/grub  || true
fi

cp -v ./patches/09_fix_root_on_zfs ${ZFS_ROOT_MOUNT}/etc/grub.d/09_fix_root_on_zfs
chmod +x ${ZFS_ROOT_MOUNT}/etc/grub.d/09_fix_root_on_zfs


chroot ${ZFS_ROOT_MOUNT} sh -c "/sbin/modprobe zfs"
systemctl enable zfs-import-scan.service zfs-import.target zfs-zed zfs.target --root=${ZFS_ROOT_MOUNT}
systemctl disable zfs-mount --root=${ZFS_ROOT_MOUNT}

## This an attempt to fix hostid mismatch when using this as a template for 
## VM cloning.
#
#         status: Mismatch between pool hostid and system hostid on imported pool.
#             This pool was previously imported into a system with a different hostid,
#             and then was verbatim imported into this system.
#         action: Export this pool on all systems on which it is imported.
#             Then import it to correct the mismatch.

if [ -f "/etc/hostid" ]; then 
    mv /etc/hostid /etc/hostid.buildhost
fi 
rm -f ${ZFS_ROOT_MOUNT}/etc/hostid || true
chroot ${ZFS_ROOT_MOUNT} sh -c /sbin/zgenhostid
cp ${ZFS_ROOT_MOUNT}/etc/hostid /etc/hostid

zpool set multihost=on  z
zpool set multihost=off z
zpool set multihost=on  b
zpool set multihost=off b

zpool export ${INST_ROOT_POOL_NAME} || true
zpool export ${INST_BOOT_POOL_NAME} || true
zpool import -f -R ${ZFS_ROOT_MOUNT} ${INST_ROOT_POOL_NAME} || true 
zpool import -f -R ${ZFS_ROOT_MOUNT} ${INST_BOOT_POOL_NAME} || true 

## blkid  | grep EFI | awk '{print $6}' | awk -F= '{print $1"="$2" /boot/efi vfat x-systemd.idle-timeout=1min,x-systemd.automount,umask=0022,fmask=0022,dmask=0022 0 1"}' | sed -E 's/"//g'
# UUID=3df02bf3-b61b-401f-995d-841dd207b22b /boot                   xfs     defaults        0 0

cp ./patches/01-generate-fstab-efi.sh ${ZFS_ROOT_MOUNT}/root/01-generate-fstab-efi.sh 
chmod +x ${ZFS_ROOT_MOUNT}/root/01-generate-fstab-efi.sh 
chroot ${ZFS_ROOT_MOUNT} sh -c "sh /root/01-generate-fstab-efi.sh ${INST_PRIMARY_DISK}1 >> /etc/fstab"

cp -v ./patches/00-update-grub-menu-for-kernel.action ${ZFS_ROOT_MOUNT}/etc/dnf/plugins/post-transaction-actions.d/00-update-grub-menu-for-kernel.action
cp -v ./patches/update-grub-menu.sh ${ZFS_ROOT_MOUNT}/usr/local/sbin/update-grub-menu.sh
chmod +x ${ZFS_ROOT_MOUNT}/usr/local/sbin/update-grub-menu.sh
cp -v ./patches/02-setup-grub-efi.sh ${ZFS_ROOT_MOUNT}/root/02-setup-grub-efi.sh 
chmod +x ${ZFS_ROOT_MOUNT}/root/02-setup-grub-efi.sh

cp -v ./patches/10_linux.patch ${ZFS_ROOT_MOUNT}/root/10_linux.patch
patch -F 10 -i ${ZFS_ROOT_MOUNT}/root/10_linux.patch ${ZFS_ROOT_MOUNT}/etc/grub.d/10_linux
rm -f ${ZFS_ROOT_MOUNT}/etc/grub.d/10_linux.*

chroot ${ZFS_ROOT_MOUNT} sh -c "/root/02-setup-grub-efi.sh ${DISK}"
chroot ${ZFS_ROOT_MOUNT} sh -c "env ZPOOL_VDEV_NAME_PATH=1 grub2-mkconfig -o /boot/efi/EFI/rocky/grub.cfg"
cp -f ${ZFS_ROOT_MOUNT}/boot/efi/EFI/rocky/grub.cfg ${ZFS_ROOT_MOUNT}/boot/efi/EFI/rocky/grub2/grub.cfg
cp -f ${ZFS_ROOT_MOUNT}/boot/efi/EFI/rocky/grub.cfg ${ZFS_ROOT_MOUNT}/boot/grub2/grub.cfg

umount ${ZFS_ROOT_MOUNT}/proc || true
umount ${ZFS_ROOT_MOUNT}/sys  || true
umount ${ZFS_ROOT_MOUNT}/dev  || true
for i in ${DISK}; do
    umount ${ZFS_ROOT_MOUNT}/boot/efis/${i}1 || true
done
umount ${ZFS_ROOT_MOUNT}/boot/efi || true

zfs umount ${bootPrefix}/default || true
zfs umount -a || true

zpool export ${INST_ROOT_POOL_NAME} || true
zpool export ${INST_BOOT_POOL_NAME} || true

if [ -f "/etc/hostid.buildhost" ]; then 
    mv /etc/hostid.buildhost /etc/hostid
else 
    rm -f /etc/hostid || true
fi
