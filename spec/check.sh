#!/bin/sh
# Model-check every spec. The *_original configs model the pre-fix code and
# must find a violation; everything else must pass.
set -u
JAR=${TLA2TOOLS:-/opt/tla/tla2tools.jar}
cd "$(dirname "$0")"
fail=0
run() {   # module config expect(pass|fail)
    out=$(java -XX:+UseParallelGC -cp "$JAR" tlc2.TLC -deadlock -workers auto \
              -metadir /tmp/tlc-$$ -config "$2" "$1" 2>&1)
    if echo "$out" | grep -q "No error has been found"; then got=pass; else got=fail; fi
    what=$(echo "$out" | grep -o "Invariant [A-Za-z]* is violated\|Temporal properties were violated\|distinct states found" | head -1)
    if [ "$got" = "$3" ]; then echo "ok    $2 ($what)"; else echo "WRONG $2: expected $3, got $got"; echo "$out" | tail -30; fail=1; fi
    rm -rf /tmp/tlc-$$
}
run FrameSync    FrameSync.cfg               pass
run FrameSync    FrameSync_original.cfg      fail
run ApuHandshake ApuHandshake.cfg            pass
run ApuHandshake ApuHandshake_live.cfg       pass
run ApuHandshake ApuHandshake_original.cfg   fail
run GameFSM      GameFSM.cfg                 pass
exit $fail
