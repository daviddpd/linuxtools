ZFS on Linux
============


ZFS Root On EL8 (Rocky Linux)
-----------------------------
Copyright (c) 2022 David P. Discher * Released into the public domain.

So, March, 2022, I started off - let's do linux on zfs root.  FreeBSD works so well, it would be easy, right?  No.

OpenZFS has a Guide for [RHEL-based distro's like Rocky Linux](https://openzfs.github.io/openzfs-docs/Getting%20Started/RHEL-based%20distro/RHEL%208-based%20distro%20Root%20on%20ZFS.html) but there were some gotchas and a bunch of things that were unclear.  Though they seem to provide script like directions, I didn't see a script.  Additionally, I wanted to leverage the kickstart file and meta packages I already had to build my reference image.

I assume this should work across multiple distros and hardware, however, this was developed and Tested with Rocky Linux 8.5, on XCP-ng (Xen Hypervisor) using XOA to control the VMs. 

This took me about 4 work days ... (so ~ 32 hours) to work out. And as a 20+ year consumer, working through these issues manually, gives one some experiences and lessons learned, that are often lost or the struggle forgotten. So, here are some notes for me ... maybe they'll be helpful for someone else.

### Limitations 
+ Both BIOS and EFI booting works.
+ There is a separate BOOT pool because GRUB doesn't support the lastest ZPOOL feature set.
    + Future Idea: Merging Boot and EFI? ... boot from vfat. 
+ Disks are manually defined.
+ ZFS RAID Levels are manually set.  Right now, 10's are supported (10, 50, 60 ... ext ... stripes over parity sets.) 
+ defining swap is untested, and not added to fstab
+ ESP(EFI) is only installed to the first disk.
+ I did not address encryption or Secure Boot
+ I did not install or test Boot Environments
+ recuse is untested


### Lessons Learns, Issues, and Bugs

+ Order of operations in this script are NOT arbitrary 
+ ESP(EFI) is only installed to the first disk.
    + based on the openzfs howto, this created some sort of recursive mounting and unmounting issue.
    + auto mount on esp partition is off
+ `etc/grub.d/10_linux` is provided as a patch, and as a conditional, and not replacing grub_probe with zdb. 
+ GRUB, Boot Pool, can be references as `/rocky/BOOT/default@` or `/rocky/BOOT/default/@` ... I'm assuming the `@` is referencing a snapshot. 
+ pkg:zfs-dracut is needed
+ when running commands in chroot, special file systems sys,proc & dev are needed.
+ for annacoda that `anaconda/product.d/${ID}.conf` is needed in `anaconda/conf.d/${ID}.conf`
    + w/o this, anaconda errors with `The RHSM DBus API is not available..` 
+ My base install system, was my own kickstart script with company specific meta packages and software.  However, from a default Rocky Install, the follow packages should be the only ones needs:
    + `anaconda-tui gdisk dosfstools grub2-efi-x64 grub2-pc-modules grub2-efi-x64-modules shim-x64 efibootmgr python3-dnf-plugin-post-transaction-actions zfs zfs-dracut`
+ Attempted to build install/squashfs for the pxe/cd installer
    + The image provided doesn't have enough free space to install zfs packages
    + I got close, but couldn't get a custom intsaller/rootfs image work, so I gave up, and just installed a full install to a disk with xfs/lvm to bootstrap an installed to a second hard drive.
+ Failure to boot:
    + if zpool can't be imported on first boot, drop to emergency  shell, and do `zpool import -f z && zpool export z`
    + should the base linux started import the root with `-f` to begin with?
    

    