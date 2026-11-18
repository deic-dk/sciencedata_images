#!/bin/bash
# /etc/my_init.post_shutdown.d: after Overleaf's services have stopped (their
# pre-shutdown scripts flushed open documents to MongoDB, which is still
# running - it is not a runit service). Set terminationGracePeriodSeconds in the
# pod's manifest so the upload has time.
/usr/local/sbin/overleaf_backup.sh
exit 0
