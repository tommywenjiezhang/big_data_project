#!/bin/bash

HADOOP_HOME="/home/ubuntu/hadoop-2.6.5"
SLAVE_FILE="$HADOOP_HOME/etc/hadoop/slaves"

echo "=== Hadoop Slave Node Loop Script ==="
echo "Using slave list: $SLAVE_FILE"
echo ""

# Read each slave node line-by-line
while IFS= read -r n; do
    # Skip empty lines or comments
    [[ -z "$n" ]] && continue
    [[ "$n" =~ ^# ]] && continue

    echo "---------------------------------------"
    echo "Processing node: $n"
    echo "---------------------------------------"

    ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no ubuntu@"$n" "
        echo '>>> Node: $n'

        # ===========================
        #  ACTIONS TO PERFORM
        #  (edit this section)
        # ===========================

        echo 'Checking NodeManager...'
        pgrep -f NodeManager >/dev/null && echo '  OK: NodeManager running' || echo '  ERROR: NodeManager NOT running'

        echo 'Checking DataNode...'
        pgrep -f DataNode >/dev/null && echo '  OK: DataNode running' || echo '  ERROR: DataNode NOT running'

        echo 'Checking YARN local dirs...'
        ls -ld /mnt/nm1 2>/dev/null || echo '  MISSING: /mnt/nm1'
        ls -ld /mnt/nm2 2>/dev/null || echo '  MISSING: /mnt/nm2'

        echo 'Testing write permissions...'
        touch /mnt/nm1/testfile 2>/dev/null && echo '  OK: write to /mnt/nm1' || echo '  ERROR: cannot write /mnt/nm1'
        rm -f /mnt/nm1/testfile

        touch /mnt/nm2/testfile 2>/dev/null && echo '  OK: write to /mnt/nm2' || echo '  ERROR: cannot write /mnt/nm2'
        rm -f /mnt/nm2/testfile

        echo 'Disk usage:'
        df -h /mnt | tail -1

        echo 'Health check done.'
    "

    echo ""
done < "$SLAVE_FILE"
