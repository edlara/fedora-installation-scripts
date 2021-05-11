#!/bin/bash

if [ -e /sys/firmware/efi/efivars ]; then
	bash fedora-live-inst-efi-btrfs-timeshift-full-encryption.sh "$@"
else
	bash fedora-live-inst-bios-btrfs-timeshift-full-encryption.sh "$@"
fi
