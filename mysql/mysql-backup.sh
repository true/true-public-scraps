#!/bin/bash
#
# True MySQL backup script for Bacula backup implementations
#
# Author   : L. Lakkas
# Version  : 3.21
# Copyright: L. Lakkas @ TrueServer.nl B.V.
#            In case you would like to make changes, let me know!
#
# Changelog:
# 1.00 Initial release
# 2.00 Huge revision. Catch pipe errors and create the option to
#      skip databases and tables.
# 2.10 Created command line debugging and make it compatible for
#      other implementations too.
# 2.11 Removed error counter and replaced it with the error array
# 2.12 Added a separate configuration file for maintainability
# 2.13 Skip databases no longer removed from array, but printed
#      and skipped upon discovery.
# 2.14 Created a primary and secondary configuration file for
#      override purposes.
# 2.15 Rewritten error handler to catch and fancyprint more errors
# 2.16 Created exception in case the configuration file and custom
#      configuration file are the same.
# 2.17 Created backticks around the $DB variable to secure it for
#      dashes in database names.
# 3.00 It seems some crazy people use spaces in there table names,
#      lets escape them too. Placed the ignore-table's in a array
#      so they are correctly passed to mysqldump. Did the same for
#      databases. Made some minor bug fixes and also printed table
#      type on debug. Also made the location of the binaries mysql
#      and mysqldump configurable, introduced the DRY_RUN option,
#      to see what will be done and fixed a issue where there is a
#      database created with no tables. Added support for the new
#      mysql.events table and moved the triggers from the table to
#      the structure dump, to match the stored procedures etc.
# 3.10 Added parameter so the user can also specify the host of
#      the MySQL database for remote backups. Also added a check
#      that verifies if the user can export all databases. Present
#      a warning if not. Exit code remains 0.
# 3.20 Allow ALL privileges too while verifying the rights of the
#      user. Also allow whitespace before configurable parameters
#      and check the configuration file rights before loading.
# 3.21 Minor bugfix on the validation of the MySQL and MySQL dump
#      variables.
#
# Configurable variables:
# DB_HOST        The MySQL hostname of the server you would like
#                to backup. Should be a FQDN, localhost or empty
#                Sample: DB_HOST=db01.example.com
# DB_USER        The MySQL login user
#                Sample: DB_USER=root
# DB_PASS        The MySQL password for the specified user
#                Sample: DB_PASS=letmein
# SKIP_DATABASES Array of databases to skip
#                Sample: SKIP_DATABASES=(information_schema)
# SKIP_TABLES    Array of tables to skip, prefixed with database
#                Sample: SKIP_TABLES=(mysql.host)
# LOCAL_BKP_DIR  The directory to put the backup in. It is not
#                advised to use the /tmp or /var/tmp directory
#                for security reasons.
#                Sample: LOCAL_BKP_DIR=/backup/mysql
# DEBUG          Boolean to enable or disable debug output
#                Sample: DEBUG=0		(Default)
# DRY_RUN        Run the backup, but don't export anything. This
#                is for testing purposes and implicidly enables
#                the debug option too. This should NOT be used
#                for real backups!
# DISK_MIN_FREE  The minimum amount of diskspace in Gigabytes
#                Sample: DISK_MIN_FREE=3	(Default)
# BIN_MYSQL      Specify the location and name of the `mysql`
#                binary file
# BIN_MYSQLDUMP  Specify the location and name of the `mysqldump`
#                binary file
#
# Note: If you want to put any of these files in a configuration
#       file, make sure you prefix them with CONFIG_.
#       Sample: CONFIG_DEBUG=1
#
#       It is also possible to use command line variable input in
#       the form of:
#       DB_USER=root DB_PASS=letmein ./mysql-backup.sh
#       The config file wil override a variable, if present!
#
# $Id$

# You might or might not want to alter this location. The script
# will look for this file. If it does not exists, then it will
# use default values or use variables passed in the environment.
# This configuration file will NOT be used if there is a config
# file in the same directory as this script.
CONFIG_FILE="/etc/true/mysql-backup/mysql-backup.conf"


################################################################
#   Start actual script. Changes below must be communicated!   #
################################################################

# Catch pipe errors that occur in mysqldump when piping through
# gzip.
set -o pipefail

# Prepare error and warning array
ERROR_REASONS=()
WARNING_REASONS=()

function printWarning {
      echo
      echo "###################################################################"
      echo "#                       WARNINGS DETECTED                         #"
      echo "###################################################################"

      for WARNINGS in "${WARNING_REASONS[@]}"
      do
         ((count++))
         echo -e "$count) ${WARNINGS}"
      done
}

function printError {
   if [ ${#ERROR_REASONS[@]} -ne 0 ]; then
      count=0

      echo
      echo "###################################################################"
      echo "#                        ERRORS DETECTED                          #"
      echo "###################################################################"

      echo -e "\nScript found ${#ERROR_REASONS[@]} errors:\n"

      for ERRORS in "${ERROR_REASONS[@]}"
      do
         ((count++))
         echo -e "$count) ${ERRORS}"
      done

      echo -e "\nExiting with errors..."
      exit 1
   else
      if [ ${#WARNING_REASONS[@]} -ne 0 ]; then
         printWarning
         echo -e "\nExiting with warnings..."
      fi
      exit 0
   fi
}

# Only root is allowed to run the script
if [ ! "$(id -u -n)" = root ]; then
   ERROR_REASONS+=("Only user 'root' can run this script!")
   printError
fi

# Find and read our configuration file. The pre-set configuration
# file location can be overridden by placing a configuration file
# in the same directory as this script.

# Get our current working directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOCAL_CONFIG="${DIR}/mysql-backup.conf"
unset DIR

# Check if the configuration file exists and has a size greater
# then zero. If this is the case, strip out the vars and read it
if [[ -s $LOCAL_CONFIG ]] && [[ $LOCAL_CONFIG != $CONFIG_FILE ]]; then
   # Local configuration found
   CONFIG_TYPE=1
   FILENAME=$LOCAL_CONFIG
else
   if [[ -s $CONFIG_FILE ]];then
      FILENAME=$CONFIG_FILE
      CONFIG_TYPE=2
   else
      echo "No configuration file found..."
      CONFIG_TYPE=3
   fi
fi
if [[ $CONFIG_TYPE == 1 ]] || [[ $CONFIG_TYPE == 2 ]]; then
   STATS=$(stat -c %A "${FILENAME}")

   if [[ ! $STATS == "-rw-------" ]]; then
      PERMISSION_TXT=""
      if [[ $STATS == "-rw-r--r--" ]]; then
         PERMISSION_TXT+="Please remove the READ rights from the 'group' and 'others' of the configuration file"
      else
         PERMISSION_TXT+="The permissions are incorrect on the configuration file!"
      fi
      PERMISSION_TXT+="\n     Use 'chmod 600 ${FILENAME}'"
      WARNING_REASONS+=("${PERMISSION_TXT}")
      unset PERMISSION_TXT
   fi
   unset STATS

   source <( sed -n 's/^\s*CONFIG_*//p' $FILENAME )
   unset FILENAME
fi

# Check if multiple commandline parameters are given
if [[ "$#" -gt 1 ]];then
   ERROR_REASONS+=("Multiple commandline parameters given, only one allowed...")
   printError
fi

# Check if we are in DRY RUN mode, and force DEBUG then
[ "$#" -eq 1 ] && [[ "$1" == --dry-run ]] && DRY_RUN=1

if [[ $DRY_RUN -gt 0 ]];then
   echo "Running in DRY_RUN mode, no real backup is started..."
   DEBUG=1
fi

# Override DEBUG parameter from command line
[ "$#" -eq 1 ] && [[ "$1" == --debug ]] && DEBUG=1
# Print debug status
if [[ $DEBUG -eq 1 ]];then
   if [[ $DRY_RUN -gt 0 ]];then
      echo "Forcing debug mode..."
   else
      echo "Debug enabled..."
   fi
   case $CONFIG_TYPE in
      1) echo "Using custom configuration in script-directory ($LOCAL_CONFIG)..." ;;
      2) echo "Using default configuration file..." ;;
      3) echo "Config file '$CONFIG_FILE' or '$LOCAL_CONFIG' was not found..." ;;
   esac
fi
unset LOCAL_CONFIG
unset CONFIG_TYPE

if [[ -z $BIN_MYSQL ]];then
   # No config set, lets try to find the binaries ourselves
   BIN_MYSQL=`which mysql`
   # Verify if the found binary is okey
   if [[ -x $BIN_MYSQL && -f $BIN_MYSQL ]];then
      [[ $DEBUG -eq 1 ]] && echo -e "Manually found 'mysql' in '$BIN_MYSQL'..."
   else
      ERROR_REASONS+=("The binary 'mysql' is invalid or has not been found!")
      printError
   fi
else
   # A binary location is given, lets check if the file exists
   if [[ -x $BIN_MYSQL && -f $BIN_MYSQL ]];then
      [[ $DEBUG -eq 1 ]] && echo -e "Using configured binary 'mysql' in '$BIN_MYSQL'..."
   else
      ERROR_REASONS+=("The binary 'mysql' has not been found!")
      printError
   fi
fi
if [[ -z $BIN_MYSQLDUMP ]];then
   # No config set, lets try to find the binaries ourselves
   BIN_MYSQLDUMP=`which mysqldump`
   # Verify if the found binary is okey
   if [[ -x $BIN_MYSQLDUMP && -f $BIN_MYSQLDUMP ]];then
      [[ $DEBUG -eq 1 ]] && echo -e "Manually found 'mysqldump' in '$BIN_MYSQLDUMP'..."
   else
      ERROR_REASONS+=("The binary 'mysqldump' is invalid or has not been found!")
      printError
   fi
else
   # A binary location is given, lets check if the file exists
   if [[ -x $BIN_MYSQLDUMP && -f $BIN_MYSQLDUMP ]];then
      [[ $DEBUG -eq 1 ]] && echo -e "Using configured binary 'mysqldump' in '$BIN_MYSQLDUMP'..."
   else
     ERROR_REASONS+=("The binary 'mysqldump' has not been found!")
     printError
  fi
fi

# If no minimum free diskspace is given, default to 1 Gb
DISK_MIN_FREE=${DISK_MIN_FREE:-1}
[[ $DEBUG -eq 1 ]] && echo -e "Minimum free diskspace is set to $DISK_MIN_FREE Gb..."

# Get terminal width
[[ $DEBUG -eq 1 ]] && echo "Terminal type is set to '$TERM'..."

# Fix pseudo terminals with fixed width
if [ $TERM == dumb ];then
   width=60
else
   # Get the terminal width and remove the width of the
   # biggest word ( [ SKIPPED ])
   ((width=$(tput cols)-12))
fi

# Fancy messages
function printDebugStatus {
   # Find the size of the ENGINE string

  if [[ -z $3 ]]; then
     printf "%-${width}s [ $1 ]\n" "$2"
  else
    engineSize=$((${#3}+3))
     ((customWidth=$width-$engineSize))
     printf "%-${customWidth}s ($3) [ $1 ]\n" "$2"
  fi

}

# Allow command line variable imput in the form of:
# DB_USER=root DB_PASS=letmein ./mysql-backup.sh
[ ! -n $DB_USER ] && DB_USER=""
[ ! -n $DB_PASS ] && DB_PASS=""

# Check if the user is trying to login without a password. Note
# that this will break the non-interactive shell!
if [[ -n $DB_USER ]] && [[ -z $DB_PASS ]];then
   [[ $DEBUG -eq 1 ]] && echo "The user '$DB_USER' has no password set in the configuration"
   ERROR_REASONS+=("Password is not set! Not continuing as having no password for MySQL is a security risk!")
   printError
fi

# Check if the user is a idiot
if [[ ! -z $DB_USER ]] && [[ $DB_USER == $DB_PASS ]];then
   ERROR_REASONS+=("MySQL Username and Password are identical. This is a security risk!")
   printError
fi

# Validate the backup directory
VALIDATEDIR=$(dirname ${LOCAL_BKP_DIR} 2>/dev/null)
if [[ $? -eq 0 ]];then
   if [ $VALIDATEDIR == "." ] || [ $VALIDATEDIR == "/" ];then
      [[ $DEBUG -eq 1 ]] && [ $VALIDATEDIR == "/" ] && [ ! $LOCAL_BKP_DIR == "/" ] && echo "User trying to put the backup in a directory of /"
      [[ $DEBUG -eq 1 ]] && [ $VALIDATEDIR == "/" ] && [ $LOCAL_BKP_DIR == "/" ] && echo "User trying to put the backup in the server root!"
      [[ $DEBUG -eq 1 ]] && [ $VALIDATEDIR == "." ] && echo "Directory '$LOCAL_BKP_DIR' is invalid!"
      ERROR_REASONS+=("Please specify at least one sub-directory to place the backup in!\n\tExample: /backup/mysql")
      printError
   fi
else
   [[ $DEBUG -eq 1 ]] && echo "Dump directory is not set!"
   ERROR_REASONS+=("The MySQL dump directory is not valid")
   printError
fi

# Check if there is at least $DISK_MIN_FREE free space on the
# server/partition. We calculate in Gb as MySQL dumps can grow
# large. Besides, having at least 1 Gb sounds like a pre!
if [[ $(($(stat -f --format="%a*%S" .)/1024/1024/1024)) -lt $DISK_MIN_FREE ]];then
   [[ $DEBUG -eq 1 ]] && echo "At least $DISK_MIN_FREE Gb is needed. Currently there is only $(($(stat -f --format="%a*%S" .)/1024/1024/1024)) Gb free!"
   ERROR_REASONS+=("Insufficient disk space available...")
   printError
fi

# Discover MySQL login type / method
if [ ${#DB_USER} -gt 0 ]; then
   LOGIN_OPTS="-u$DB_USER -p$DB_PASS"
else
   # Check if we have a Debian login method
   if [ -f "/etc/mysql/debian.cnf" ]; then
      LOGIN_OPTS="--defaults-extra-file=/etc/mysql/debian.cnf"
   else
      # Check if we have a DirectAdmin login method
      if [ -f "/usr/local/directadmin/conf/my.cnf" ];then
         LOGIN_OPTS="--defaults-extra-file=/usr/local/directadmin/conf/my.cnf"
      else
         ERROR_REASONS+=("No MySQL login method found and no credentials given, aborting...")
         printError
      fi
   fi
fi

# Check if we need to backup remotely
if [[ ! -z $DB_HOST ]] && [[ $DB_HOST != "localhost" ]];then
   [[ $DEBUG -eq 1 ]] && echo "Using remote database '$DB_HOST' to gather backup..."
   LOGIN_OPTS+=" --host ${DB_HOST}"
fi

DB_LIST=$((echo "show databases;"|$BIN_MYSQL $LOGIN_OPTS -N) 2>&1)

# Check if we made correctly a connection
if [[ $? -gt 0 ]];then
   [[ $DEBUG -eq 1 ]] && echo -e "Wrong credentials of MySQL...\nTried to use credentials: $LOGIN_OPTS"
   ERROR_REASONS+=("${DB_LIST}")
   printError
   exit 1
fi

# Check if we have enough MySQL rights to export everything
[[ $DEBUG -eq 1 ]] && echo -e "Validating rights..."
RIGHTS=$(($BIN_MYSQL $LOGIN_OPTS --skip-column-names -Be "show grants for current_user;" | grep -o -P '(?<=GRANT ).*(?= ON)') 2>&1)

MISSING_RIGHTS="Missing grant (rights)"
if [[ -z $DB_USER ]]; then
   MISSING_RIGHTS+="!"
else
   MISSING_RIGHTS+=" for user '$DB_USER'!"
fi

if [[ ! "$RIGHTS" =~ "ALL PRIVILEGES" ]]; then
   if [[ ! "$RIGHTS" =~ "SELECT" ]]; then
      MISSING_RIGHTS+="\n     SELECT      - Probably NOT exporting all databases and tables!"
      MISSING=1
   fi

   if [[ ! "$RIGHTS" =~ "LOCK TABLES" ]]; then
      [[ $DEBUG -eq 1 ]] && MISSING_RIGHTS+="\n     LOCK TABLES - Probably problems with exporting some tables!"
      MISSING=1
   fi

   if [[ ! "$RIGHTS" =~ "EVENT" ]]; then
      [[ $DEBUG -eq 1 ]] && MISSING_RIGHTS+="\n     EVENT       - Probably problems with exporting some MySQL tables!"
      MISSING=1
   fi

   [[ ! -z $MISSING ]] && WARNING_REASONS+=("${MISSING_RIGHTS}");

   unset MISSING
fi
unset RIGHTS
unset MISSING_RIGHTS

# Just output the skipped databases and tables
if [[ $DEBUG -eq 1 ]];then
   if [ ${#SKIP_DATABASES[@]} -gt 0 ];then
      echo -e "\nSkipping databases:"
      for i in "${SKIP_DATABASES[@]}"
      do
         echo "  $i"
      done
   fi
fi
if [[ $DEBUG -eq 1 ]]; then
   if [ ${#SKIP_TABLES[@]} -gt 0 ];then
      echo -e "\nSkipping tables:"
      for i in "${SKIP_TABLES[@]}"
      do
         echo "  $i"
         done
      fi
fi

[[ $DEBUG -eq 1 ]] && echo -e "\nStarting backup...\n"

# Now create the backups
while read -r DB; do
   SKIP=0;
   for i in "${SKIP_DATABASES[@]}"
   do
      if [[ $i == $DB ]];then
         [[ $DEBUG -eq 1 ]] && printDebugStatus "SKIPPED" "$DB"
         SKIP=1;
      fi
   done
   if [[ $SKIP -eq 0 ]]; then
      # Go ahead!

      DB_BKP_DIR=$LOCAL_BKP_DIR/$DB

      # Verify if we can make the directory
      if [[ ! -d $DB_BKP_DIR ]]; then
         if [[ $DRY_RUN -eq 0 ]];then
            OUTPUT=$((mkdir -p "$DB_BKP_DIR") 2>&1)
            if [[ $? -eq 1 ]]; then
               [[ $DEBUG -eq 1 ]] && echo "Can not make directory '$DB_BKP_DIR'..."
               ERROR_REASONS+=("${OUTPUT}")
            fi
         fi
      fi

      # Create the skip string for the structure dump
      SKIPSTRING=()
      for i in "${SKIP_TABLES[@]}"
      do
         # Check if we have a database that is identical to a skipped one.
         if [[ ${i%%.*} == $DB ]];then
            # Check if the table is identical to the one to be skipped
            SKIPSTRING+=("--ignore-table=$i")
         fi
      done

      # Get the tables and its type. Store it in an array.
      # Using backticks around $DB for users who have dashes in there database / table names.

      table_status="show table status from \`${DB}\`"
      table_types=$(($BIN_MYSQL $LOGIN_OPTS --skip-column-names -Be "${table_status}" | awk -F "\t" '{print $1, $2}') 2>&1)

      if [[ $? -eq 1 ]]; then
         ERROR_REASONS+=("${table_types}")
      fi

      # Check if the database is empty
      if [[ -z $table_types ]];then
         [[ $DEBUG -eq 1 ]] && printDebugStatus "EMPTY" "$DB"
      else
         # Get the schema of database with the stored procedures.
         # This will be the first file in the database backup folder
         if [[ $DRY_RUN -eq 0 ]];then
            OUTPUT=$(($BIN_MYSQLDUMP $LOGIN_OPTS --routines --no-data --triggers --single-transaction "${SKIPSTRING[@]}" "${DB}" | gzip -c > "$DB_BKP_DIR/000-DB_SCHEMA.sql.gz") 2>&1)

            if [ $? -ne 0 ]; then
               [[ $DEBUG -eq 1 ]] && printDebugStatus "FAILED" "$DB"
               ERROR_REASONS+=("${OUTPUT}")
            else
               [[ $DEBUG -eq 1 ]] && printDebugStatus "OK" "$DB"
            fi
         else
            printDebugStatus "DRY_RUN" "$DB"
         fi
      fi

      while read -r row; do
         table=${row% *}
         type=${row##* }

         DUMP_OPTS=("$DB")
         DUMP_OPTS+=("--no-create-info")    # Do not write CREATE TABLES in the dump
         DUMP_OPTS+=("--skip-triggers")     # Do not include triggers, we have them in the structure
         DUMP_OPTS+=("--tables")

         # Make sure events are stored correctly, so add the right mysqlbackup
         # parameter when the mysql.event table is found.
         [[ $DB == "mysql" && $table == "event" ]] && DUMP_OPTS+=("--events")

         # MyISAM can't work with single-transactions, so exclude it
         if [ ! "$type" = MyISAM ]; then
            DUMP_OPTS+=("--single-transaction")
         fi

         # Lets check if its a table we need to skip
         # Loop over our databases
         for i in "${SKIP_TABLES[@]}"
         do
            # Check if we have a database that is identical to a skipped one.
            if [[ ${i%%.*} == $DB ]] && [[ ${SKIP} == 0 ]];then
               # Check if the table is identical to the one to be skipped
               if [[ ${i#*.} == "$table" ]];then
                  SKIP=1
                  break
               fi
            else
               SKIP=0
            fi
         done

         if [[ $SKIP -eq 1 ]]; then
            [[ $DEBUG -eq 1 ]] && printDebugStatus "SKIPPED" "  $table"
         else
            # Starting the backup of the table
            if [[ ! -z $table_types ]];then
               if [[ $DRY_RUN -eq 0 ]];then
                  OUTPUT=$(($BIN_MYSQLDUMP $LOGIN_OPTS "${DUMP_OPTS[@]}" "$table" | gzip -c > "$DB_BKP_DIR/$table.sql.gz") 2>&1)

                  if [ $? -ne 0 ]; then
                     [[ $DEBUG -eq 1 ]] && printDebugStatus "FAILED" "  $table" $type
                     ERROR_REASONS+=("${OUTPUT}")
                  else
                     [[ $DEBUG -eq 1 ]] && printDebugStatus "OK" "  $table" $type
                  fi
               else
                  printDebugStatus "DRY_RUN" "  $table" $type
               fi
            fi
         fi

      done <<< "$table_types"
   fi
done <<< "$DB_LIST"

if [[ $DRY_RUN -eq 0 ]];then
   [[ $DEBUG -eq 1 ]] && echo -e "\nBackup script finished. Data stored in '$LOCAL_BKP_DIR'..."
else
   [[ $DEBUG -eq 1 ]] && echo -e "\nBackup script finished, but NOTHING is stored in '$LOCAL_BKP_DIR'..."
fi

# If there are errors, print it. If not, bye...
printError
