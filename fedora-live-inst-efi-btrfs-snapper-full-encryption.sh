#!/bin/bash

function usage()
{
	echo "Usage: $0 [options] <target device>"
	echo "Executes the installation of the current LiveOS to the target device formatting"
	echo "with btrfs (/boot included in root) over full encryption luks1"
	echo
	echo "Options:"
	echo "       -h, --help   This help"
	echo
	echo "Parameters:"
	echo "       target device:   Where to install"
	echo
}

function DIE {
	exitcode=$1
	shift
	echo "$@" >&2
	exit $exitcode
}

while [[ $1 =~ ^\-.*$ && $1 != -- ]]; do
	case $1 in
		-h|--help) usage;
			exit 1;;
		*) echo Error: Unknown option $1 >&2;
			usage
			exit 1;;
	esac
	
	shift
done

TGT_DEV="$1"

if [[ -z "$TGT_DEV" ]]; then
	echo Error: Missing target device >&2
	usage
	exit 1
fi

if [[ ! "$TGT_DEV" =~ ^/dev/[a-z][a-z0-9]+$ ]]; then
	echo Invalid device $TGT_DEV >&2
	usage
	exit 1
fi

PART_PREFIX=""
if [[ "$TGT_DEV" =~ ^/dev/nvme[a-z0-9]+$ ]]; then
	PART_PREFIX="p"
fi

DEV_UEFI=${TGT_DEV}${PART_PREFIX}1
DEV_ROOT=${TGT_DEV}${PART_PREFIX}2

(( $(id -u) == 0 )) || DIE 1 User must be root

# Ask for passwords and account
LUKS_PASS=x
LUKS_PASS2=y
for (( count=0 ; count < 3 ; count++ )); do
	read -s -p "Encryption pass: " LUKS_PASS
	echo
	read -s -p "Confirm Encryption pass: " LUKS_PASS2
	echo
	if [[ "$LUKS_PASS" != "$LUKS_PASS2" ]] ; then 
		echo Passwords do not match, try again
	else
		break
	fi
done
[[ "$LUKS_PASS" != "$LUKS_PASS2" ]] && DIE 1 Passwords do not match, exiting

ROOT_PASS=x
ROOT_PASS2=y
for (( count=0 ; count < 3 ; count++ )); do
	read -s -p "root pass: " ROOT_PASS
	echo
	read -s -p "Confirm root pass: " ROOT_PASS2
	echo
	if [[ "$ROOT_PASS" != "$ROOT_PASS2" ]] ; then 
		echo Passwords do not match, try again
	else
		break
	fi
done
[[ "$ROOT_PASS" != "$ROOT_PASS2" ]] && DIE 1 Passwords do not match, exiting

read -p "Username: " USERNAME
read -p "$USERNAME Full Name: " USER_FULLNAME

USER_PASS=x
USER_PASS2=y
for (( count=0 ; count < 3 ; count++ )); do
	read -s -p "$USERNAME pass: " USER_PASS
	echo
	read -s -p "Confirm $USERNAME pass: " USER_PASS2
	echo
	if [[ "$USER_PASS" != "$USER_PASS2" ]] ; then 
		echo Passwords do not match, try again
	else
		break
	fi
done
[[ "$USER_PASS" != "$USER_PASS2" ]] && DIE 1 Passwords do not match, exiting

read -p "The content of the device $TGT_DEV will be lost. Type yes in uppercase to continue: " CONT_ANSWER
[[ "$CONT_ANSWER" != "YES" ]] && DIE 1 Terminating...

# Disabling SELinux to avoid errors in chroot environment when setting user password
setenforce 0

# Kill existing device partitions and table
for devpart in $(ls ${TGT_DEV}${PART_PREFIX}[0-9]* 2>/dev/null); do
	dd if=/dev/zero of=$devpart bs=1024 count=10
done

dd if=/dev/zero of=$TGT_DEV bs=1024 count=10

sync
sleep 30

# Partition with gpt: EFI and system
fdisk $TGT_DEV <<EOF || DIE 2 fdisk error 
g
n
1
2048
+600M
t
1
n
2


w
EOF
parted $TGT_DEV name 1 EFI-Boot name 2 System || DIE 2 parted error
mkfs.vfat -F 32 $DEV_UEFI || DIE 2 Error formating EFI partition
echo -n $LUKS_PASS | cryptsetup luksFormat --type luks1 $DEV_ROOT --key-file -  || DIE 2 Error formating luks partition

echo -n $LUKS_PASS | cryptsetup luksOpen $DEV_ROOT sysroot --key-file -  || DIE 2 Error opening luks partition

mkfs.btrfs /dev/mapper/sysroot || DIE 2 Error formating btrfs partition
mkdir /mnt/sys || DIE 2 Error making /mnt/sys directory
mount -odefaults,subvolid=5,ssd,noatime,space_cache,commit=120,compress=zstd /dev/mapper/sysroot /mnt/sys  || DIE 2 Error mounting /mnt/sys directory
btrfs quota enable /mnt/sys
btrfs subvolume create /mnt/sys/root || DIE 2 Error creating root volume
btrfs subvolume create /mnt/sys/home || DIE 2 Error creating home volume
btrfs subvolume set-default /mnt/sys/root || DIE 2 Error setting root as default volume

# Subvolumes for snapshots
btrfs subvolume create /mnt/sys/root-snapshots || DIE 2 Error creating root snapshot volume
btrfs subvolume create /mnt/sys/home-snapshots || DIE 2 Error creating home snapshot volume

mkdir /mnt/sysimage || DIE 2 Error making /mnt/sysimage directory
mount -odefaults,ssd,noatime,space_cache,commit=120,compress=zstd /dev/mapper/sysroot /mnt/sysimage || DIE 2 Error mounting /mnt/sysimage directory

mkdir -p /mnt/sysimage/boot/efi || DIE 2 Error making /mnt/sysimage/boot/efi directory
mount $DEV_UEFI /mnt/sysimage/boot/efi || DIE 2 Error mounting EFI partition

mkdir /mnt/source || DIE 2 Error making /mnt/source directory
mount /dev/mapper/live-base /mnt/source || DIE 2 Error mounting /mnt/source directory

# Software Installation
rsync -pogAXtlHrDx --exclude /dev/ --exclude /proc/ --exclude '/tmp/*' --exclude /sys/ --exclude /run/ --exclude '/boot/*rescue*' --exclude /boot/loader/ --exclude /boot/efi/loader/ --exclude /etc/machine-id /mnt/source/ /mnt/sysimage

# EFI partition needs to be mounted again from within chroot for installation to work
umount /mnt/sysimage/boot/efi || DIE 2 Error umounting EFI partition

EFI_UUID=$(blkid -s UUID -o value $DEV_UEFI)
LUKS_UUID=$(blkid -s UUID -o value  ${DEV_ROOT})
BTRFS_UUID=$(blkid -s UUID -o value  /dev/mapper/sysroot)

# Key for partition
cat <<EOF >/mnt/sysimage/etc/crypttab
sysroot UUID=$LUKS_UUID /etc/keys/root.key luks,discard
EOF

# fstab with efi, root, home and snapshots
cat <<EOF >/mnt/sysimage/etc/fstab
#
# /etc/fstab
#
# Accessible filesystems, by reference, are maintained under '/dev/disk/'.
# See man pages fstab(5), findfs(8), mount(8) and/or blkid(8) for more info.
#
# After editing this file, run 'systemctl daemon-reload' to update systemd
# units generated from this file.
#
UUID=$BTRFS_UUID /                       btrfs   defaults,ssd,noatime,space_cache,commit=120,compress=zstd,x-systemd.device-timeout=0 0 0
UUID=$EFI_UUID                            /boot/efi               vfat    umask=0077,shortname=winnt 0 2
UUID=$BTRFS_UUID /home                   btrfs   defaults,subvol=home,ssd,noatime,space_cache,commit=120,compress=zstd,x-systemd.device-timeout=0 0 0

UUID=$BTRFS_UUID /.snapshots             btrfs   defaults,subvol=root-snapshots,ssd,noatime,space_cache,commit=120,compress=zstd,x-systemd.device-timeout=0 0 0
UUID=$BTRFS_UUID /home/.snapshots        btrfs   defaults,subvol=home-snapshots,ssd,noatime,space_cache,commit=120,compress=zstd,x-systemd.device-timeout=0 0 0

vartmp   /var/tmp    tmpfs   defaults   0  0

EOF

# Grub configuration with cryptodisk and btrfs snapshot booting
cat <<EOF >/mnt/sysimage/etc/default/grub
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=false
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="root=UUID=$BTRFS_UUID ro rd.luks.uuid=luks-$LUKS_UUID rhgb quiet"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
GRUB_ENABLE_CRYPTODISK=y
SUSE_BTRFS_SNAPSHOT_BOOTING=true
EOF

# Install the luks key in the initram image
cat <<EOF >/mnt/sysimage/etc/dracut.conf.d/add-keys.conf
install_items+=" /etc/keys/root.key "
EOF

cat <<EOF >/mnt/sysimage/etc/sysconfig/kernel
# UPDATEDEFAULT specifies if new-kernel-pkg should make
# new kernels the default
UPDATEDEFAULT=yes

# DEFAULTKERNEL specifies the default kernel package type
DEFAULTKERNEL=kernel-core

EOF

# install patch in live image to patch addition of new kernels
# https://bugzilla.redhat.com/show_bug.cgi?id=1906191
dnf install -y patch
cd /
patch -p 1 <<EOF
--- /mnt/sysimage/usr/lib/kernel/install.d/20-grub.install  2020-08-31 08:07:01.000000000 -0400
+++ /mnt/sysimage/usr/lib/kernel/install.d/20-grub.install  2020-12-09 15:27:16.894798980 -0500
@@ -104,7 +104,11 @@
 
             LINUX="\$(grep '^linux[ \t]' "\${BLS_TARGET}" | sed -e 's,^linux[ \t]*,,')"
             INITRD="\$(grep '^initrd[ \t]' "\${BLS_TARGET}" | sed -e 's,^initrd[ \t]*,,')"
-            LINUX_RELPATH="\$(grub2-mkrelpath /boot\${LINUX})"
+            if [[ "\$(grub2-probe --device \$(grub2-probe --target=device /) --target=fs)" == "btrfs" && "\${SUSE_BTRFS_SNAPSHOT_BOOTING}" == "true" ]]; then
+                LINUX_RELPATH="\$(grub2-mkrelpath -r /boot\${LINUX})"
+            else
+                LINUX_RELPATH="\$(grub2-mkrelpath /boot\${LINUX})"
+            fi
             BOOTPREFIX="\$(dirname \${LINUX_RELPATH})"
             ROOTPREFIX="\$(dirname "/boot\${LINUX}")"
EOF

# create key for luks device
mkdir -m0700 /mnt/sysimage/etc/keys || DIE 2 Error making keys directory
( umask 0077 && dd if=/dev/urandom bs=1 count=64 of=/mnt/sysimage/etc/keys/root.key conv=excl,fsync )
echo -n $LUKS_PASS | cryptsetup luksAddKey /dev/sda2 /mnt/sysimage/etc/keys/root.key --key-file -

# preparing for chroot
mkdir -p /mnt/sysimage/{dev,run,sys,proc} || DIE 2 Error making system directories
mount -v -o bind /dev /mnt/sysimage/dev/ || DIE 2 Error mounting dev
mount -v -o bind /run /mnt/sysimage/run/ || DIE 2 Error mounting run
mount -v -t proc proc /mnt/sysimage/proc/ || DIE 2 Error mounting proc
mount -v -t sysfs sys /mnt/sysimage/sys/ || DIE 2 Error mounting sys

# set root password (variables are not passed to chroot)
echo -n $ROOT_PASS | chroot /mnt/sysimage passwd --stdin root

# setup machine-id, grub, EFI boot
# reinstalling kernel so grub BLS entries and rescue image are created
# fix BLS options as they use the current kernel parameters from the live image
# install snapper
chroot /mnt/sysimage bash <<'ENDCHROOT'
LUKS_UUID=$(lsblk -fs | grep sysroot -A 1 | grep crypto | awk '{ print $4 }')
BTRFS_UUID=$(blkid -s UUID -o value  /dev/mapper/sysroot)

mount -t efivarfs efivarfs /sys/firmware/efi/efivars/
mount /boot/efi
mount /home

systemd-machine-id-setup

grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg
efibootmgr -c -d /dev/sda -p 1 -L Fedora -l '\EFI\fedora\shimx64.efi'

grub2-editenv /boot/efi/EFI/fedora/grubenv set blsdir=/boot/loader/entries

dnf reinstall -y kernel-core

sed -i "s@^options root=.*@options root=UUID=$BTRFS_UUID ro rd.luks.uuid=luks-$LUKS_UUID rhgb quiet \${extra_cmdline}@g" /boot/loader/entries/*.conf

dnf install -y snapper python3-dnf-plugins-extras-snapper

umount /home
umount /boot/efi
umount /sys/firmware/efi/efivars

ENDCHROOT

# Setup regular user account
mount $DEV_UEFI /mnt/sysimage/boot/efi || DIE 2 Error mounting EFI partition
mount -odefaults,subvol=home,ssd,noatime,space_cache,commit=120,compress=zstd /dev/mapper/sysroot /mnt/sysimage/home || DIE 2 Error mounting home partition

chroot /mnt/sysimage useradd -c "${USER_FULLNAME}" -G wheel $USERNAME
echo -n $USER_PASS | chroot /mnt/sysimage passwd --stdin $USERNAME

# Setup snapper for root and home snapshots
mkdir /mnt/sys/root/.snapshots
mkdir /mnt/sys/home/.snapshots

cat <<EOF >/mnt/sysimage/etc/sysconfig/snapper 
## Path: System/Snapper

## Type:        string
## Default:     ""
# List of snapper configurations.
SNAPPER_CONFIGS="root home"

EOF

cat <<EOF >/mnt/sysimage/etc/snapper/configs/root 

# subvolume to snapshot
SUBVOLUME="/"

# filesystem type
FSTYPE="btrfs"


# btrfs qgroup for space aware cleanup algorithms
QGROUP=""


# fraction of the filesystems space the snapshots may use
SPACE_LIMIT="0.5"

# fraction of the filesystems space that should be free
FREE_LIMIT="0.2"


# users and groups allowed to work with config
ALLOW_USERS=""
ALLOW_GROUPS=""

# sync users and groups from ALLOW_USERS and ALLOW_GROUPS to .snapshots
# directory
SYNC_ACL="no"


# start comparing pre- and post-snapshot in background after creating
# post-snapshot
BACKGROUND_COMPARISON="yes"


# run daily number cleanup
NUMBER_CLEANUP="yes"

# limit for number cleanup
NUMBER_MIN_AGE="1800"
NUMBER_LIMIT="50"
NUMBER_LIMIT_IMPORTANT="10"


# create hourly snapshots
TIMELINE_CREATE="yes"

# cleanup hourly snapshots after some time
TIMELINE_CLEANUP="yes"

# limits for timeline cleanup
TIMELINE_MIN_AGE="1800"
TIMELINE_LIMIT_HOURLY="10"
TIMELINE_LIMIT_DAILY="10"
TIMELINE_LIMIT_WEEKLY="0"
TIMELINE_LIMIT_MONTHLY="10"
TIMELINE_LIMIT_YEARLY="10"


# cleanup empty pre-post-pairs
EMPTY_PRE_POST_CLEANUP="yes"

# limits for empty pre-post-pair cleanup
EMPTY_PRE_POST_MIN_AGE="1800"

EOF

sed 's@^SUBVOLUME="/"@SUBVOLUME="/home"@g' /mnt/sysimage/etc/snapper/configs/root >/mnt/sysimage/etc/snapper/configs/home

# relabel for SELinux
touch /mnt/sysimage/.autorelabel

umount /mnt/sysimage/boot/efi
umount /mnt/sysimage/home

umount /mnt/sysimage/{dev,run,sys,proc}
umount /mnt/sysimage
umount /mnt/sys
umount /mnt/source

cryptsetup luksClose sysroot

setenforce 1
