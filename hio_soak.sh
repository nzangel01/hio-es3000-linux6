#!/bin/bash
# hio soak: write deterministic pseudo-random data, drop caches, read back, compare. Run as root.
# usage: sudo ./hio_soak.sh [minutes=480] [gib_per_round=32] [dir=/mnt/huawei]
M=${1:-480}; G=${2:-32}; DIR=${3:-/mnt/huawei}; LOG=$HOME/hio_soak.log
SZ=$((G*1024*1024*1024)); END=$((SECONDS+M*60)); r=0; bad=0
gen(){ openssl enc -aes-128-ctr -K "$(printf '%032x' "$1")" -iv 00000000000000000000000000000000 -nosalt </dev/zero 2>/dev/null | head -c "$SZ"; }
log(){ echo "$(date '+%F %T') $*" | tee -a "$LOG"; }
log "start: ${M}min, ${G}GiB/round, dir=$DIR, errs-before=$(dmesg | grep -c -i -E 'hio(err|warn).*(timeout|fail)')"
while [ $SECONDS -lt $END ]; do
  r=$((r+1)); F=$DIR/soak.bin
  w0=$SECONDS; gen $r | dd of=$F bs=1M oflag=direct conv=fsync iflag=fullblock status=none; w=$((SECONDS-w0))
  sync; echo 3 > /proc/sys/vm/drop_caches
  r0=$SECONDS; dd if=$F bs=1M iflag=direct status=none | cmp - <(gen $r) && ok=OK || { ok=MISMATCH; bad=$((bad+1)); }; rd=$((SECONDS-r0))
  log "round $r: write ${w}s ($((G*1024/(w+1))) MB/s) read+cmp ${rd}s => $ok  df=$(df -h --output=pcent $DIR | tail -1)"
  [ "$ok" = OK ] && rm -f $F
done
log "done: rounds=$r mismatches=$bad hio-errors-in-dmesg:"; dmesg | grep -i -E 'hio(err|warn)' | grep -v 'bm operationstatus' | tail -5 | tee -a "$LOG"
