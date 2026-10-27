#!/bin/bash
# diagnose.sh [bun]: like repro.sh's aot case, but traces the process's memfd_create and mmap calls
# with tracefs while CRIU injects into it, to show the error mmap returns.
set -eu
BUN=${1:-bun-45631}
cd "$(dirname "$0")"
T=/sys/kernel/tracing
[ -e $T/trace ] || mount -t tracefs nodev $T
[ -x hello-aot ] || "$BUN" build --compile --aot hello.ts --outfile hello-aot >/dev/null 2>&1
PORT=5009 ./hello-aot </dev/null >/dev/null 2>&1 &
pid=$!
sleep 2
events="sys_enter_memfd_create sys_exit_memfd_create sys_enter_mmap sys_exit_mmap"
echo > $T/trace
# Filtered by name, because tracefs sees host PIDs, not the container's.
for e in $events; do
  echo 'comm == "hello-aot"' > $T/events/syscalls/$e/filter
  echo 1 > $T/events/syscalls/$e/enable
done
rm -rf img-diag; mkdir img-diag
criu dump -t "$pid" -D img-diag --shell-job -o dump.log 2>/dev/null || echo "criu exit $?"
for e in $events; do
  echo 0 > $T/events/syscalls/$e/enable
  echo 0 > $T/events/syscalls/$e/filter
done
grep -v '^#' $T/trace | sed 's/^ *//' || echo "no calls traced"
kill "$pid" 2>/dev/null || true
