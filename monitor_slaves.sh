HADOOP_HOME="/home/ubuntu/hadoop-2.6.5"
SLAVES_FILE="$HADOOP_HOME/etc/hadoop/slaves"

while IFS= read -r n; do
  [[ -z "$n" ]] && continue
  [[ "$n" =~ ^# ]] && continue

  echo "Fixing YARN local dirs on $n ..."
  ssh -o ConnectTimeout=3 ubuntu@"$n" '
    sudo mkdir -p /mnt/nm1 /mnt/nm2
    sudo chown -R $(whoami):$(whoami) /mnt/nm1 /mnt/nm2
    sudo chmod 755 /mnt/nm1 /mnt/nm2

    echo "After fix:"
    ls -ld /mnt/nm1 /mnt/nm2
    touch /mnt/nm1/testfile && echo "OK write nm1" && rm /mnt/nm1/testfile
    touch /mnt/nm2/testfile && echo "OK write nm2" && rm /mnt/nm2/testfile
  '
  echo
done < "$SLAVES_FILE"

