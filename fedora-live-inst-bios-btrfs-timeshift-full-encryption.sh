#!/bin/bash

function usage()
{
	echo "Usage: $0 [options] <target device>"
	echo "Executes the installation of the current LiveOS to the target device formatting"
	echo "with btrfs (/boot included in root) over full encryption luks2 for timeshift usage"
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

DEV_ROOT=${TGT_DEV}${PART_PREFIX}1

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
o
n




w
EOF

# grub2-install with bios does not work with luks2. After install grub2-mkimage and grub2-bios-setup are used to create a working core.img (stage 1.5)
echo -n $LUKS_PASS | cryptsetup -qv luksFormat $DEV_ROOT --pbkdf pbkdf2 --key-file -  || DIE 2 Error formating luks partition

echo -n $LUKS_PASS | cryptsetup luksOpen $DEV_ROOT sysroot --key-file -  || DIE 2 Error opening luks partition

mkfs.btrfs /dev/mapper/sysroot || DIE 2 Error formating btrfs partition
mkdir /mnt/sys || DIE 2 Error making /mnt/sys directory
mount -odefaults,subvolid=5,noatime,compress=zstd /dev/mapper/sysroot /mnt/sys  || DIE 2 Error mounting /mnt/sys directory
btrfs quota enable /mnt/sys
btrfs subvolume create /mnt/sys/@ || DIE 2 Error creating root volume
btrfs subvolume create /mnt/sys/@home || DIE 2 Error creating home volume

mkdir /mnt/sysimage || DIE 2 Error making /mnt/sysimage directory
mount -osubvol=@,defaults,noatime,compress=zstd /dev/mapper/sysroot /mnt/sysimage || DIE 2 Error mounting /mnt/sysimage directory

mkdir /mnt/source || DIE 2 Error making /mnt/source directory
mount /dev/mapper/live-base /mnt/source || DIE 2 Error mounting /mnt/source directory

# Software Installation
rsync -pogAXtlHrDx --info=progress2 --exclude /dev/ --exclude /proc/ --exclude '/tmp/*' --exclude /sys/ --exclude /run/ --exclude '/boot/*rescue*' --exclude /boot/loader/ --exclude /boot/efi/loader/ --exclude /etc/machine-id /mnt/source/ /mnt/sysimage

LUKS_UUID=$(blkid -s UUID -o value  $DEV_ROOT)
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
UUID=$BTRFS_UUID /                       btrfs   defaults,subvol=@,noatime,compress=zstd,x-systemd.device-timeout=0 0 0
UUID=$BTRFS_UUID /home                   btrfs   defaults,subvol=@home,noatime,compress=zstd,x-systemd.device-timeout=0 0 0

tmpfs    /tmp        tmpfs   defaults   0  0
vartmp   /var/tmp    tmpfs   defaults   0  0

EOF

# Grub boot configuration for core.img
cat <<EOF >/mnt/sysimage/root/early-grub.cfg
insmod luks2
insmod cryptodisk
insmod btrfs
insmod search
insmod configfile

cryptomount -u ${LUKS_UUID//\-/}
set root='cryptouuid/${LUKS_UUID//\-/}'

search --no-floppy --fs-uuid --set=dev --hint='cryptouuid/${LUKS_UUID//\-/}'  $BTRFS_UUID

set prefix=(\$dev)/@/boot/grub2
export \$prefix
configfile \$prefix/grub.cfg

EOF

# Grub configuration with cryptodisk and btrfs snapshot booting
cat <<EOF >/mnt/sysimage/etc/default/grub
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="\$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=false
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="ro rd.luks.uuid=luks-$LUKS_UUID rhgb quiet"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
GRUB_ENABLE_CRYPTODISK=y
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

# create key for luks device
mkdir -m0700 /mnt/sysimage/etc/keys || DIE 2 Error making keys directory
( umask 0077 && dd if=/dev/urandom bs=1 count=64 of=/mnt/sysimage/etc/keys/root.key conv=excl,fsync )
echo -n $LUKS_PASS | cryptsetup luksAddKey $DEV_ROOT /mnt/sysimage/etc/keys/root.key --key-file -

# preparing for chroot
mkdir -p /mnt/sysimage/{dev,run,sys,proc} || DIE 2 Error making system directories
mount -v -o bind /dev /mnt/sysimage/dev/ || DIE 2 Error mounting dev
mount -v -o bind /run /mnt/sysimage/run/ || DIE 2 Error mounting run
mount -v -t proc proc /mnt/sysimage/proc/ || DIE 2 Error mounting proc
mount -v -t sysfs sys /mnt/sysimage/sys/ || DIE 2 Error mounting sys

# set root password (variables are not passed to chroot)
echo -n $ROOT_PASS | chroot /mnt/sysimage passwd --stdin root

# setup machine-id, grub
# reinstalling kernel so grub BLS entries and rescue image are created
# fix BLS options as they use the current kernel parameters from the live image
# install and configure timeshift
chroot /mnt/sysimage bash <<'ENDCHROOT'
TGT_DEV="/dev/$(lsblk -fs | grep sysroot -A 2 | egrep -v 'sysroot|crypto' | sed 's@^[^sn]\+@@g')"
LUKS_UUID=$(lsblk -fs | grep sysroot -A 1 | grep crypto | awk '{ print $4 }')
BTRFS_UUID=$(blkid -s UUID -o value  /dev/mapper/sysroot)

mount -av

systemd-machine-id-setup

grub2-mkconfig -o /boot/grub2/grub.cfg
grub2-install --modules "cryptodisk btrfs luks luks2" $TGT_DEV

grub2-mkimage -c /root/early-grub.cfg -o /boot/grub2/i386-pc/core.img -O i386-pc -p /@/boot/grub2 -C auto -v luks2 all_video boot blscfg btrfs cat configfile cryptodisk echo ext2 fat font gcry_rijndael gcry_rsa gcry_serpent gcry_sha256 gcry_twofish gcry_whirlpool gfxmenu gfxterm gzio halt hfsplus http increment iso9660 jpeg loadenv loopback linux lvm luks mdraid09 mdraid1x minicmd net normal part_apple part_msdos part_gpt password_pbkdf2 pgp png reboot regexp search search_fs_uuid search_fs_file search_label serial sleep syslinuxcfg test tftp version video xfs zstd biosdisk
grub2-bios-setup -d /boot/grub2/i386-pc/ /dev/sda

grub2-editenv /boot/grub2/grubenv set blsdir=/@/boot/loader/entries

dnf reinstall -y kernel-core

sed -i "s,^options root=.*,options root=UUID=$BTRFS_UUID ro rootflags=subvol=@ rd.luks.uuid=luks-$LUKS_UUID rhgb quiet \${extra_cmdline},g" /boot/loader/entries/*.conf

dnf install -y timeshift python3-dnf-plugins-extras-common

cat <<EOF >/etc/timeshift.json
{
  "backup_device_uuid" : "$BTRFS_UUID",
  "parent_device_uuid" : "$LUKS_UUID",
  "do_first_run" : "false",
  "btrfs_mode" : "true",
  "include_btrfs_home_for_backup" : "true",
  "include_btrfs_home_for_restore" : "false",
  "stop_cron_emails" : "true",
  "btrfs_use_qgroup" : "true",
  "schedule_monthly" : "true",
  "schedule_weekly" : "true",
  "schedule_daily" : "true",
  "schedule_hourly" : "false",
  "schedule_boot" : "true",
  "count_monthly" : "1",
  "count_weekly" : "3",
  "count_daily" : "5",
  "count_hourly" : "6",
  "count_boot" : "3",
  "snapshot_size" : "0",
  "snapshot_count" : "0",
  "date_format" : "%Y-%m-%d %H:%M:%S",
  "exclude" : [],
  "exclude-apps" : []
}
EOF

cat <<EOF >$(dirname $(rpm -q python3-dnf-plugins-core --filesbypkg | grep download.py | awk '{ print $2 }'))/timeshift.py
# dnf plugin
# creates snapshots via 'timeshift'.
# Copy this file to: /usr/lib/python${pythonver}/site-packages/dnf-plugins/
#

import sys
import subprocess

from dnfpluginsextras import _, logger
import dnf


class Timeshift(dnf.Plugin):
    name = 'timeshift'

    def __init__(self, base, cli):
        self.base = base
        self.description = " ".join(sys.argv)
        self._pre_snap_created = False

    def pre_transaction(self):
        if not self.base.transaction:
            return

        logger.debug(
            "timeshift: creating pre_snapshot"
        )

        tsrun = subprocess.run(["timeshift","--create",
		"--comments","pre_snapshot: "+self.description], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if tsrun.returncode != 0:
            logger.critical(
                "timeshift: " + _("creating pre_snapshot failed, %d"), tsrun.returncode
            )
            return

        self._pre_snap_created = True
        logger.debug(
            "timeshift: " + _("created pre_snapshot")
        )

    def transaction(self):
        if not self.base.transaction:
            return

        if not self._pre_snap_created:
            logger.debug(
                "timeshift: " + _("skipping post_snapshot because creation of pre_snapshot failed")
            )
            return

        logger.debug(
            "timeshift: creating post_snapshot"
        )

        tsrun = subprocess.run(["timeshift","--create",
		"--comments","post_snapshot: "+self.description], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if tsrun.returncode != 0:
            logger.critical(
                "timeshift: " + _("creating post_snapshot failed, %d"), tsrun.returncode
            )
            return

        logger.debug(
            "timeshift: created post_snapshot"
        )
EOF

umount /home
umount /var/tmp
umount /tmp

ENDCHROOT

# Setup regular user account
mount -odefaults,subvol=@home,noatime,compress=zstd /dev/mapper/sysroot /mnt/sysimage/home || DIE 2 Error mounting home partition

chroot /mnt/sysimage useradd -c "${USER_FULLNAME}" -G wheel $USERNAME
echo -n $USER_PASS | chroot /mnt/sysimage passwd --stdin $USERNAME

umount /mnt/sysimage/home

chroot /mnt/sysimage bash <<'ENDCHROOT'
mount -av

timeshift --create --comments "Big-Bang"

umount /home
umount /var/tmp
umount /tmp
umount /run/timeshift/backup
ENDCHROOT

# relabel for SELinux
touch /mnt/sysimage/.autorelabel

killall dbus-launch
sleep 30

umount /mnt/sysimage/{dev,run,sys,proc}
umount /mnt/sysimage
umount /mnt/sys
umount /mnt/source

cryptsetup luksClose sysroot

setenforce 1
