#!/usr/bin/env bash
#
# Check NodeManager logs on every worker node.
#

HADOOP_HOME=${HADOOP_HOME:-/home/ubuntu/hadoop-2.6.5}
SLAVES_FILE="$HADOOP_HOME/etc/hadoop/slaves"

echo "Using slaves file: $SLAVES_FILE"
echo

for n in $(cat "$SLAVES_FILE"); do
  echo "=============== $n ==============="

  ssh -o StrictHostKeyChecking=no ubuntu@$n << 'EOF'
HADOOP_HOME=/home/ubuntu/hadoop-2.6.5

echo "-- Hostname & JPS --"
hostname
jps || echo "jps failed"

echo
echo "-- NodeManager .out file(s) --"
ls -1 "$HADOOP_HOME/logs"/yarn-*-nodemanager-*.out 2>/dev/null || echo "No NM .out file found"
echo
for f in "$HADOOP_HOME"/logs/yarn-*-nodemanager-*.out; do
  [ -f "$f" ] || continue
  echo "---- tail: \$(basename "$f") ----"
  tail -n 50 "$f"
  echo
done

echo
echo "-- NodeManager .log file(s) --"
ls -1 "$HADOOP_HOME/logs"/yarn-*-nodemanager-*.log 2>/dev/null || echo "No NM .log file found"
echo
for f in "$HADOOP_HOME"/logs/yarn-*-nodemanager-*.log; do
  [ -f "$f" ] || continue
  echo "---- tail: \$(basename "$f") ----"
  tail -n 50 "$f"
  echo
done

echo
echo "-- Disk usage --"
df -h

echo
echo "-- NM local dirs --"
ls -ld "$HADOOP_HOME/yarn/local" "$HADOOP_HOME/yarn/logs" 2>/dev/null || echo "NM local dirs missing"

echo
EOF

  echo "====================================="
  echo
done
