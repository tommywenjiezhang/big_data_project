#!/usr/bin/env bash
# monitor-yarn.sh
# Usage: ./monitor-yarn.sh [interval_seconds]
# Example: ./monitor-yarn.sh 5

set -euo pipefail

INTERVAL="${1:-10}"

timestamp() { date +"%Y-%m-%d %H:%M:%S"; }

print_app_status() {
  local APPID="$1"

  # YARN application status (single call)
  local ST
  if ! ST="$(yarn application -status "$APPID" 2>/dev/null)"; then
    echo "[$(timestamp)] $APPID: unable to read status"; return
  fi

  # Lightweight field extraction
  local NAME STATE FINAL PROG USER QUEUE START ELAPSED RUNNING_CONTAINERS MEM VCORES
  NAME="$(awk -F': ' '/Application-Name/{print $2}' <<<"$ST")"
  STATE="$(awk -F': ' '/State/{print $2}' <<<"$ST")"
  FINAL="$(awk -F': ' '/Final-State/{print $2}' <<<"$ST")"
  PROG="$(awk -F': ' '/Progress/{print $2}' <<<"$ST")"
  USER="$(awk -F': ' '/User/{print $2}' <<<"$ST")"
  QUEUE="$(awk -F': ' '/Queue/{print $2}' <<<"$ST")"
  START="$(awk -F': ' '/Start-Time/{print $2}' <<<"$ST")"
  ELAPSED="$(awk -F': ' '/Elapsed-Time/{print $2}' <<<"$ST")"
  RUNNING_CONTAINERS="$(awk -F': ' '/Running-Containers/{print $2}' <<<"$ST")"
  MEM="$(awk -F': ' '/Allocated Memory MB/{print $2}' <<<"$ST")"
  VCORES="$(awk -F': ' '/Allocated VCores/{print $2}' <<<"$ST")"

  # Try to fetch classic MRv2 job status by translating ID
  local JOBID MR
  JOBID="${APPID/application_/job_}"
  MR="$(mapred job -status "$JOBID" 2>/dev/null || true)"

  local MAP_PROG RED_PROG MAP_DONE MAP_TOTAL RED_DONE RED_TOTAL
  MAP_PROG="$(awk -F': ' '/map progress/{print $2}' <<<"$MR" | sed 's/[[:space:]]//g')"
  RED_PROG="$(awk -F': ' '/reduce progress/{print $2}' <<<"$MR" | sed 's/[[:space:]]//g')"
  MAP_DONE="$(awk -F': ' '/map completed tasks/{print $2}' <<<"$MR")"
  MAP_TOTAL="$(awk -F': ' '/map total tasks/{print $2}' <<<"$MR")"
  RED_DONE="$(awk -F': ' '/reduce completed tasks/{print $2}' <<<"$MR")"
  RED_TOTAL="$(awk -F': ' '/reduce total tasks/{print $2}' <<<"$MR")"

  echo "--------------------------------------------------------------------------------"
  echo "[$(timestamp)]  APP: $APPID  ($NAME)"
  echo " State: $STATE   Final: $FINAL   Progress: $PROG   User: $USER   Queue: $QUEUE"
  echo " Start: $START   Elapsed: $ELAPSED"
  echo " Containers: running=$RUNNING_CONTAINERS  memMB=$MEM  vcores=$VCORES"

  if [[ -n "$MR" ]]; then
    echo " MR Job: $JOBID"
    [[ -n "$MAP_PROG" ]] && echo "   Map:    progress=$MAP_PROG  ($MAP_DONE/$MAP_TOTAL)"
    [[ -n "$RED_PROG" ]] && echo "   Reduce: progress=$RED_PROG  ($RED_DONE/$RED_TOTAL)"
  else
    echo " MR Job: (no classic MapReduce status available for $JOBID)"
  fi
}

monitor_once() {
  local APPS
  APPS="$(yarn application -list -appStates RUNNING,ACCEPTED 2>/dev/null | awk 'NR>2{print $1}')"
  if [[ -z "$APPS" ]]; then
    echo "[$(timestamp)] No RUNNING/ACCEPTED applications."
    return
  fi

  for APP in $APPS; do
    print_app_status "$APP"
  done
}

# Main loop
while true; do
  monitor_once
  sleep "$INTERVAL"
done
