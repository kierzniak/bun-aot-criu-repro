#!/bin/bash
# repro.sh [bun]: run as root on Linux with CRIU installed. bun defaults to bun-45631 (bunx bun-pr 45631).
# Builds hello.ts three ways, starts each, checkpoints it with `criu dump`, and exits 1 if any dump fails.
set -eu
BUN=${1:-bun-45631}
cd "$(dirname "$0")"
echo "$(uname -m), kernel $(uname -r), $(criu --version | head -1), bun $("$BUN" --revision)"
"$BUN" build --compile hello.ts --outfile hello-compile >/dev/null
"$BUN" build --compile --aot hello.ts --outfile hello-aot >/dev/null 2>&1
failed=0
try() { # name port cmd...
  local name=$1 port=$2; shift 2
  rm -rf "img-$name"; mkdir "img-$name"
  PORT=$port setsid "$@" </dev/null >/dev/null 2>&1 &
  sleep 2
  local pid; pid=$(ss -ltnpH "sport = :$port" | sed 's/.*pid=\([0-9]*\).*/\1/')
  curl -sf "localhost:$port" >/dev/null
  if criu dump -t "$pid" -D "img-$name" --shell-job -v4 -o dump.log 2>/dev/null; then
    echo "$name: dump OK"
  else
    echo "$name: dump FAILED (criu exit $?)"; grep -B1 Error "img-$name/dump.log"; kill "$pid"; failed=1
  fi
}
try bun 5001 "$BUN" hello.ts
try compile 5002 ./hello-compile
try aot 5003 ./hello-aot
exit $failed
