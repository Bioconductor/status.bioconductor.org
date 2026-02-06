#!/bin/bash
# USAGE:
# bash .github/scripts/web_check_and_report.sh 'http://bioconductor.org' '(Auto-detected) Bioconductor Main Site Down' 'down' 'Main site'
CHECKTYPE="$1"
WEBURL="$2"
TITLE="$3"
SEVERITY="$4"
SYSTEMNAME="$5"

SYSTEM=$(echo "$SYSTEMNAME" | sed 's/ /_/g')
set -x
NOTIFY=true
DATE=$(TZ='America/New_York' date '+%Y-%m-%d-%H-%M-%S')

if [ "$CHECKTYPE" == "webcheck" ]; then
  curl -s --head -L --request GET "$WEBURL" > /tmp/curlcheck-$DATE
  if cat /tmp/curlcheck-$DATE | grep "^HTTP" | grep "200" > /dev/null; then 
    echo "pass" > /tmp/check
  else
    echo "fail" > /tmp/check
  fi
elif [ "$CHECKTYPE" == "statscheck" ]; then
  date_string=$(curl -s "$WEBURL" | grep -oP "Data as of \K[^<]+")
  extracted_date=$(date -d "$date_string" +%s)
  current_date=$(date +%s)
  difference=$((current_date - extracted_date))
  hours=$((difference / 3600))
  if [ $hours -gt 60 ]; then
    echo "fail" > /tmp/check
  else
    echo "pass" > /tmp/check
  fi
else
  echo "ERROR: UNKNOWN CHECK TYPE!!"
  exit 1
fi

if grep -q 'pass' /tmp/check; then
  touch /tmp/existingissue-$DATE
  if grep -lR 'resolved: false' content/issues/*_"$SYSTEM".md > /tmp/existingissue-$DATE; then
    echo "URL to affected resource: $WEBURL" >> /tmp/webchecknotify-msg-$SYSTEM
    echo "Issue URL: $(cat /tmp/existingissue-$DATE | sed 's#content/#https://dev.status.bioconductor.org/#' | sed 's/.md//' |  tr '[:upper:]' '[:lower:]')" >> /tmp/webchecknotify-msg-$SYSTEM
    echo "Issue source: https://github.com/Bioconductor/status.bioconductor.org/blob/main/$(cat /tmp/existingissue-$DATE)" >> /tmp/webchecknotify-msg-$SYSTEM
    CURRSEVERITY=$(cat /tmp/existingissue-$DATE | xargs -i grep 'severity:' '{}' | awk '{print $2}' | tr -d "'")
    if [ "$CURRSEVERITY" == "down" ]; then
        NEWSEVERITY="disrupted"
        cat /tmp/existingissue-$DATE | xargs -i sed -i "s/severity: $CURRSEVERITY/severity: $NEWSEVERITY/" '{}'
        echo "Severity downgraded from '$CURRSEVERITY' to '$NEWSEVERITY' on $DATE" >> /tmp/webchecknotify-msg-$SYSTEM
    elif [ "$CURRSEVERITY" == "disrupted" ]; then
        cat /tmp/existingissue-$DATE | xargs -i sed -i 's/resolved: false/resolved: true/' '{}'
        cat /tmp/existingissue-$DATE | xargs -i sed -i "s/# resolvedWhen: /resolvedWhen: $(date '+%Y-%m-%d %H:%M:%S')/" '{}'
        echo "Severity downgraded from '$CURRSEVERITY' to 'resolved' on $DATE" >> /tmp/webchecknotify-msg-$SYSTEM
    fi
    git add "$(cat /tmp/existingissue-$DATE)"
  else
    NOTIFY=false
  fi
  # Separate log file per service with latest at top
  LOGFILE="logs/${SYSTEM}.csv"
  mkdir -p logs
  # Create header if file doesn't exist
  if [ ! -f "$LOGFILE" ]; then
    echo "DATE,SERVICE,NOTES,STATUS" > "$LOGFILE"
  fi
  # Reverse file (skip header), append new entry, reverse back
  tail -n +2 "$LOGFILE" | tac > /tmp/reversed-$SYSTEM
  echo "$DATE,$SYSTEM,$WEBURL $(cat /tmp/curlcheck-$DATE | grep "^HTTP" | tail -n 1 | awk '{print $1" "$2}'),ok" >> /tmp/reversed-$SYSTEM
  tac /tmp/reversed-$SYSTEM > /tmp/temp-$SYSTEM
  echo "DATE,SERVICE,NOTES,STATUS" > "$LOGFILE"
  cat /tmp/temp-$SYSTEM >> "$LOGFILE"
  rm /tmp/reversed-$SYSTEM /tmp/temp-$SYSTEM
else
  if ! grep -lR 'resolved: false' content/issues/*_"$SYSTEM".md > /tmp/existingissue-$DATE; then
    sed """s@##TITLE##@${TITLE}@g
           s@YYYY-MM-DD hh:mm:ss@$(date '+%Y-%m-%d %H:%M:%S')@g
           s@##SEVERITY##@${SEVERITY}@g
           s@##DESCRIPTION##@$(echo "$DATE $TITLE")@g
           s@##SYSTEM##@${SYSTEMNAME}@g""" .github/templates/incident.md > "content/issues/${DATE}_$SYSTEM.md"
    git add "content/issues"
    echo "URL to affected resource: $WEBURL" >> /tmp/webchecknotify-msg-$SYSTEM
    echo "Issue URL: https://github.com/Bioconductor/status.bioconductor.org/blob/main/content/issues/${DATE}_$SYSTEM.md" >> /tmp/webchecknotify-msg-$SYSTEM
    echo "Severity marked as '$SEVERITY'." >> /tmp/webchecknotify-msg-$SYSTEM
  else
    echo "URL to affected resource: $WEBURL" >> /tmp/webchecknotify-msg-$SYSTEM
    echo "Issue URL: https://github.com/Bioconductor/status.bioconductor.org/blob/main/$(cat /tmp/existingissue-$DATE)" >> /tmp/webchecknotify-msg-$SYSTEM
    CURRSEVERITY=$(cat /tmp/existingissue-$DATE | xargs -i grep 'severity:' '{}' | awk '{print $2}' | tr -d "'")
    if [ "$CURRSEVERITY" == "disrupted" ]; then
        NEWSEVERITY="down"
    elif [ "$CURRSEVERITY" == "down" ]; then
        NEWSEVERITY="down"
        NOTIFY=false
    fi
    cat /tmp/existingissue-$DATE | xargs -i sed -i "s/severity: $CURRSEVERITY/severity: $NEWSEVERITY/" '{}'
    echo "Severity upgraded from '$CURRSEVERITY' to '$NEWSEVERITY' on $DATE" >> /tmp/webchecknotify-msg-$SYSTEM
    git add "content/issues"
  fi
  # Separate log file per service with latest at top
  LOGFILE="logs/${SYSTEM}.csv"
  mkdir -p logs
  # Create header if file doesn't exist
  if [ ! -f "$LOGFILE" ]; then
    echo "DATE,SERVICE,NOTES,STATUS" > "$LOGFILE"
  fi
  # Reverse file (skip header), append new entry, reverse back
  tail -n +2 "$LOGFILE" | tac > /tmp/reversed-$SYSTEM
  echo "$DATE,$SYSTEM,$WEBURL $(cat /tmp/curlcheck-$DATE | grep "^HTTP" | tail -n 1 | awk '{print $1" "$2}'),down" >> /tmp/reversed-$SYSTEM
  tac /tmp/reversed-$SYSTEM > /tmp/temp-$SYSTEM
  echo "DATE,SERVICE,NOTES,STATUS" > "$LOGFILE"
  cat /tmp/temp-$SYSTEM >> "$LOGFILE"
  rm /tmp/reversed-$SYSTEM /tmp/temp-$SYSTEM
fi
rm /tmp/curlcheck-$DATE
rm /tmp/existingissue-$DATE
if $NOTIFY; then echo 'yes' > /tmp/webchecknotify-$SYSTEM; fi
cat /tmp/webchecknotify-msg-$SYSTEM >> /tmp/webchecknotify-msg 2>/dev/null || true
git add logs/${SYSTEM}.csv
