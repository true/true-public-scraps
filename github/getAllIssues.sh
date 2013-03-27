#!/bin/bash
#
# Author   : L.Lakkas
# Version  : 1.02
# Copyright: L. Lakkas @ TrueServer.nl B.V.
#
# Current scripts based on:
# http://www.fullo.net/blog/2012/06/25/export-github-issues-as-csv-with-v3-api/
#
# TODO:
# We should get rid of PHP and make it default *nix compatible by using bash and
# grep/perl together. Some examples:
#
# Parse title using grep:
# grep -Po '"title":.*?[^\\]",' /tmp/dumpIssues.json
#
# Parse issue numbers only using Perl:
# perl -ne 'print if s/"number"://; s/^"//; s/",$//' < dumpIssues.json

# Fill in your username and password for Github
GITHUB_USER="hackme"
GITHUB_PASS="letmein"

# Fill in the organisation and repository of Github, where the issues reside
GITHUB_ORGANIZATION="org"
GITHUB_REPOSITORY="repo"

# Would you like to view open or closed issues? (Boolean)
SHOW_CLOSED=false


#############################################################################
# Actual script below.

php -v >/dev/null 2>&1 || { echo >&2 "PHP-CGI is required but not installed. Aborting..."; exit 1; }

tempfoo=`basename $0`
TMP_ISSUES_FILE=`mktemp -q /tmp/${tempfoo%%.*}.XXXXXX`
if [ $? -ne 0 ]; then
  echo "Can't create issues temp file, exiting..."
  exit 1
fi

TMP_HEADER_FILE=`mktemp -q /tmp/${tempfoo%%.*}.XXXXXX`
if [ $? -ne 0 ]; then
  echo "Can't create header temp file, exiting..."
  exit 1
fi

echo -n "Searching all "
$SHOW_CLOSED &&  echo -n "closed" || echo -n "open"
echo " issues from Github...."

echo "Getting page 1 from Github API..."

# Get the first like of issues and see how many pages we have:
$SHOW_CLOSED && STATE="&state=closed" || STATE=""
curl -s -u "$GITHUB_USER:$GITHUB_PASS" "https://api.github.com/repos/$GITHUB_ORGANIZATION/$GITHUB_REPOSITORY/issues?page=$i&per_page=100$STATE" --insecure --dump-header $TMP_HEADER_FILE > $TMP_ISSUES_FILE
PAGES=`cat ${TMP_HEADER_FILE} | grep "Link:"| eval "sed 's/.*?page=\(.*\)&per_page=100${STATE}>; rel=\"last.*/\1/'"`

if [[ -z $PAGES ]];then
  echo "No pages found. Possibly a authentication issue at Github!"
  exit 1
fi

if [[ $PAGES -gt 1 ]];then
  for (( i=2; i<=$PAGES; i++ ))
  do
    echo "Getting page $i from Github API..."

    curl -s -u "$GITHUB_USER:$GITHUB_PASS" "https://api.github.com/repos/$GITHUB_ORGANIZATION/$GITHUB_REPOSITORY/issues?page=$i&per_page=100$STATE" --insecure >> $TMP_ISSUES_FILE
  done
fi

# Fix the pages end issues.
perl -0777 -pi -e 's/  }\n\]\n\[\n  {/  },\n  {/igs' $TMP_ISSUES_FILE

# Lets write the csv
php issues.php $TMP_ISSUES_FILE > issues.csv

# Remove temp files
rm "$TMP_ISSUES_FILE"
rm "$TMP_HEADER_FILE"
echo "Done! Now open file issues.csv on your desktop!"
