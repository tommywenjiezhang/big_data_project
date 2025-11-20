#!/usr/bin/env bash
set -euo pipefail

H="${HADOOP_HOME:-/home/ubuntu/hadoop-2.6.5}"
SLAVES_FILE="$H/etc/hadoop/slaves"

# Expected values (adjust if you want different sizing)
EXP_RM_HOST="master"
EXP_NM_MEM="6144"
EXP_NM_VCORES="2"
EXP_MIN_ALLOC="256"
EXP_MAX_ALLOC="6144"
EXP_AUX="mapreduce_shuffle"
EXP_SHUFFLE_CLS="org.apache.hadoop.mapred.ShuffleHandler"

EXP_AM_MB="1024"
EXP_AM_OPTS="-Xmx768m"
EXP_MAP_MB="1024"
EXP_MAP_OPTS="-Xmx768m"
EXP_RED_MB="1536"
EXP_RED_OPTS="-Xmx1152m"
EXP_MAP_VC="1"
EXP_RED_VC="1"

# Helper to extract <value> for a given <name> key from an XML file (simple, robust)
xml_get_val() {
  local file="$1" key="$2"
  awk -v k="$2" '
    BEGIN{RS="</property>"; FS="\n"}
    $0 ~ "<name>"k"</name>" {
      match($0, /<value>([^<]*)<\/value>/, a); if (a[1] != "") print a[1];
    }' "$file"
}

check_node() {
  local node="$1"
  echo "===== $node ====="
  ssh -o StrictHostKeyChecking=no "ubuntu@$node" bash -s <<'REMOTE'
H="${HADOOP_HOME:-/home/ubuntu/hadoop-2.6.5}"
YS="$H/etc/hadoop/yarn-site.xml"
MR="$H/etc/hadoop/mapred-site.xml"
if [ ! -f "\$YS" ]; then echo "MISSING: \$YS"; fi
if [ ! -f "\$MR" ]; then echo "MISSING: \$MR"; fi
REMOTE

  # Pull both files to /tmp for local parsing (avoids remote awk differences)
  scp -q -o StrictHostKeyChecking=no "ubuntu@$node:$H/etc/hadoop/yarn-site.xml" "/tmp/yarn-site.$node.xml" 2>/dev/null || true
  scp -q -o StrictHostKeyChecking=no "ubuntu@$node:$H/etc/hadoop/mapred-site.xml" "/tmp/mapred-site.$node.xml" 2>/dev/null || true

  Y="/tmp/yarn-site.$node.xml"; M="/tmp/mapred-site.$node.xml"
  [ -f "$Y" ] || { echo "  !! yarn-site.xml not present"; echo; return; }
  [ -f "$M" ] || { echo "  !! mapred-site.xml not present"; echo; return; }

  # yarn-site.xml checks
  rmhost=$(xml_get_val "$Y" "yarn.resourcemanager.hostname")
  aux=$(xml_get_val "$Y" "yarn.nodemanager.aux-services")
  shcls=$(xml_get_val "$Y" "yarn.nodemanager.aux-services.mapreduce.shuffle.class")
  nmmem=$(xml_get_val "$Y" "yarn.nodemanager.resource.memory-mb")
  nmvc=$(xml_get_val "$Y" "yarn.nodemanager.resource.cpu-vcores")
  minalloc=$(xml_get_val "$Y" "yarn.scheduler.minimum-allocation-mb")
  maxalloc=$(xml_get_val "$Y" "yarn.scheduler.maximum-allocation-mb")
  ldirs=$(xml_get_val "$Y" "yarn.nodemanager.local-dirs")
  llogs=$(xml_get_val "$Y" "yarn.nodemanager.log-dirs")

  # mapred-site.xml checks
  ammb=$(xml_get_val "$M" "yarn.app.mapreduce.am.resource.mb")
  amopt=$(xml_get_val "$M" "yarn.app.mapreduce.am.command-opts")
  mapmb=$(xml_get_val "$M" "mapreduce.map.memory.mb")
  mapopt=$(xml_get_val "$M" "mapreduce.map.java.opts")
  redmb=$(xml_get_val "$M" "mapreduce.reduce.memory.mb")
  redopt=$(xml_get_val "$M" "mapreduce.reduce.java.opts")
  mapvc=$(xml_get_val "$M" "mapreduce.map.cpu.vcores")
  redvc=$(xml_get_val "$M" "mapreduce.reduce.cpu.vcores")

  # Compare helper
  cmp() { local key="$1" got="$2" exp="$3"; if [ -z "$got" ]; then printf "  !! %-45s %-15s (expected: %s)\n" "$key" "<EMPTY>" "$exp"; elif [ "$got" != "$exp" ]; then printf "  !! %-45s %-15s (expected: %s)\n" "$key" "$got" "$exp"; else printf "  OK %-45s %s\n" "$key" "$got"; fi; }

  echo "  [yarn-site.xml]"
  cmp "yarn.resourcemanager.hostname" "$rmhost" "$EXP_RM_HOST"
  cmp "yarn.nodemanager.aux-services" "$aux" "$EXP_AUX"
  cmp "yarn.nodemanager.aux-services.mapreduce.shuffle.class" "$shcls" "$EXP_SHUFFLE_CLS"
  cmp "yarn.nodemanager.resource.memory-mb" "$nmmem" "$EXP_NM_MEM"
  cmp "yarn.nodemanager.resource.cpu-vcores" "$nmvc" "$EXP_NM_VCORES"
  cmp "yarn.scheduler.minimum-allocation-mb" "$minalloc" "$EXP_MIN_ALLOC"
  cmp "yarn.scheduler.maximum-allocation-mb" "$maxalloc" "$EXP_MAX_ALLOC"
  if [ -z "$ldirs" ]; then echo "  !! yarn.nodemanager.local-dirs is EMPTY"; else echo "  OK yarn.nodemanager.local-dirs               $ldirs"; fi
  if [ -z "$llogs" ]; then echo "  !! yarn.nodemanager.log-dirs is EMPTY"; else echo "  OK yarn.nodemanager.log-dirs                $llogs"; fi

  echo "  [mapred-site.xml]"
  cmp "yarn.app.mapreduce.am.resource.mb" "$ammb" "$EXP_AM_MB"
  cmp "yarn.app.mapreduce.am.command-opts" "$amopt" "$EXP_AM_OPTS"
  cmp "mapreduce.map.memory.mb" "$mapmb" "$EXP_MAP_MB"
  cmp "mapreduce.map.java.opts" "$mapopt" "$EXP_MAP_OPTS"
  cmp "mapreduce.reduce.memory.mb" "$redmb" "$EXP_RED_MB"
  cmp "mapreduce.reduce.java.opts" "$redopt" "$EXP_RED_OPTS"
  cmp "mapreduce.map.cpu.vcores" "$mapvc" "$EXP_MAP_VC"
  cmp "mapreduce.reduce.cpu.vcores" "$redvc" "$EXP_RED_VC"

  echo
}

# Loop slaves
while read -r n; do
  [[ -z "$n" || "$n" =~ ^[[:space:]]*# ]] && continue
  check_node "$n"
done < "$SLAVES_FILE"

