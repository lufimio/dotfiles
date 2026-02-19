#!/bin/sh

warning_threshold=15
critical_threshold=5

acpi -b | awk -F'[,:%]' '{print $2, $3}' | {
  read -r status capacity

  # If battery is discharging with capacity below threshold
  if [ "${status}" = Discharging ]; then
    if [ "${capacity}" -lt ${critical_threshold} ]; then
      notify-send -u critical -i battery-empty-symbolic "Critical: Low Battery" "Battery less than 5%, plug in immediately."
    elif [ "${capacity}" -lt ${warning_threshold} ]; then
      notify-send -i battery-caution-symbolic "Warning: Low Battery" "Battery less than 15%"
    fi
  fi
}
