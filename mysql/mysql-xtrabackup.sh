#!/bin/bash
#
# True MySQL backup script for Xtrabackup implementations
#
# Author   : Rene Bakkum
# Version  : 1.01
# Copyright: True B.V.
#            In case you would like to make changes, let me know!
#
# Changelog:
# 1.00 Initial release
# 1.01 Added external config

PID="/backup/xtraback-running.lock"
MAILTO="root"
MAILFROM="$(hostname)@$(hostname -d)"
BACKUPPATH="/backup/xtrabackup"
SUBJECT="[MySQL] Backup is still running"
# Retention periods (in minutes)
KEEP_UNCOMPRESSED="180"
KEEP_COMPRESSED="2880"

CFG="${0/.sh/.cfg}"

if [ ! -e "$CFG" ]; then
  cat << EOF > "$CFG"
MAILTO="$MAILTO"
BACKUPPATH="$BACKUPPATH"
SUBJECT="$SUBJECT"
# Retention periods (in minutes)
KEEP_UNCOMPRESSED="$KEEP_UNCOMPRESSED"
KEEP_COMPRESSED="$KEEP_COMPRESSED"
EOF
else
  source "$CFG"
fi

if [ ! -e "$PID" ]; then
  echo "Backup is still running, starting date: $(date)" > "$PID"
  ####
  # Let's make the backup!
  ####
  time innobackupex --default-extra-file=/etc/mysql/debian.cnf $BACKUPPATH

  s=$?
  if [ $s -ne 0 ]; then
    STATUS="FAIL";
    SUBJECT="Xtrabackup step failed."
    /usr/bin/mailx -r $MAILFROM -s "[$STATUS] $SUBJECT" $MAILTO < /dev/null
  fi

  latestdir="$(ls -t $BACKUPPATH | head -1)"
  ####
  # Apply the logs.
  ####
  time innobackupex --apply-log --use-memory=4G $BACKUPPATH/$latestdir

  s=$?
  if [ $s -ne 0 ]; then
    STATUS="FAIL";
    SUBJECT="Xtrabackup APPLY step failed."
    /usr/bin/mailx -r $MAILFROM -s "[$STATUS] $SUBJECT" $MAILTO < /dev/null
  fi

  ####
  # Since we want multicore compression, we are going to make 1 big tar file before pigz kicks in..
  ####
  time tar -cf $BACKUPPATH/$latestdir.tar $BACKUPPATH/$latestdir

  s=$?
  if [ $s -ne 0 ]; then
    STATUS="FAIL";
    SUBJECT="Tar step failed."
    /usr/bin/mailx -r $MAILFROM -s "[$STATUS] $SUBJECT" $MAILTO < /dev/null
  fi

  ####
  # Let's compress it... you need pigz installed (apt install pigz)
  ####
  time pigz --fast $BACKUPPATH/$latestdir.tar

  s=$?
  if [ $s -ne 0 ]; then
    STATUS="FAIL";
    SUBJECT="Pigz step failed."
    /usr/bin/mailx -r $MAILFROM -s "[$STATUS] $SUBJECT" $MAILTO < /dev/null
  fi

  ####
  # Remove uncompressed backups older than xx minutes...
  ####
  find "$BACKUPPATH" -maxdepth 1 ! -path "$BACKUPPATH" -type d -mmin +$KEEP_UNCOMPRESSED -exec rm -Rf {} \;

  ####
  # Remove compressed backups older than xx minutes...
  ####
  find "$BACKUPPATH" -type f -mmin +$KEEP_COMPRESSED -delete

  ####
  # Remove the lock file so new backup will start
  ####
  rm $PID

else
  ####
  # Report that the backup is still running, instead of starting multiple backups
  ####
  /usr/bin/mailx -r $MAILFROM -s "$SUBJECT" $MAILTO < $PID
fi
