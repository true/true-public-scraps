MySQL scripts
=============

Here you will find some scipts for MySQL. They have been stored here in the past years to make sure they will not get lost.

Please read the Wiki article about [Tips and Tricks](https://wiki.true.nl/Tips_and_Tricks:_MySQL "This is the internal Wiki of True" ) for more information.


### Files

✔ **mysql-backup.sh**
> Script to backup MySQL databases. It has options for exluding databases and tables. It handles also pipe-errors well, a common mistake in many MySQL backup scripts

✔ **mysql-backup.conf**
> This is the optional configuration file for the `mysql-backup.sh` script

✔ **mysql-report.sh**
> This will generate a fancy report of MySQL usage.
> Source: http://hackmysql.com/mysqlreport

✔ **mysql-max-connections-tracker.sh**
> This script will warn when the MySQL `max_connections` is almost reached. When its triggered, it will store the data in a file for reviewing.
> Use the following cron to enable this script:

`*/1 * * * * /root/bin/mysql-max-connections-tracker.sh > /dev/null 2>&1`
