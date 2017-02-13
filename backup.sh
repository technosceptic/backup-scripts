#!/bin/bash
# backup.sh -- secure rsync backup from a remote host
#              to the backup server running this script

function usage ()
{
    printf "Usage: $0 <remote-host> <remote-directory1>...<remote-directoryN>\n\
           \t<remote-host>:\t\tan IP or FQDN of the remote host\n\
	   \t<remote-directoryN>:\tthe folder on the remote host to backup\n
           \n\tExample: $0 10.0.1.1 /etc /srv/samba\n"
}

if [ 2 -gt $# ]; then
    echo "Too few parameters"
    usage;
    exit 1
fi

# IP or FQDN of the remote host
RMACHINE=$1

# Directories on the remote host to backup.
# Exclude trailing slash in directory names!
RSOURCES=${*:2}
#echo $RSOURCES

# Remote username
RUSER=rbackup

# Location of passphraseless ssh keyfile
RKEY=/home/rbackup/rsync_key

# Directory to backup FROM the remote machine.
TARGET_PREFIX=/srv/backups
TARGET="$TARGET_PREFIX/$RMACHINE"

# The EXCLUDE_FILE tells rsync what NOT to backup.
#EXCLUDE_FILE="/path/to/your/exclude_file.txt"

# The directory storing the logs
LOG_DIRECTORY="/home/rbackup/logs"

# Comment out the following line to disable verbose output
VERBOSE="--verbose"

# Comment out the following line to disable progress output
PROGRESS="--progress"

# Comment out the following line to disable stats output
STATS="--stats"

# Comment out the following line to disable compression during transfer
COMPRESS="--compress"

# Comment out the follewing line to keep permissions while backing up
PERMISSIONS="--perms"

###########################################
## IF YOU ARE EDITING BELOW THIS POINT,  ##
## I PRESUME YOU KNOW WHAT YOU ARE DOING ##
###########################################

LOG_FILE="$LOG_DIRECTORY/$RMACHINE.log"
if [ ! -f $LOG_FILE ]; then
   touch $LOG_FILE
fi
LOG="--log-file=$LOG_FILE"


date >> $LOG_FILE
echo "Verifying ssh keyfile..." >> $LOG_FILE
if [ ! -f $RKEY ]; then
  echo "Couldn't find ssh keyfile!" >> $LOG_FILE
  echo "Exiting..." >> $LOG_FILE
  exit 2
fi

echo "Verifying the source directory on the remote host..." >> $LOG_FILE
for source in $RSOURCES; do
  if ! ssh -i $RKEY $RUSER@$RMACHINE "test -x $source"; then
     echo "Error $source doesn't exist on $RMACHINE "\
          "or has wrong permissions." >> $LOG_FILE
    echo "Exiting..." >> $LOG_FILE
    exit 2
  fi
done

echo "Verifying the local target..." >> $LOG_FILE
if [ ! -x $TARGET ]; then
     echo "Error: $TARGET does not exist, or has wrong permissions." >> $LOG_FILE
     echo "Exiting..." >> $LOG_FILE
     exit 2
fi

if [ -f $EXCLUDE_FILE ]; then
EXCLUDE="--exclude-from=$EXCLUDE_FILE"
fi

echo "Source and target verified. Running rsync..." >> $LOG_FILE
for source in $RSOURCES; do
    if [ ! -d $TARGET$source ]; then
        echo "$TARGET$source" >> $LOG_FILE
        mkdir -p $TARGET$source
    fi
     rsync $VERBOSE $PROGRESS $STATS $COMPRESS $EXCLUDE $PERMISSIONS $LOG -a --delete -e "ssh -i $RKEY" $RUSER@$RMACHINE:$source/ $TARGET$source/
done

exit 0

