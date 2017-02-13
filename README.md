# Snapshot stype backup using rsync over SSH

## The task at hand

As my home network grows, the need for a kind of centralized backup functionality becomes pressing.

## Literature

One can easily find on the Internet lists of backup solutions for Linux, free and proprietary alike. The method that fits in well with my style of doing things is using rsync. There are many rsync docs and tutorials online, however most of them are one-liners to accomplish some isolated task. The description of the setup below is based on this document: [Making secure remote backups with rsync](https://www.linux.com/news/making-secure-remote-backups-rsync).

## The strategy

The sketch of the indended mode of operation is as follows:

1. The backup server connects to hosts on the network.
2. The backup server rsync's specified directories from the hosts to itself (i.e. which directories on which hosts are to be backed up is configurable);
3. The connections are accomplished via SSH.

## Software requirements

The backup server and the hosts run Debian Jessie 8.7, amd64 architecture.

## Setting up SSH
### On the backup server
The rbackup user is created. It is a system user account (the -r switch), but with a home directory (the -m switch) for storing SSH keys:
```
admin@backup-server:~$ sudo useradd -r -m rbackup
```
An SSH public key is generated for logging into the hosts without the password prompt.
```
admin@backup-server:~$ cd /home/rbackup
admin@backup-server:~/home/backup$ ssh-keygen -t rsa -b 2048 -f ~/rsync-key
Generating public/private dsa key pair.
Enter passphrase (empty for no passphrase): [press enter here]
Enter same passphrase again: [press enter here]
Your identification has been saved in /home/user/rsync-key.
Your public key has been saved in /home/user/rsync-key.pub.
```
The public key must now be distributed to the network hosts that we intend to backup. Assuming that the admin account is present on the host, and that the admin account has a home directory on the host
```
admin@backup-server:~/home/rbackup$ scp /home/user/rbackup/rsync-key.pub admin@host:~/
```
Make a directory for storing rsync transfer logs and adjust its ownership and permissions:
```
admin@backup-server:~$ sudo mkdir /home/user/rbackup/logs
admin@backup-server:~$ sudo chown rbackup:rbackup /home/user/rbackup/logs
admin@backup-server:~$ sudo chmod 755 /home/user/rbackup/logs
```
The script will create and store the logs in files under the names having the form of <remote-host-name.log>

### On the network hosts
A simple script can be used to automate the setup on the host side:
```
#!/bin/bash
## hostsetup.sh

ADMIN_HOME=/home/admin
RBACKUP_HOME=/home/rbackup

useradd -r -m rbackup
cd $RBACKUP_HOME
mkdir .ssh
mv $ADMIN_HOME/rsync-key.pub .ssh/
touch .ssh/authorized_keys
cat .ssh/rsync-key.pub >> .ssh/authorized_keys
chown -r rbackup:rbackup .ssh/
chmod 700 .ssh
chmod 600 .ssh/*
```
Similarly, this script must be distributed to the network hosts:
```
admin@backup-server:~$ scp /home/user/rbackup/rsync-key.pub admin@host:~/
```
Now, locally on the host or via SSH
```
admin@host:~$ chmod +x hostsetup.sh
admin@host:~$ sudo ./hostsetup.sh
```

### The backup script

```
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
```

Copy this script to /home/rbackup/backup.sh on the backup server and
```
admin@backup-server:~$ sudo chown rbackup:rbackup /home/rbackup/backup.sh
admin@backup-server:~$ sudo chmod 700 /home/rbackup/backup.sh
```

Now, suppose there were a machine server-1 on the network that we'd like to backup. In order to make crontab declarations more readable, one could create a helper script like the one below in the rbackup home directory:
```
#!/bin/bash
# backup-server-1
# Backup of server-1
./backup.sh server-1 /etc /usr/local /var

exit 0
```
After making sure the backup-server-1 script ownership and permissions are OK,
```
admin@backup-server:~$ sudo chown rbackup:rbackup /home/rbackup/backup-server-1
admin@backup-server:~$ sudo chmod 700 /home/rbackup/backup-server-1
```
in order to schedule weekly backups of the server, /etc/crontab can be modified as follows
```
# m h dom mon dow user  command
...
00 17 *   *  Fri rbackup /home/rbackup/backup-server-1
```

## Log rotation

As the logs in /home/rbackup/logs grows with time, it is reasonable to configure logrotate to do its thing on those logs. To do so, let's create /etc/logrotate.d/rbackup with the following content
```
/home/rbackup/logs/*log {
   weekly
   rotate 4
   missingok
   compress
   notifempty
}
```
So, the logs will be rotated weekly, with compressed archives of four recent weeks worth of logs; the empty logfiles will not be rotated; if the log files will be missing it will be silently ignored. Please, refer to the logrotate manpage for further information.

## Further development
In future, it is worth an effort expanding the backup functionality with the following:
1. Compression of backup snapshots;
2. Rotation of backups.

## GitHub

The backup script and this writeup are stored at [https://github.com/technosceptic/backup-scripts](https://github.com/technosceptic/backup-scripts).
