#!/bin/bash
#
# Query by dbtuna.com
#

MAX_PERCENT="80"
OUTFILE="/var/log/mysql/mysql-max-connections-tracker.log"

PERCENT=$((/usr/bin/mysql --defaults-extra-file=/etc/mysql/debian.cnf --skip-column-names -Be "select ( pl.connections / gv.max_connections ) * 100 as percentage_used_connections from ( select count(*) as connections from information_schema.processlist ) as pl, ( select VARIABLE_VALUE as max_connections from information_schema.global_variables where variable_name = 'MAX_CONNECTIONS' ) as gv;") | awk '{printf "%0.0f", $0}' 2>&1)

if [[ "${PERCENT}" > "${MAX_PERCENT}" ]]; then
	/usr/bin/logger -p user.crit "Max MySQL connections almost reached"
	echo "WARNING: Max_connections is high (${PERCENT} of ${MAX_PERCENT})"
	PROCESSLIST=$((/usr/bin/mysql --defaults-extra-file=/etc/mysql/debian.cnf -e "show full processlist") 2>&1)
	echo -en "HIGH (${PERCENT} of ${MAX_PERCENT}) @ " >> ${OUTFILE}
	date >> ${OUTFILE}
	echo -e "${PROCESSLIST}\n" >> ${OUTFILE}
	exit 1
fi
exit 0
