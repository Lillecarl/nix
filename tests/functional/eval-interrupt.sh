#!/usr/bin/env bash

source common.sh

# A pure evaluation prints nothing until it finishes, so a signal must stop it
# from inside the evaluator. SIGTERM, because a non-interactive shell starts
# background jobs with SIGINT ignored.

out="$TEST_ROOT/eval-interrupt.out"

nix eval --expr "
  let
    sum = builtins.foldl' (a: b: a + b) 0;
    range = n: builtins.genList (x: x) n;
  in
  builtins.trace \"started\" (builtins.foldl' (a: _: a + sum (range 1000)) 0 (range 1000000))
" > "$out" 2>&1 &
pid=$!

for _ in $(seq 100); do
    grepQuiet started "$out" && break
    sleep 0.1
done
grepQuiet started "$out" || fail "nix eval did not start"

kill -TERM "$pid"

for _ in $(seq 100); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
done
if kill -0 "$pid" 2>/dev/null; then
    kill -KILL "$pid"
    fail "nix eval did not stop within 10 seconds of SIGTERM"
fi

if wait "$pid"; then
    fail "nix eval succeeded after SIGTERM"
fi
grepQuiet "interrupted by the user" "$out"
