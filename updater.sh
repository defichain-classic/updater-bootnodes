#!/bin/bash
if [ ! -d /app/download ]; then
    mkdir -p /app/download;
fi;
if [ ! -d /app/data ]; then
    mkdir -p /app/data;
fi;
if [ ! -d /app/updater ]; then
    mkdir -p /app/updater;
fi;

if [ ! -f "/nodekey.hex" ]; then
    echo "Nodekey is not set in /nodekey.hex! ERROR!"
    exit 1
fi;
NODEKEY=`cat /nodekey.hex | tr -d '\n'`

# Ensure service is there
if [ ! -f "/etc/systemd/system/defichain.service" ]; then
    echo "Installing Service ..."
    cat > /etc/systemd/system/defichain.service << EOF
[Unit]
Description=Defichain Classic Client

[Service]
Type=simple
ExecStart=/app/geth --defichain --datadir /app/data --nodekeyhex $NODEKEY

[Install]
WantedBy=default.target
EOF
fi;

# Ensure that updater is downloaded and set up to run as a cron/service
if [ ! -f "/app/updater/updater.sh" ]; then
    echo "Installing Updater Script ..."
    cp "$0" /app/updater/updater.sh
    echo "Installing Updater Cron Job ..."
    cat > /etc/systemd/system/defichain-updater.service << EOF
[Unit]
Description=Update Defichain From Github

[Service]
Type=oneshot
ExecStart=/app/updater/updater.sh fromservice

[Install]
WantedBy=default.target
EOF


    cat > /etc/systemd/system/defichain-updater.timer << EOF
[Unit]
Description=Timer for Update Defichain From Github
Requires=defichain-updater.service

[Timer]
Unit=defichain-updater.service

# Time to wait after booting before we run first time
OnBootSec=10min

# Define a calendar event (see `man systemd.time`)
OnCalendar=*:0/15

[Install]
WantedBy=default.target
EOF

    systemctl daemon-reload
    systemctl enable defichain-updater.service
    systemctl enable defichain-updater.timer
    systemctl start defichain-updater.timer
    echo "All setup! The timer will launch the rest of the updater!"
    exit 0
fi;

if [[ $# -ne 1 ]]; then
    echo 'Only the timer should run this script from this point on' >&2
    exit 1
fi

curl -sL -H "Accept: application/vnd.github+json" -H "Authorization: Bearer  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 " -H "X-GitHub-Api-Version: 2022-11-28" https://api.github.com/repos/defichain-classic/core/releases/latest > /app/latest.txt
SERVER_VERSION=`cat /app/latest.txt | jq -r ".tag_name"`
DOWNLOAD_LINK=`cat /app/latest.txt | grep alltools-linux | grep -v sha256 | grep download_url | awk '{print $2}' | awk -F '"' '{print $2}'`
rm /app/latest.txt
if [[ ${SERVER_VERSION:0:1} == "v" ]] ; then
  echo "Current Server Version: $SERVER_VERSION"
  FILE=/app/local.version
  LOCAL_VERSION='none'
  if test -f "$FILE"; then
    LOCAL_VERSION=`cat $FILE | tr -d '\n'`
  fi
  echo "Current Local Version: $LOCAL_VERSION"
  if [ "$LOCAL_VERSION" = "$SERVER_VERSION" ]; then
    echo "Update is not required ..."

    IFRUNNING=`systemctl is-active defichain.service | tr -d '\n'`
    if [ "$IFRUNNING" = "inactive" ]; then
        echo "Defichain not running, starting service ..."
        systemctl start defichain.service
    fi;
  else
    echo "Performing upgrade ..."

    echo "Stopping service"
    systemctl stop defichain.service

    rm -rf /app/download/*
    wget -O /app/download/zipfile.zip $DOWNLOAD_LINK
    if test -f "/app/download/zipfile.zip"; then
      echo "Download sucessful, extracting ..."
      rm /app/*
      unzip /app/download/zipfile.zip -d /app
      rm /app/download/zipfile.zip
      echo $SERVER_VERSION > /app/local.version

      echo "Restarting service"
      systemctl daemon-reload
      systemctl start defichain.service
    else
      echo "Download failed: retrying later"
    fi
  fi
else echo "Failed to fetch version from server: retrying later"; fi