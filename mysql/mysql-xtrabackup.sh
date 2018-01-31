#!/bin/bash
#
# True MySQL backup script for Xtrabackup implementations
#
# Author   : Rene Bakkum & Patrick Lina
# Version  : 2.0.0
# Copyright: True B.V.
#            In case you would like to make changes, let Rene know!
#
# Changelog:
# 1.00 Initial release
# 1.01 Added external config
# 2.0.0 Major rewrite
#set -x

SELF="$(basename $0)"

LOCK="/backup/xtrabackup-running.lock"
LOG="/backup/xtrabackup-running.log"
MAILTO=""
MAILFROM="$(hostname)@$(hostname -d)"
BACKUPPATH="/backup/xtrabackup"
# Retention periods (in minutes)
KEEP_CLEANUP="pre"
KEEP_UNCOMPRESSED="180"
KEEP_COMPRESSED="2880"

CFG="${0/.sh/.cfg}"

if [ ! -e "$CFG" ]; then
  cat << EOF > "$CFG"
LOCK="$LOCK"
LOG="$LOG"
MAILTO="$MAILTO"
MAILFROM="$MAILFROM"
BACKUPPATH="$BACKUPPATH"
# Retention periods (in minutes)
KEEP_CLEANUP="$KEEP_CLEANUP"
KEEP_UNCOMPRESSED="$KEEP_UNCOMPRESSED"
KEEP_COMPRESSED="$KEEP_COMPRESSED"
EOF
else
  source "$CFG"
fi

## Capture all output
exec 5>&1 6>&2 1>"$LOG" 2>&1

## Send email and exit
## Usage: mail_and_exit [<exitcode> ["<subject>" ["<contentfile>"]]]
function mail_and_exit {
  exitcode="${1:-0}"
  subject="${2:-$SELF}"
  content="${4:-$LOG}"

  ## Check if sender and recipient are configured
  if [ -n "$MAILFROM" -a -n "$MAILTO" ]; then
    ## Send email with content
    /usr/bin/mailx -r "$MAILFROM" -s "$subject" "$MAILTO" < "$content"
  else
    ## Undo logging and show content
    exec 1>&5 2>&6
    echo "***" >&2
    echo "*** $subject" >&2
    echo "***" >&2
    cat "$content" >&2
  fi

  ## Exit program
  exit "$exitcode"
}

# Remove the lock file so new backup will start
function clean_exit {
  rm "$LOCK"
}

function cleanup {
  # Remove uncompressed backups older than xx minutes...
  find "$BACKUPPATH" -maxdepth 1 ! -path "$BACKUPPATH" -type d -mmin +$KEEP_UNCOMPRESSED -exec rm -Rf {} \;

  # Remove compressed backups older than xx minutes...
  find "$BACKUPPATH" -type f -name "*.tgz" -mmin +$KEEP_COMPRESSED -delete
}

###
### Main program
###
if [ -e "$LOCK" ]; then
  # Report that the backup is still running, instead of starting multiple backups
  mail_and_exit 1 "[MySQL] Backup is still running" "$LOCK"

else

  ## Set lock file and clean it up on exit
  echo "Backup is still running, starting date: $(date)" > "$LOCK"
  trap clean_exit exit

  ## Pre cleanup
  [ "$KEEP_CLEANUP" == "pre" ] && cleanup

  # Let's make the backup!
  time innobackupex --default-extra-file=/etc/mysql/debian.cnf "$BACKUPPATH"
  [ $? -ne 0 ] && mail_and_exit 1 "[FAIL] Xtrabackup step failed."

  # Apply the logs.
  latestdir="$(ls -t "$BACKUPPATH" | head -1)"
  time innobackupex --apply-log --use-memory=4G "${BACKUPPATH}/${latestdir}"
  [ $? -ne 0 ] && mail_and_exit 1 "[FAIL] Xtrabackup APPLY step failed."

  # Since we want multicore compression, we are going to make 1 big tar file before pigz kicks in..
  time tar -cf - "${BACKUPPATH}/${latestdir}" | pigz --fast >"${BACKUPPATH}/${latestdir}.tgz"
  [[ "${PIPESTATUS[*]}" =~ [^0\ ] ]] && mail_and_exit 1 "[FAIL] Compression step failed."

  ## Post cleanup
  [ "$KEEP_CLEANUP" != "pre" ] && cleanup
fi
