#!/bin/bash
#
# True MySQL backup script for Bacula implementations
#
# Author   : L. Lakkas
# Version  : 2.17
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
#
# Storable variables:
# DB_USER	 The MySQL login user
#                Sample: DB_USER=root
# DB_PASS	 The MySQL password for the specified user
#                Sample: DB_PASS=letmein
# SKIP_DATABASES Array of databases to skip
# 		 Sample: SKIP_DATABASES=(information_schema)
# SKIP_TABLES    Array of tables to skip, prefixed with database
#                Sample: SKIP_TABLES=(mysql.host)
# LOCAL_BKP_DIR  The directory to put the backup in. It is not
#                advised to use the /tmp or /var/tmp directory
#                for security reasons.
#                Sample: LOCAL_BKP_DIR=/backup/mysql
# DEBUG          Boolean to enable or disable debug output
#                Sample: DEBUG=0		(Default)
# DISK_MIN_FREE  The minimum amount of diskspace in Gigabytes
#                Sample: DISK_MIN_FREE=3	(Default)
#
# Note: If you want to put any of these files in a configuration
#       file, make sure you prefix them with CONFIG_.
#       Sample: CONFIG_DEBUG=1
#
#       It is also possible to use command line variable imput in
#       the form of:
#       DB_USER=root DB_PASS=letmein ./mysql-backup.sh
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

# Prepare error array
ERROR_REASONS=()

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
      exit 0
   fi
}

# Only root is allowed to run the script
if [ ! "$(id -u -n)" = "root" ]; then
   ERROR_REASONS+=("Only user 'root' can run this script!")
   printError
fi

# Find and read our configuration file. The pre-set configuration
# file location can be overridden by placing a configuration file
# in the same directory as this script.

# Get our current working directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
READ_CONFIG="${DIR}/mysql-backup.conf"
unset DIR

# Check if the configuration file exists and has a size greater
# then zero. If this is the case, strip out the vars and read it
if [[ -s $READ_CONFIG ]] && [[ $READ_CONFIG != $CONFIG_FILE ]]; then
   # Local configuration found
   source <( sed -n 's/^CONFIG_*//p' $READ_CONFIG )
   CONFIG_TYPE=1
else
   if [[ -s $CONFIG_FILE ]];then
      source <( sed -n 's/^CONFIG_*//p' $CONFIG_FILE )
      CONFIG_TYPE=2
   else
      echo "No configuration file found..."
      CONFIG_TYPE=3
   fi
fi

# Override DEBUG parameter from command line
[ "$#" -eq 1 ] && [[ "$1" == "--debug" ]] && DEBUG=1
# Print debug status
if [[ $DEBUG -eq 1 ]];then
   echo "Debug enabled..."
   case $CONFIG_TYPE in
      1) echo "Using custom configuration in script-directory ($READ_CONFIG)..." ;;
      2) echo "Using default configuration file..." ;;
      3) echo "Config file '$CONFIG_FILE' or '$READ_CONFIG' was not found..." ;;
   esac
fi
unset READ_CONFIG
unset CONFIG_TYPE

# If no minimum free diskspace is given, default to 1 Gb
DISK_MIN_FREE=${DISK_MIN_FREE:-1}
[[ $DEBUG -eq 1 ]] && echo -e "Minimum free diskspace is set to $DISK_MIN_FREE Gb..."

# Get terminal width
[[ $DEBUG -eq 1 ]] && echo "Terminal type is set to '$TERM'..."

# Fix pseudo terminals with fixed width
if [ $TERM == "dumb" ];then
   width=60
else
   # Get the terminal width and remove the width of the
   # biggest word ( [ SKIPPED ])
   ((width=$(tput cols)-12))
fi

# Fancy messages
function printDebugStatus {
   printf "%-${width}s [ $1 ]\n" "$2"
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
      LOGIN_OPTS="--defaults-file=/etc/mysql/debian.cnf"
   else
      # Check if we have a DirectAdmin login method
      if [ -f "/usr/local/directadmin/conf/my.cnf" ];then
         LOGIN_OPTS="--defaults-file=/usr/local/directadmin/conf/my.cnf"
      else
         ERROR_REASONS+=("No MySQL login method found and no credentials given, aborting...")
         printError
      fi
   fi
fi

DB_LIST=$((echo "show databases;"|mysql $LOGIN_OPTS -N) 2>&1)

# Check if we made correctly a connection
if [[ $? -gt 0 ]];then
   [[ $DEBUG -eq 1 ]] && echo -e "Wrong credentials of MySQL...\nTried to use credentials: $LOGIN_OPTS"
   ERROR_REASONS+=("${DB_LIST}")
   printError
   exit 1
fi

# Just output the skipped databases and tables
if [[ $DEBUG -eq 1 ]];then
   if [ ${#SKIP_DATABASES[@]} -gt 1 ];then
      echo -e "\nSkipping databases:"
      for i in "${SKIP_DATABASES[@]}"
      do
         echo "  $i"
      done
   fi
fi
if [[ $DEBUG -eq 1 ]]; then
   if [ ${#SKIP_TABLES[@]} -gt 1 ];then
      echo -e "\nSkipping tables:"
      for i in "${SKIP_TABLES[@]}"
      do
         echo "  $i"
         done
      fi
fi

[[ $DEBUG -eq 1 ]] && echo -e "\nStarting backup...\n"

# Now create the backups
for DB in $DB_LIST; do
   SKIP=0;
   for i in "${SKIP_DATABASES[@]}"
   do
      if [[ $i == $DB ]];then
         [[ $DEBUG -eq 1 ]] && printDebugStatus "SKIPPED" $DB
         SKIP=1;
      fi
   done
   if [[ $SKIP -eq 0 ]]; then
      # Go ahead!

      DB_BKP_DIR=$LOCAL_BKP_DIR/$DB

      # Verify if we can make the directory
      if [[ ! -d $DB_BKP_DIR ]]; then
         OUTPUT=$((mkdir -p $DB_BKP_DIR) 2>&1)
         if [[ $? -eq 1 ]]; then
            [[ $DEBUG -eq 1 ]] && echo "Can not make directory '$DB_BKP_DIR'..."
            ERROR_REASONS+=("${OUTPUT}")
         fi
      fi

      # Create the skip string for the structure dump
      SKIPSTRING=""
      for i in "${SKIP_TABLES[@]}"
      do
         # Check if we have a database that is identical to a skipped one.
         if [[ ${i%%.*} == $DB ]];then
            # Check if the table is identical to the one to be skipped
            SKIPSTRING=$SKIPSTRING" --ignore-table=$i"
         fi
      done

      # Get the schema of database with the stored procedures.
      # This will be the first file in the database backup folder
      OUTPUT=$((mysqldump $LOGIN_OPTS -R -d --single-transaction$SKIPSTRING "$DB" | gzip -c > "$DB_BKP_DIR/000-DB_SCHEMA.sql.gz") 2>&1)

      if [ $? -ne 0 ]; then
         [[ $DEBUG -eq 1 ]] && printDebugStatus "FAILED" $DB
         ERROR_REASONS+=("${OUTPUT}")
      else
         [[ $DEBUG -eq 1 ]] && printDebugStatus "OK" $DB
      fi

      index=0
      # Get the tables and its type. Store it in an array.
      # Using backticks around $DB for users who have dashes in there database / table names.
      table_types=($(mysql $LOGIN_OPTS --skip-column-names -e "show table status from \`$DB\`" | awk '{print $1,$2}'))
      table_type_count=${#table_types[@]}
      # Loop through the tables and apply the mysqldump option according to the table type
      # The table specific SQL files will not contain any create info for the table schema.
      # It will be available in SCHEMA file
      # Credit: http://thejahil.blogspot.nl/2009/09/mysql-backup-script.html [Sunday, September 27, 2009]
      while [ "$index" -lt "$table_type_count" ]; do
         START=$(date +%s)
         TYPE=${table_types[$index + 1]}
         table=${table_types[$index]}
         if [ "$TYPE" = "MyISAM" ]; then
            DUMP_OPTS="$DB --no-create-info --tables$DUMP_OPTS_SKIP"
         else
            DUMP_OPTS="$DB --no-create-info --single-transaction --tables$DUMP_OPTS_SKIP"
         fi

         # Lets check if its a table we need to skip
         # Loop over our databases
         for i in "${SKIP_TABLES[@]}"
         do
            # Check if we have a database that is identical to a skipped one.
            if [[ ${i%%.*} == $DB ]] && [[ ${SKIP} == 0 ]];then
               # Check if the table is identical to the one to be skipped
               if [[ ${i#*.} == $table ]];then
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
            OUTPUT=$((mysqldump $LOGIN_OPTS $DUMP_OPTS "$table" | gzip -c > "$DB_BKP_DIR/$table.sql.gz") 2>&1)

            if [ $? -ne 0 ]; then
               [[ $DEBUG -eq 1 ]] && printDebugStatus "FAILED" "  $table"
               ERROR_REASONS+=("${OUTPUT}")
            else
               [[ $DEBUG -eq 1 ]] && printDebugStatus "OK" "  $table"
            fi
         fi

         index=$(($index + 2))
      done
   fi
done

[[ $DEBUG -eq 1 ]] && echo -e "\nBackup script finished. Result is stored in '$LOCAL_BKP_DIR'..."

# If there are errors, print it. If not, bye...
printError
