#!/usr/bin/env bash
#
# Restart Hadoop cluster and run AvgTripKm job
# - Kills any existing YARN applications
# - Restarts HDFS + YARN
# - Ensures NM local dirs are set up on slaves
# - Verifies NodeManagers and shuffle ports are healthy
# - Cleans old output dir and runs job
#

set -euo pipefail

HADOOP_HOME=${HADOOP_HOME:-/home/ubuntu/hadoop-2.6.5}
SLAVES_FILE="$HADOOP_HOME/etc/hadoop/slaves"
YARN_SITE="$HADOOP_HOME/etc/hadoop/yarn-site.xml"

JAR="$HOME/citibike-mr/target/citibike-mr-1.0-SNAPSHOT.jar"
CLASS="com.wenjie.citibike.AvgTripKm"
INPUT="/input/citibike-may2025"
OUT_PATH="/tmp/output/top10-$(date +%Y%m%d-%H%M)-may2025"

echo "==================== Cleaning up existing YARN applications ===================="

if [[ ! -f "$YARN_SITE" ]]; then
  echo "FATAL: Missing $YARN_SITE; cannot validate YARN shuffle configuration."
  exit 1
fi

echo "Validating NodeManager shuffle configuration..."
aux_services=$(awk -F'[<>]' '/yarn.nodemanager.aux-services/{getline; print $3}' "$YARN_SITE" | tr -d '[:space:]')
shuffle_class=$(awk -F'[<>]' '/yarn.nodemanager.aux-services.mapreduce.shuffle.class/{getline; print $3}' "$YARN_SITE" | tr -d '[:space:]')

if [[ "$aux_services" != "mapreduce_shuffle" ]]; then
  echo "FATAL: yarn.nodemanager.aux-services should be set to mapreduce_shuffle (found: '${aux_services:-<empty>}')."
  exit 1
fi

if [[ "$shuffle_class" != "org.apache.hadoop.mapred.ShuffleHandler" ]]; then
  echo "FATAL: yarn.nodemanager.aux-services.mapreduce.shuffle.class should be org.apache.hadoop.mapred.ShuffleHandler (found: '${shuffle_class:-<empty>}')."
  echo "Reducers will hang during shuffle if this is misconfigured."
  exit 1
fi

echo "Shuffle config looks correct."

# Kill any RUNNING YARN apps from previous runs
# (ignore errors if YARN is not up yet)
if command -v yarn >/dev/null 2>&1; then
  set +e
  yarn application -list 2>/dev/null | \
    awk 'NR>2 && $1 ~ /^application_/ && $6=="RUNNING" {print $1}' | \
    xargs -r -n1 yarn application -kill
  set -e
else
  echo "WARN: yarn command not found; skipping application cleanup"
fi

echo
echo "==================== Stopping HDFS + YARN ===================="

$HADOOP_HOME/sbin/stop-yarn.sh || true
$HADOOP_HOME/sbin/stop-dfs.sh  || true

echo
echo "==================== Ensuring YARN local dirs on all slaves ===================="

while IFS= read -r n; do
  [[ -z "$n" ]] && continue
  [[ "$n" =~ ^# ]] && continue

  echo "---- $n ----"
  ssh -o StrictHostKeyChecking=no ubuntu@"$n" '
    # Create and fix ownership/permissions for YARN local dirs
    sudo mkdir -p /mnt/nm1 /mnt/nm2
    sudo chown -R $(whoami):$(whoami) /mnt/nm1 /mnt/nm2
    sudo chmod 755 /mnt/nm1 /mnt/nm2

    echo "Local dirs:"
    ls -ld /mnt/nm1 /mnt/nm2

    echo "Write test:"
    touch /mnt/nm1/.nm_test && echo "  OK write /mnt/nm1" || echo "  FAIL write /mnt/nm1"
    rm -f /mnt/nm1/.nm_test

    touch /mnt/nm2/.nm_test && echo "  OK write /mnt/nm2" || echo "  FAIL write /mnt/nm2"
    rm -f /mnt/nm2/.nm_test
  '
  echo
done < "$SLAVES_FILE"

echo "==================== Starting HDFS + YARN ===================="

$HADOOP_HOME/sbin/start-dfs.sh
$HADOOP_HOME/sbin/start-yarn.sh

echo
echo "=== Waiting for NameNode to leave safe mode ==="
hdfs dfsadmin -safemode wait
echo "Safe mode is OFF."

echo
echo "==================== Verifying NodeManagers on slaves ===================="

nm_errors=0

while IFS= read -r n; do
  [[ -z "$n" ]] && continue
  [[ "$n" =~ ^# ]] && continue

  echo "=== $n ==="
  ssh -o StrictHostKeyChecking=no ubuntu@"$n" "
    hostname
    jps
    echo
    echo 'Checking for NodeManager process...'
    if pgrep -f NodeManager >/dev/null; then
      echo '  OK: NodeManager running'
      exit 0
    else
      echo '  ERROR: NodeManager NOT running'
      exit 1
    fi
  " || nm_errors=$((nm_errors + 1))

  echo
done < "$SLAVES_FILE"

if [[ $nm_errors -ne 0 ]]; then
  echo "FATAL: One or more NodeManagers are not running. Aborting job."
  exit 1
fi

echo
echo "==================== Verifying NM Web UI + Shuffle ports ===================="

port_errors=0

while IFS= read -r n; do
  [[ -z "$n" ]] && continue
  [[ "$n" =~ ^# ]] && continue

  echo "=== $n ==="

  # NodeManager Web UI (8042)
  if nc -vz "$n" 8042 >/dev/null 2>&1; then
    echo "  OK: 8042 (NodeManager Web UI) reachable"
  else
    echo "  ERROR: 8042 not reachable on $n"
    port_errors=$((port_errors + 1))
  fi

  # Shuffle handler (13562)
  if nc -vz "$n" 13562 >/dev/null 2>&1; then
    echo "  OK: 13562 (Shuffle Handler) reachable"
  else
    echo "  ERROR: 13562 not reachable on $n"
    port_errors=$((port_errors + 1))
  fi

  echo
done < "$SLAVES_FILE"

if [[ $port_errors -ne 0 ]]; then
  echo "FATAL: One or more NodeManager/shuffle ports are not reachable. Aborting job."
  exit 1
fi

echo
echo "==================== Cleaning old output path (if exists) ===================="

if hadoop fs -test -e "$OUT_PATH"; then
  echo "Removing existing output directory: $OUT_PATH"
  hadoop fs -rm -r -f "$OUT_PATH"
else
  echo "No existing output directory at $OUT_PATH"
fi

echo
echo "==================== Running MapReduce Job ===================="

echo "JAR      : $JAR"
echo "CLASS    : $CLASS"
echo "INPUT    : $INPUT"
echo "OUTPUT   : $OUT_PATH"
echo

# Optional: give the job a clear name so it's easy to track/kill later
JOB_NAME="AvgTripKm-$(date +%Y%m%d-%H%M)"

hadoop jar "$JAR" "$CLASS" \
  "$INPUT" "$OUT_PATH"

echo
echo "==================== Job Complete ===================="
echo "Output directory: $OUT_PATH"
echo "You can inspect YARN app list with:"
echo "  yarn application -list -appStates FINISHED,FAILED,KILLED"

