These scripts install Fedora from a live image with timeshift support. The boot directory is part of root so it is included in the timeshift snapshots making it easier to rollback changes. It also includes a recovery partition where Fedora live image isos can be just dropped and used from the grub menu at start up.

# WARNING
There are a lot of issues with these scripts so the scripts, starting that they refer to a non public repository. Also upgrades of grub can lead to breaking the boot process. The situation is recoverable though, but requires some manual intervention (most of the time using the grub command line is sufficient, but sometimes a live usb is required)
