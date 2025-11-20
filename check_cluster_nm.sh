#!/usr/bin/env bash
#
# Check NodeManager status, port connectivity, and memory settings for all workers.
#
# Run from master node:
#   ./check_cluster_nm.sh
#

HADOOP_HOME=${HADOOP_HOME:-/home/ubuntu/hadoop-2.6.5}
SLAVES_FILE="$HADOOP_HOME/etc/hadoop/slaves"

YARN_SITE="$HADOOP_HOME/etc/hadoop/yarn-site.xml"

echo "Using slaves file: $SLAVES_FILE"
echo

for n in $(cat "$SLAVES_FILE"); do
  echo "=============== $n ==============="

  # 0. Ensure NM log/local dirs exist on remote
  echo "-- Ensuring log + local dirs exist on $n --"
  ssh -o StrictHostKeyChecking=no ubuntu@$n "
    HADOOP_HOME='$HADOOP_HOME'
    mkdir -p \"\$HADOOP_HOME/logs\" \
             \"\$HADOOP_HOME/yarn/local\" \
             \"\$HADOOP_HOME/yarn/logs\"
    chown -R ubuntu:ubuntu \"\$HADOOP_HOME\"
  " || echo "WARN: could not ensure dirs on $n"

  echo

  # 1. Basic host check
  echo "-- Hostname & JPS --"
  ssh -o StrictHostKeyChecking=no ubuntu@$n "hostname; jps" || echo "SSH FAILED"

  echo

  # 2. NodeManager Web UI (port 8042)
  echo "-- Port 8042 (NodeManager Web UI) --"
  nc -z -w 3 $n 8042 && echo "OK: 8042 open" || echo "FAIL: 8042 not reachable"

  echo

  # 3. Shuffle handler (Port 13562)
  echo "-- Port 13562 (Shuffle Handler) --"
  nc -z -w 3 $n 13562 && echo "OK: Shuffle port open" || echo "FAIL: Shuffle port unreachable"

  echo

  # 4. Memory settings check
  echo "-- Memory Settings (from yarn-site.xml on remote) --"
  ssh -o StrictHostKeyChecking=no ubuntu@$n "
    grep -A1 'yarn.nodemanager.resource.memory-mb' '$YARN_SITE' 2>/dev/null;
    echo;
    grep -A1 'yarn.scheduler.maximum-allocation-mb' '$YARN_SITE' 2>/dev/null;
  " || echo "Could not read yarn-site.xml on $n"

  echo "====================================="
  echo
done
