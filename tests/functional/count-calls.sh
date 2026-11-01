#!/usr/bin/env bash

source common.sh

stats="$TEST_ROOT/count-calls-stats.json"
expr='let f = x: x; in f (f 1)'

NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$stats" nix eval --expr "$expr"
jq -e 'has("functions") | not' "$stats"

NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$stats" nix eval --option count-calls true --expr "$expr"
jq -e '.functions | map(select(.name == "f")) | .[0].count == 2' "$stats"

NIX_COUNT_CALLS=1 NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$stats" nix eval --expr "$expr"
jq -e '.functions | map(select(.name == "f")) | .[0].count == 2' "$stats"
