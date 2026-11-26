#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Lid Sleep Status
# @raycast.mode inline
# @raycast.refreshTime 1m

# Optional parameters:
# @raycast.icon 💻
# @raycast.packageName System

# Documentation:
# @raycast.description Shows whether the Mac stays awake with the lid closed (pmset disablesleep).
# @raycast.author asaday
# @raycast.authorURL https://raycast.com/asaday

if [ "$(pmset -g | awk '/SleepDisabled/ {print $2}')" = "1" ]; then
  echo "Awake with lid closed"
else
  echo "Sleeps with lid closed"
fi
