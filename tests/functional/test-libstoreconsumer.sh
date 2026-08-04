#!/usr/bin/env bash

source common.sh

consumer="${_NIX_TEST_BUILD_DIR}/test-libstoreconsumer/test-libstoreconsumer"

drv="$(nix-instantiate simple.nix)"
cat "$drv"
out="$("$consumer" "$drv")"
grep -F "Hello World!" < "$out/hello"

# A consumer of the libstore API must get the statistics of the build.
# `DerivationTrampolineGoal` merges them from the goals of the outputs.
# `nix build --json` cannot cover this fully, because it prints the JSON only
# after a build that succeeds. Thus the statistics of a build that fails have
# no other test.

# Read one `key=value` line from the output of the consumer. The consumer
# prints one block of statistics for each result. This test builds one path,
# and so the output holds one block. Take the first line only, so that the
# arithmetic below still gets one value if a later change adds a second path.
statOf() {
    printf '%s\n' "$2" | sed -n "s/^$1=//p" | head -n 1
}

# `clearStore` removes the derivation as well. Thus instantiate it again, so
# that the consumer has something to build.
clearStore
drv="$(nix-instantiate simple.nix)"
stats="$("$consumer" "$drv" 2>&1 >/dev/null)"
printf '%s\n' "$stats"
[[ "$(statOf status "$stats")" == success ]]
(( "$(statOf timesBuilt "$stats")" >= 1 ))
startTime="$(statOf startTime "$stats")"
stopTime="$(statOf stopTime "$stats")"
(( startTime > 0 ))
(( stopTime >= startTime ))

# The merge happens before the goal reports the failure. Thus a build that
# fails reports its statistics as well.
failingDrv="$(nix-instantiate --expr '
  with import ./config.nix;
  mkDerivation {
    name = "consumer-failing";
    buildCommand = "exit 1";
  }
')"
failStats="$("$consumer" "$failingDrv" 2>&1 >/dev/null)"
printf '%s\n' "$failStats"
# The build must fail. If it does not, this test covers the success path
# again, and the statistics of a failure stay untested.
[[ "$(statOf status "$failStats")" == failure ]]
(( "$(statOf timesBuilt "$failStats")" >= 1 ))
failStartTime="$(statOf startTime "$failStats")"
failStopTime="$(statOf stopTime "$failStats")"
(( failStartTime > 0 ))
(( failStopTime >= failStartTime ))
