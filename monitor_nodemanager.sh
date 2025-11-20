#!/bin/bash

HADOOP_HOME="/home/ubuntu/hadoop-2.6.5"
SLAVE_LIST="$HADOOP_HOME/etc/hadoop/slaves"

echo "===== Cluster Health Check ====="
echo "Checking nodes from: $SLAVE_LIST"
echo ""

for n in $(cat $SLAVE_LIST); do
  echo "---- Checking $n ----"

  ssh -o ConnectTimeout=2 ubuntu@$n "
    echo \"$n: Checking NodeManager...\"
    if pgrep -f NodeManager > /dev/null; then
       echo \"[OK] NodeManager running\"
    else
       echo \"[ALERT] NodeManager NOT running\"
    fi

    echo \"$n: Checking DataNode...\"
    if pgrep -f DataNode > /dev/null; then
       echo \"[OK] DataNode running\"
    else
       echo \"[ALERT] DataNode NOT running\"
    fi

    DISK=\$(df -h / | awk 'NR==2{print \$5}')
    echo \"$n: Disk usage: \$DISK\"

    echo \"$n: Checking for OOM killer...\"
    dmesg | grep -i 'killed process' | tail -1

    echo \"$n: Checking NodeManager unhealthy...\"
    grep -i unhealthy $HADOOP_HOME/logs/yarn-ubuntu-nodemanager-\$(hostname).log | tail -1

    echo \"$n: Checking for SIGTERM / exitCode=143...\"
    grep -i 'SIGTERM' $HADOOP_HOME/logs/yarn-ubuntu-nodemanager-\$(hostname).log | tail -1
    grep -i 'exitCode=143' $HADOOP_HOME/logs/yarn-ubuntu-nodemanager-\$(hostname).log | tail -1

    echo \"----\"
  "

  echo
done
