#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Toggle MacBook resolution
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 💻
# @raycast.packageName Resolution

# Documentation:
# @raycast.description Toggle the built-in display between default and more space, keeping the external display arrangement
# @raycast.author Arhun Saday
# @raycast.authorURL https://raycast.com/asaday

DEFAULT_RES="1512x982"
MORE_SPACE_RES="1800x1169"

list=$(displayplacer list)

# Persistent id of the built-in screen (3 lines above its "Type:")
builtin_id=$(echo "$list" | grep -B3 "Type: MacBook built in screen" | sed -n 's/^Persistent screen id: //p')
if [ -z "$builtin_id" ]; then
  echo "Built-in display not found"
  exit 1
fi

# Current arrangement, one display config per line
configs=$(echo "$list" | tail -1 | grep -o '"id:[^"]*"' | tr -d '"')

main_h=$(echo "$configs" | grep 'origin:(0,0)' | sed -E 's/.* res:[0-9]+x([0-9]+).*/\1/')
builtin_config=$(echo "$configs" | grep "id:$builtin_id")

read -r w h x y < <(echo "$builtin_config" | sed -E 's/.* res:([0-9]+)x([0-9]+).* origin:\((-?[0-9]+),(-?[0-9]+)\).*/\1 \2 \3 \4/')

if [ "${w}x${h}" = "$DEFAULT_RES" ]; then
  new_res=$MORE_SPACE_RES
else
  new_res=$DEFAULT_RES
fi
new_w=${new_res%x*}
new_h=${new_res#*x}

# Keep the built-in screen attached to the same edge of the main display
if [ $((y + h)) -le 0 ]; then      # above: keep bottom edge, keep centered
  x=$((x + (w - new_w) / 2))
  y=$((y + h - new_h))
elif [ "$y" -ge "${main_h:-0}" ]; then # below: keep top edge, keep centered
  x=$((x + (w - new_w) / 2))
elif [ $((x + w)) -le 0 ]; then    # left: keep right edge
  x=$((x + w - new_w))
fi                                 # right: keep left edge

new_builtin_config=$(echo "$builtin_config" | sed -E "s/res:[0-9]+x[0-9]+/res:$new_res/; s/origin:\([^)]*\)/origin:($x,$y)/")

args=()
while IFS= read -r config; do
  if [ "$config" = "$builtin_config" ]; then
    args+=("$new_builtin_config")
  else
    args+=("$config")
  fi
done <<< "$configs"

displayplacer "${args[@]}"
