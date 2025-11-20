#!/usr/bin/env bash
#
# Check reduce task states + shuffle errors for a YARN MRv2 job
#
# Usage:
#   ./check_reducers.sh                 # auto-pick latest RUNNING app
#   ./check_reducers.sh application_... # check specific application
#
# Optional env:
#   RM_HOST (default: master)
#   RM_PORT (default: 8088)

set -euo pipefail

RM_HOST="${RM_HOST:-master}"
RM_PORT="${RM_PORT:-8088}"

# --- 1. Get application ID ---------------------------------------------------

APPID="${1:-}"

if [ -z "$APPID" ]; then
  echo "No applicationId provided, trying to auto-detect latest RUNNING app..."
  APPID=$(yarn application -list -appStates RUNNING 2>/dev/null \
    | awk 'NR>2 {print $1}' | head -n1 || true)
  if [ -z "$APPID" ]; then
    echo "❌ No RUNNING applications found. Provide an applicationId explicitly."
    echo "   Example: ./check_reducers.sh application_1731550000000_0001"
    exit 1
  fi
fi

echo "Using applicationId: $APPID"

# Convert application_... -> job_... (MRv2 convention)
JOBID="job${APPID#application}"
echo "Derived jobId:       $JOBID"

# --- 2. Query YARN REST API for REDUCE task states --------------------------

echo
echo "=== Reduce task states from RM REST API ==="

TASK_JSON=$(curl -sf "http://${RM_HOST}:${RM_PORT}/ws/v1/mapreduce/jobs/${JOBID}/tasks?type=reduce" || true)

if [ -z "$TASK_JSON" ]; then
  echo "❌ Could not fetch tasks for $JOBID from RM (${RM_HOST}:${RM_PORT})."
  echo "   - Is the job still running?"
  echo "   - Is the ResourceManager web UI reachable (http://${RM_HOST}:${RM_PORT}/cluster)?"
else
  echo "$TASK_JSON" \
    | awk -F'"' '/"state":/ {print $4}' \
    | sort | uniq -c

  echo
  echo "Interpretation:"
  echo "  NEW / SCHEDULED / ASSIGNED -> PENDING (waiting for containers)"
  echo "  RUNNING                    -> Containers allocated, reducers active"
  echo "  SUCCEEDED / FAILED / KILLED -> Terminal states"
fi

# --- 3. Look for shuffle errors in logs -------------------------------------

echo
echo "=== Sampling YARN logs for shuffle errors ==="
echo "(searching for FetchFailed / Failed to connect / Connection timed out)"
echo

if yarn logs -applicationId "$APPID" >/tmp/_app_logs.$$ 2>/dev/null; then
  egrep -i 'FetchFailed|Failed to connect|Connection timed out' /tmp/_app_logs.$$ \
    | head -n 20 || echo "No obvious shuffle-related errors in first matches."
  rm -f /tmp/_app_logs.$$
else
  echo "❌ Could not fetch logs for $APPID (job may be finished or logs not retained)."
fi

echo
echo "Done."
