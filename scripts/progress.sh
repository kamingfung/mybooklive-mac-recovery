#!/bin/bash
# Live progress for a debugfs rdump copy. Run in a second Terminal window; Ctrl+C to stop.
# Usage: bash progress.sh /dev/diskNsM ~/MyBookLive/shares
DEV="${1:?usage: progress.sh /dev/diskNsM DEST_FOLDER}"
DEST="${2:?usage: progress.sh /dev/diskNsM DEST_FOLDER}"
DBG="${DBG:-$HOME/e2fs/e2fsprogs-1.47.1/debugfs/debugfs}"
INTERVAL=20

# Total = space used on the whole drive, so the bar stops short of 100% if you skipped folders.
stats=$(sudo DEBUGFS_PAGER=__none__ "$DBG" -R stats "$DEV" 2>/dev/null)
bc=$(awk -F: '/^Block count/{gsub(/ /,"",$2); print $2}' <<<"$stats")
fb=$(awk -F: '/^Free blocks/{gsub(/ /,"",$2); print $2}' <<<"$stats")
bs=$(awk -F: '/^Block size/{gsub(/ /,"",$2); print $2}' <<<"$stats")
total_kb=$(( (bc - fb) * bs / 1024 ))
[ "$total_kb" -gt 0 ] || { echo "Could not read drive size."; exit 1; }

gb() { awk -v k="$1" 'BEGIN{printf "%.1f GB", k/1048576}'; }

prev_kb=$(sudo du -sk "$DEST" 2>/dev/null | cut -f1); prev_kb=${prev_kb:-0}
echo "Drive has $(gb $total_kb) in use. Updating every ${INTERVAL}s..."
while true; do
  sleep "$INTERVAL"
  kb=$(sudo du -sk "$DEST" 2>/dev/null | cut -f1); kb=${kb:-0}
  rate=$(( (kb - prev_kb) / INTERVAL ))   # KB/s
  prev_kb=$kb
  pct=$(( kb * 100 / total_kb )); [ $pct -gt 100 ] && pct=100
  filled=$(( pct * 20 / 100 ))
  bar=$(printf '%*s' "$filled" '' | tr ' ' '#')$(printf '%*s' $((20 - filled)) '' | tr ' ' '-')
  if ! pgrep -f "debugfs.* -f " >/dev/null && ! pgrep -f "debugfs.*rdump" >/dev/null; then
    printf "\r\033[KCopy finished: %s copied to %s\n" "$(gb $kb)" "$DEST"
    exit 0
  fi
  if [ "$rate" -gt 0 ]; then
    eta="ETA <=$(( (total_kb - kb) / rate / 60 ))m"
  else
    eta="(between files)"
  fi
  # Kept short so it never wraps; \033[K clears the rest of the line.
  printf "\r\033[K[%s] %3d%% %s/%s %.1fMB/s %s" "$bar" "$pct" "$(gb $kb | cut -d' ' -f1)" "$(gb $total_kb)" \
    "$(awk -v r=$rate 'BEGIN{print r/1024}')" "$eta"
done
