#!/usr/bin/env bash
# ============================================================
# Hadoop/YARN Reducer Diagnostic Script
# Usage: ./yarn_diagnose.sh application_XXXXXXXXXXXXX_XXXX
# ============================================================

APP="$1"
if [ -z "$APP" ]; then
  echo "Usage: $0 <application_id>"
  exit 1
fi

JOB="${APP/application_/job_}"
echo "== Diagnosing Application: $APP (Job: $JOB) =="

timestamp() { date +"%Y-%m-%d %H:%M:%S"; }

echo
echo "[$(timestamp)] === 1. Cluster NodeManagers ==="
yarn node -list -states RUNNING

echo
echo "[$(timestamp)] === 2. Application Resource Status ==="
yarn application -status "$APP" | egrep -i 'State|Progress|Running-Containers|Allocated|Pending|Queue'

echo
echo "[$(timestamp)] === 3. Job Overview ==="
mapred job -status "$JOB" | egrep -i 'Job state|map|reduce|Launched|Total|Completed'

echo
echo "[$(timestamp)] === 4. Running Map & Reduce Attempts ==="
echo "Running Maps:"
mapred job -list-attempt-ids "$JOB" MAP running 2>/dev/null || echo "  (none)"
echo "Running Reduces:"
mapred job -list-attempt-ids "$JOB" REDUCE running 2>/dev/null || echo "  (none)"

echo
echo "[$(timestamp)] === 5. Shuffle & Reduce Counters ==="
for C in REDUCE_SHUFFLE_BYTES REDUCE_INPUT_RECORDS FETCH_FAILED FAILED_SHUFFLE; do
  printf "  %-32s" "$C"
  mapred job -counter "$JOB" org.apache.hadoop.mapreduce.TaskCounter "$C" 2>/dev/null || echo "N/A"
done

echo
echo "[$(timestamp)] === 6. Searching Logs for Shuffle / Fetch / Disk / Codec Errors ==="
yarn logs -applicationId "$APP" 2>/dev/null | \
  egrep -i 'FetchFailed|shuffle|Copying|Connection|Refused|NoRoute|space|Snappy|zlib|FSError|FileNotFound|Exception' | \
  tail -n 50 || echo "No major errors detected."

echo
echo "[$(timestamp)] === 7. NodeManager Config & Health Check ==="
for n in $(cat $HADOOP_HOME/etc/hadoop/slaves); do
  echo "--- $n ---"
  ssh -o StrictHostKeyChecking=no ubuntu@$n "
    jps | egrep 'NodeManager|DataNode' || true;
    grep -E 'aux-services|shuffle.class|nodemanager.resource|maximum-allocation|cpu-vcores' -n $HADOOP_HOME/etc/hadoop/yarn-site.xml || true;
    df -h / | tail -1;
    free -m | head -2
  " 2>/dev/null
done

echo
echo "[$(timestamp)] === 8. Shuffle Port Listening (13562 / 8042) ==="
for n in $(cat $HADOOP_HOME/etc/hadoop/slaves); do
  echo "--- $n ---"
  ssh -o StrictHostKeyChecking=no ubuntu@$n "sudo ss -ltnp 2>/dev/null | egrep '13562|8042' || true"
done

echo
echo "[$(timestamp)] === Diagnostics Completed ==="
echo "Inspect the logs above for 'FetchFailed', 'Connection refused', 'SnappyError', or 'No space left on device'."
