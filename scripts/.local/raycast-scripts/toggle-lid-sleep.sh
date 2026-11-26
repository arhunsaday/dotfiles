#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Toggle Lid Sleep
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 💻
# @raycast.packageName System

# Documentation:
# @raycast.description Toggles pmset disablesleep, which keeps the Mac awake with the lid closed. It blocks all system sleep, not only lid sleep.
# @raycast.author asaday
# @raycast.authorURL https://raycast.com/asaday

password=$(security find-generic-password -w -s 'Sudo password' -a 'sudo')

sleep_disabled=$(pmset -g | awk '/SleepDisabled/ {print $2}')

if [ "$sleep_disabled" = "1" ]; then
  target=0
  status="Lid sleep on: Mac sleeps when lid is closed"
else
  target=1
  status="Lid sleep off: Mac stays awake when lid is closed"
fi

if ! printf '%s\n' "$password" | sudo -S -p '' pmset -a disablesleep "$target" 2>/dev/null; then
  echo "Failed to change sleep setting"
  exit 1
fi

echo "$status"
