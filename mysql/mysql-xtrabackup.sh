#!/bin/bash
#
# True MySQL backup script for Xtrabackup implementations
#
# Author   : Rene Bakkum
# Version  : 1.00
# Copyright: True B.V.
#            In case you would like to make changes, let me know!
#
# Changelog:
# 1.00 Initial release

PID="/backup/xtraback-running.lock"
MAILTO="root"
MAILFROM="$(hostname)@$(hostname -d)"
BACKUPPATH="/backup/xtrabackup"
SUBJECT="[MySQL] Backup is still running"

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
    MAILTO="sla@true.nl"
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
    MAILTO="sla@true.nl"
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
    MAILTO="sla@true.nl"
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
    MAILTO="sla@true.nl"
    /usr/bin/mailx -r $MAILFROM -s "[$STATUS] $SUBJECT" $MAILTO < /dev/null
  fi

  ####
  # Remove uncompressed backups older than 3 hours...
  ####
  find "$BACKUPPATH" -maxdepth 1 ! -path "$BACKUPPATH" -type d -mmin +180 -exec rm -Rf {} \;

  ####
  # Remove compressed backups older than 2 hours...
  ####
  find "$BACKUPPATH" -type f -mmin +2880 -delete

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
