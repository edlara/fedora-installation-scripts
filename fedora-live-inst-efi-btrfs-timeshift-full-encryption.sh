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

DEV_UEFI=${TGT_DEV}${PART_PREFIX}1
DEV_RECOVERY=${TGT_DEV}${PART_PREFIX}2
DEV_ROOT=${TGT_DEV}${PART_PREFIX}3

(( $(id -u) == 0 )) || DIE 1 User must be root

# Ask for account and passwords
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
+512M
t
1
n
2

+10G
n
3


w
EOF
parted $TGT_DEV name 1 EFI-Boot name 2 Recovery name 3 System || DIE 2 parted error
mkfs.vfat -F 32 $DEV_UEFI || DIE 2 Error formating EFI partition
mkfs.ext4 -O ^has_journal -m 0 $DEV_RECOVERY || DIE 2 Error formating Recovery partition

echo -n $LUKS_PASS | cryptsetup -qv luksFormat $DEV_ROOT --pbkdf pbkdf2 --pbkdf-force-iterations 10000 --key-file -  || DIE 2 Error formating luks partition

echo -n $LUKS_PASS | cryptsetup luksOpen $DEV_ROOT sysroot --key-file -  || DIE 2 Error opening luks partition

mkfs.btrfs /dev/mapper/sysroot || DIE 2 Error formating btrfs partition
mkdir /mnt/sys || DIE 2 Error making /mnt/sys directory
mount -odefaults,subvolid=5,noatime,compress=zstd /dev/mapper/sysroot /mnt/sys  || DIE 2 Error mounting /mnt/sys directory
btrfs quota enable /mnt/sys
btrfs subvolume create /mnt/sys/@ || DIE 2 Error creating root volume
btrfs subvolume create /mnt/sys/@home || DIE 2 Error creating home volume

mkdir /mnt/sysimage || DIE 2 Error making /mnt/sysimage directory
mount -osubvol=@,defaults,noatime,compress=zstd /dev/mapper/sysroot /mnt/sysimage || DIE 2 Error mounting /mnt/sysimage directory

mkdir -p /mnt/sysimage/boot/efi || DIE 2 Error making /mnt/sysimage/boot/efi directory
mount $DEV_UEFI /mnt/sysimage/boot/efi || DIE 2 Error mounting EFI partition

mkdir /mnt/source || DIE 2 Error making /mnt/source directory
mount /dev/live-base /mnt/source || DIE 2 Error mounting /mnt/source directory

# Software Installation
rsync -pogAXtlHrDx --info=progress2 --exclude /dev/ --exclude /proc/ --exclude '/tmp/*' --exclude /sys/ --exclude /run/ --exclude '/boot/*rescue*' --exclude /boot/loader/ --exclude /boot/efi/loader/ --exclude /etc/machine-id /mnt/source/ /mnt/sysimage

EFI_UUID=$(blkid -s UUID -o value $DEV_UEFI)
RECOVERY_UUID=$(blkid -s UUID -o value $DEV_RECOVERY)
LUKS_UUID=$(blkid -s UUID -o value  $DEV_ROOT)
BTRFS_UUID=$(blkid -s UUID -o value  /dev/mapper/sysroot)

# Key for partition
cat <<EOF >/mnt/sysimage/etc/crypttab
sysroot UUID=$LUKS_UUID /etc/disk-keys/root.key luks,discard
EOF

# Recovery partition mount point
mkdir /mnt/sysimage/recovery

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
UUID=$BTRFS_UUID  /                       btrfs   defaults,subvol=@,noatime,compress=zstd,x-systemd.device-timeout=0     1 1
UUID=$EFI_UUID                               /boot/efi               vfat    umask=0077,shortname=winnt                                             0 2
UUID=$BTRFS_UUID  /home                   btrfs   defaults,subvol=@home,noatime,compress=zstd,x-systemd.device-timeout=0 1 2
UUID=$RECOVERY_UUID  /recovery               ext4    defaults,noatime,nodiratime,lazytime                                   0 2

tmpfs    /tmp        tmpfs   defaults   0  0
vartmp   /var/tmp    tmpfs   defaults   0  0

EOF

# Grub boot configuration
cat <<EOF >/mnt/sysimage/boot/efi/EFI/fedora/grub.cfg
insmod luks2
insmod regexp
insmod all_video
insmod ls
set timeout=5

search --no-floppy --fs-uuid --set=root $EFI_UUID
if [ x\$feature_default_font_path = xy ] ; then
   font=unicode
else
    font="/EFI/fedora/themes/unicode.pf2"
fi

set gfxmode=1024x768,auto
terminal_output gfxterm
insmod gfxmenu
insmod png
# set theme=(\$root)/EFI/fedora/themes/DarkFedora/theme.txt
# export theme

menuentry "Boot to main OS" {
  for crypttry in 1 2 3; do
    cryptomount -u ${LUKS_UUID//\-/}
    set cryptres=\$?
    if [ \$cryptres == 0 ]; then
      break
    fi
    if [ \$crypttry -lt 3 ]; then
      echo Error decrypting disk, try again...
    else
      echo Error decrypting disk, last attempt...
      sleep --verbose --interruptible 10
    fi
  done
  set root='cryptouuid/${LUKS_UUID//\-/}'

  if [ x\$feature_platform_search_hint = xy ]; then
    search --no-floppy --fs-uuid --set=dev --hint='cryptouuid/${LUKS_UUID//\-/}'  $BTRFS_UUID
  else
    search --no-floppy --fs-uuid --set=dev $BTRFS_UUID
  fi

  set prefix=(\$dev)/@/boot/grub2
  export \$prefix
  configfile \$prefix/grub.cfg
}

submenu "Recovery ->" {
  # workaround: remove tpm module to avoid grub2 OOM
  rmmod tpm
  search --no-floppy --fs-uuid --set=root $RECOVERY_UUID

  for isofile in /Fedora-*-Live-*.iso; do
    if [ -e "\$isofile" ]; then
      regexp --set=isoname "/(.*)" "\$isofile"
      submenu "\$isoname ->" "\$isofile" {
        iso_path="\$2"
        loopback loop "\$iso_path"
        probe --label --set=cd_label (loop)
        if [ -e (loop)/isolinux/vmlinuz ]; then
            set imgpath=isolinux
            set kernelfile=vmlinuz
            set kernelimg=initrd.img
        elif [ -e (loop)/images/pxeboot/vmlinuz ]; then
            set imgpath=images/pxeboot
            set kernelfile=vmlinuz
            set kernelimg=initrd.img
        elif [ -e (loop)/boot/x86_64/loader/linux ]; then
            set imgpath=boot/x86_64/loader
            set kernelfile=linux
            set kernelimg=initrd
        fi
        menuentry "Start Fedora Live" {
          bootoptions="iso-scan/filename=\$iso_path root=live:CDLABEL=\$cd_label rd.live.image quiet"
          linux (loop)/\$imgpath/\$kernelfile \$bootoptions
          initrd (loop)/\$imgpath/\$kernelimg
        }
        menuentry "Start Fedora Live in basic graphics mode" {
          bootoptions="iso-scan/filename=\$iso_path root=live:CDLABEL=\$cd_label rd.live.image nomodeset quiet"
          linux (loop)/\$imgpath/\$kernelfile \$bootoptions
          initrd (loop)/\$imgpath/\$kernelimg
        }
        menuentry "Test this media & start Fedora Live" {
          bootoptions="iso-scan/filename=\$iso_path root=live:CDLABEL=\$cd_label rd.live.image rd.live.check quiet"
          linux (loop)/\$imgpath/\$kernelfile \$bootoptions
          initrd (loop)/\$imgpath/\$kernelimg
        }
        if [ -e (loop)/\$imgpath/memtest ]; then
          menuentry "Run a memory test" {
            bootoptions=""
            linux16 (loop)/\$imgpath/memtest \$bootoptions
          }
        fi
      }
    fi
  done
}

if [ "\$grub_platform" = "efi" ]; then
  menuentry 'UEFI Firmware Settings' \$menuentry_id_option 'uefi-firmware' {
    fwsetup
  }
fi

EOF

# backup efi grub.cfg
cp /mnt/sysimage/boot/efi/EFI/fedora/grub.cfg /mnt/sysimage/boot/efi/EFI/fedora/grub.cfg-fedora-installation
cp /mnt/sysimage/boot/efi/EFI/fedora/grub.cfg-fedora-installation /mnt/sysimage/root/

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

# to configure a theme uncomment the following
# and regenerate /boot/grub2/grub.cfg
# delete GRUB_TERMINAL_OUTPUT from above
# GRUB_GFXMODE="1024x768,auto"
# GRUB_TERMINAL_OUTPUT="gfxterm"
# GRUB_GFXPAYLOAD_LINUX=keep
# GRUB_THEME="/boot/efi/EFI/fedora/themes/DarkFedora/theme.txt"

EOF

# Install the luks key in the initram image
cat <<EOF >/mnt/sysimage/etc/dracut.conf.d/add-keys.conf
install_items+=" /etc/disk-keys/root.key "
EOF

cat <<EOF >/mnt/sysimage/etc/sysconfig/kernel
# UPDATEDEFAULT specifies if new-kernel-pkg should make
# new kernels the default
UPDATEDEFAULT=yes

# DEFAULTKERNEL specifies the default kernel package type
DEFAULTKERNEL=kernel-core

EOF

# create key for luks device
mkdir -m0700 /mnt/sysimage/etc/disk-keys || DIE 2 Error making keys directory
( umask 0077 && dd if=/dev/urandom bs=1 count=64 of=/mnt/sysimage/etc/disk-keys/root.key conv=excl,fsync )
echo -n $LUKS_PASS | cryptsetup luksAddKey $DEV_ROOT /mnt/sysimage/etc/disk-keys/root.key --key-file -

# preparing for chroot
mkdir -p /mnt/sysimage/{dev,run,sys,proc} || DIE 2 Error making system directories
mount -v -o bind /dev /mnt/sysimage/dev/ || DIE 2 Error mounting dev
mount -v -o bind /run /mnt/sysimage/run/ || DIE 2 Error mounting run
mount -v -t proc proc /mnt/sysimage/proc/ || DIE 2 Error mounting proc
mount -v -t sysfs sys /mnt/sysimage/sys/ || DIE 2 Error mounting sys

# set root password (variables are not passed to chroot)
echo -n $ROOT_PASS | chroot /mnt/sysimage passwd --stdin root

# EFI partition needs to be mounted again from within chroot for installation to work
umount /mnt/sysimage/boot/efi || DIE 2 Error umounting EFI partition

# Passing environment to chroot
cat <<EOF >/mnt/sysimage/inst_env
TGT_DEV=$TGT_DEV
LUKS_UUID=$LUKS_UUID
BTRFS_UUID=$BTRFS_UUID

export TGT_DEV LUKS_UUID BTRFS_UUID
EOF

# setup machine-id, grub, EFI boot
# reinstalling kernel so grub BLS entries and rescue image are created
# fix BLS options as they use the current kernel parameters from the live image
# install and configure timeshift
chroot /mnt/sysimage bash <<'ENDCHROOT'
source /inst_env

mount -t efivarfs efivarfs /sys/firmware/efi/efivars/
mount -av

systemd-machine-id-setup

efibootmgr -c -d $TGT_DEV -p 1 -L Fedora -l '\EFI\fedora\shimx64.efi'

grub2-mkconfig -o /boot/grub2/grub.cfg
grub2-editenv /boot/grub2/grubenv set blsdir=/@/boot/loader/entries

kernel-install add $(uname -r) /lib/modules/$(uname -r)/vmlinuz

sed -i "s,^options root=.*,options root=UUID=$BTRFS_UUID ro rootflags=subvol=@ rd.luks.uuid=luks-$LUKS_UUID rhgb quiet \${extra_cmdline},g" /boot/loader/entries/*.conf

dnf install -y grub2-efi-x64-modules
rsync -avz /usr/lib/grub/x86_64-efi /boot/efi/EFI/fedora/

dnf install -y timeshift libdnf5-plugin-actions

dnf install -y http://asgard2.fios-router.home/repository/f41/x86_64/RPMS/asgard2-repo-1.0-1.ell.noarch.rpm
dnf install -y libdnf5-plugin-actions-timeshift
dnf install -y libdnf5-plugin-actions-timeshift

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
  "count_monthly" : "2",
  "count_weekly" : "3",
  "count_daily" : "5",
  "count_hourly" : "6",
  "count_boot" : "5",
  "snapshot_size" : "0",
  "snapshot_count" : "0",
  "date_format" : "%Y-%m-%d %H:%M:%S",
  "exclude" : [],
  "exclude-apps" : []
}
EOF

rm -f /inst_env

umount /recovery
umount /home
umount /boot/efi
umount /var/tmp
umount /tmp
umount /sys/firmware/efi/efivars

ENDCHROOT

# Setup regular user account
mount $DEV_UEFI /mnt/sysimage/boot/efi || DIE 2 Error mounting EFI partition
mount -odefaults,subvol=@home,noatime,compress=zstd /dev/mapper/sysroot /mnt/sysimage/home || DIE 2 Error mounting home partition

chroot /mnt/sysimage useradd -c "${USER_FULLNAME}" -G wheel $USERNAME
echo -n $USER_PASS | chroot /mnt/sysimage passwd --stdin $USERNAME

umount /mnt/sysimage/boot/efi
umount /mnt/sysimage/home

chroot /mnt/sysimage bash <<'ENDCHROOT'
mount -t efivarfs efivarfs /sys/firmware/efi/efivars/
mount -av
sync
sleep 5

timeshift --create --comments "Big-Bang"

umount /recovery
umount /home
umount /boot/efi
umount /var/tmp
umount /sys/firmware/efi/efivars
ENDCHROOT

# relabel for SELinux
touch /mnt/sysimage/.autorelabel

killall dbus-launch
sleep 30

umount /mnt/sysimage/{dev,run,sys,proc,tmp}
umount /mnt/sysimage
umount /mnt/sys
umount /mnt/source

cryptsetup luksClose sysroot

setenforce 1
