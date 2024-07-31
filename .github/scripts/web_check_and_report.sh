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
    echo "URL to affected resource: $WEBURL" >> /tmp/webchecknotify-msg
    echo "Issue URL: $(cat /tmp/existingissue-$DATE | sed 's#content/#https://dev.status.bioconductor.org/#' | sed 's/.md//' |  tr '[:upper:]' '[:lower:]')" >> /tmp/webchecknotify-msg
    echo "Issue source: https://github.com/Bioconductor/status.bioconductor.org/blob/main/$(cat /tmp/existingissue-$DATE)" >> /tmp/webchecknotify-msg
    CURRSEVERITY=$(cat /tmp/existingissue-$DATE | xargs -i grep 'severity:' '{}' | awk '{print $2}' | tr -d "'")
    if [ "$CURRSEVERITY" == "down" ]; then
        NEWSEVERITY="disrupted"
        cat /tmp/existingissue-$DATE | xargs -i sed -i "s/severity: $CURRSEVERITY/severity: $NEWSEVERITY/" '{}'
        echo "Severity downgraded from '$CURRSEVERITY' to '$NEWSEVERITY' on $DATE" >> /tmp/webchecknotify-msg
    elif [ "$CURRSEVERITY" == "disrupted" ]; then
        cat /tmp/existingissue-$DATE | xargs -i sed -i 's/resolved: false/resolved: true/' '{}'
        cat /tmp/existingissue-$DATE | xargs -i sed -i "s/# resolvedWhen: /resolvedWhen: $(date '+%Y-%m-%d %H:%M:%S')/" '{}'
        echo "Severity downgraded from '$CURRSEVERITY' to 'resolved' on $DATE" >> /tmp/webchecknotify-msg
    fi
    git add "$(cat /tmp/existingissue-$DATE)"
  else
    NOTIFY=false
  fi
  echo "$DATE,$SYSTEM,$WEBURL $(cat /tmp/curlcheck-$DATE | grep "^HTTP" | tail -n 1 | awk '{print $1" "$2}'),ok" >> logs/checks.csv
else
  if ! grep -lR 'resolved: false' content/issues/*_"$SYSTEM".md > /tmp/existingissue-$DATE; then
    sed """s@##TITLE##@${TITLE}@g
           s@YYYY-MM-DD hh:mm:ss@$(date '+%Y-%m-%d %H:%M:%S')@g
           s@##SEVERITY##@${SEVERITY}@g
           s@##DESCRIPTION##@$(echo "$DATE $TITLE")@g
           s@##SYSTEM##@${SYSTEMNAME}@g""" .github/templates/incident.md > "content/issues/${DATE}_$SYSTEM.md"
    git add "content/issues"
    echo "URL to affected resource: $WEBURL" >> /tmp/webchecknotify-msg
    echo "Issue URL: https://github.com/Bioconductor/status.bioconductor.org/blob/main/content/issues/${DATE}_$SYSTEM.md" >> /tmp/webchecknotify-msg
    echo "Severity marked as '$SEVERITY'." >> /tmp/webchecknotify-msg
  else
    echo "URL to affected resource: $WEBURL" >> /tmp/webchecknotify-msg
    echo "Issue URL: https://github.com/Bioconductor/status.bioconductor.org/blob/main/$(cat /tmp/existingissue-$DATE)" >> /tmp/webchecknotify-msg
    CURRSEVERITY=$(cat /tmp/existingissue-$DATE | xargs -i grep 'severity:' '{}' | awk '{print $2}' | tr -d "'")
    if [ "$CURRSEVERITY" == "disrupted" ]; then
        NEWSEVERITY="down"
    elif [ "$CURRSEVERITY" == "down" ]; then
        NEWSEVERITY="down"
        NOTIFY=false
    fi
    cat /tmp/existingissue-$DATE | xargs -i sed -i "s/severity: $CURRSEVERITY/severity: $NEWSEVERITY/" '{}'
    echo "Severity upgraded from '$CURRSEVERITY' to '$NEWSEVERITY' on $DATE" >> /tmp/webchecknotify-msg
    git add "content/issues"
  fi
  echo "$DATE,$SYSTEM,$WEBURL $(cat /tmp/curlcheck-$DATE | grep "^HTTP" | tail -n 1 | awk '{print $1" "$2}'),down" >> logs/checks.csv
fi
rm /tmp/curlcheck-$DATE
rm /tmp/existingissue-$DATE
if $NOTIFY; then echo 'yes' > /tmp/webchecknotify; fi
git add logs/checks.csv
