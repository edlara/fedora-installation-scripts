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
