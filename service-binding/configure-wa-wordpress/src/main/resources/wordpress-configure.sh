#!/bin/bash
#This script configures WordPress

set -o pipefail  # trace ERR through pipes
set -o nounset   # trace ERR through 'time command' and other functions
set -o errtrace  # set -u : exit the script if you try to use an uninitialised variable
set -o errexit   # set -e : exit the script if any statement returns a non-true return value

TERM=linux
DEBIAN_FRONTEND=noninteractive

stderr_log="/dev/shm/stderr.log"
exec 2>"$stderr_log"

template='{"code":"%s","message":"%s"}'
json=''

###~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##
#
# FUNCTION: EXIT_HANDLER
#
###~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##

exit_handler() {

    local code="$?"

    test $code == 0 && return;

    #
    # LOCAL VARIABLES:
    # ------------------------------------------------------------------
    #
    local i=0
    local regex=''
    local mem=''

    local error_file=''
    local error_lineno=''
    local error_message='unknown'

    local lineno=''

    #
    # GETTING LAST ERROR OCCURRED:
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #

    #
    # Read last file from the error log
    # ------------------------------------------------------------------
    #
    if test -f "$stderr_log"
        then
            stderr=$( tail -n 1 "$stderr_log" )
            sudo rm "$stderr_log"
    fi

    #
    # Managing the line to extract information:
    # ------------------------------------------------------------------
    #

    if test -n "$stderr"
        then
            # Exploding stderr on :
            mem="$IFS"
            local shrunk_stderr=$( echo "$stderr" | sed 's/\: /\:/g' )
            IFS=':'
            local stderr_parts=( $shrunk_stderr )
            IFS="$mem"

            # Storing information on the error
            error_file="${stderr_parts[0]}"
            error_lineno="${stderr_parts[1]}"
            error_message=""

            for (( i = 3; i <= ${#stderr_parts[@]}; i++ ))
                do
                    error_message="$error_message "${stderr_parts[$i-1]}": "
            done

            # Removing last ':' (colon character)
            error_message="${error_message%:*}"

            # Trim
            error_message="$( echo "$error_message" | sed -e 's/^[ \t]*//' | sed -e 's/[ \t]*$//' )"
    fi

    #
    # EXITING:
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #

    json=$(printf "$template" "$code" "$error_message")
    echo "$json" 

    exit "$code"
}

trap exit ERR
trap 'exit_handler' EXIT

#
# MAIN CODE:
#
###~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~##

docRoot=$1
contextRoot=$2
dbName=$3
dbUsr=$4
dbPwd=$5
dbIPAddress=$6
dbPort=$7

if [ "$contextRoot" == "/" ]; then
  contextRoot=""
fi

if [ ! -d $docRoot/$contextRoot ]; then
  eval "sudo mkdir -p $docRoot/$contextRoot"
fi

sudo rm -rf $docRoot/$contextRoot/*
sudo mv -f /opt/wordpress/wordpress/* $docRoot/$contextRoot

file=$(sudo find / -name 'wp-config-sample.php')
folder=$(dirname $file)
eval "cd $folder"

sudo cp wp-config-sample.php wp-config.php
sudo sed -i 's/database_name_here/'$dbName'/' wp-config.php
sudo sed -i 's/username_here/'$dbUsr'/' wp-config.php
sudo sed -i 's/password_here/'$dbPwd'/' wp-config.php
sudo sed -i 's/localhost/'$dbIPAddress:$dbPort'/' wp-config.php

sudo chown -R www-data:www-data $docRoot/$contextRoot
sudo chmod 777 -R $docRoot/$contextRoot

NAME="WordPress"
LOCK="/tmp/lockaptget"

while true; do
  if mkdir "${LOCK}" &>/dev/null; then
    echo "$NAME take apt lock"
    break;
  fi
  echo "$NAME waiting apt lock to be released..."
  sleep 1
done

while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 ; do
  echo "$NAME waiting for other software managers to finish..."
  sleep 1
done

sudo rm -f /var/lib/dpkg/lock
sudo dpkg --configure -a

sudo apt-get update
sudo apt-get -y -q install php-mysql
#sudo apt-get -y -q install php5-mysql

rm -rf "${LOCK}"
echo "$NAME released apt lock"

if (( $(ps -ef | grep -v grep | grep apache2 | wc -l) > 0 ))
  then
	sudo /etc/init.d/apache2 restart
else
	sudo /etc/init.d/apache2 start
fi

now=$(date)
echo "WORDPRESS-CONFIGURE --> $now" >> ~/log.txt

#json=$(printf "$template" "0" "WordPress configuration succeeded")
json=$(printf "$template" "0" "{\\\"context.root\\\":\\\"$contextRoot\\\"}")
echo "$json"

exit 0
