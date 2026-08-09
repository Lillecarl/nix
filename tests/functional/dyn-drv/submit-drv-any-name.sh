#!/usr/bin/env bash

source common.sh

# builder-rpc-v0
requireDaemonNewerThan "2.35pre20260507"

TODO_NixOS # can't enable a sandbox feature easily

enableFeatures 'dynamic-derivations ca-derivations'
restartDaemon

NIX_BIN_DIR="$(dirname "$(type -p nix)")"
export NIX_BIN_DIR

# The planner submits a derivation whose name is not the name of the planner.
drvPath="$(nix build -L --file ./submit-drv-any-name.nix planner --no-link --print-out-paths)"

# The output is the root derivation, at its own store path, under its own name.
echo "$drvPath" | grep -- "-graph\.drv$"

# The output is a derivation that Nix reads, and not a store object that
# happens to hold the bytes of one. The store path of a derivation comes from
# the contents of that derivation, so `nix derivation add` of the same
# derivation gives the same path back.
[[ "$(nix derivation show "$drvPath" | jq -r '.derivations | keys | .[]')" = "$(basename "$drvPath")" ]]
[[ "$(nix derivation show "$drvPath" | jq -r '.derivations[].name')" = graph ]]

# Every leaf reached the store as an input of the root. Sort by the name and
# not by the whole base name, because the hash comes first and gives no order.
mapfile -t leaves < <(nix derivation show "$drvPath" | jq -r '.derivations[].inputs.drvs | keys | .[] | sub("^[^-]*-"; "")' | sort)
[[ ${#leaves[@]} -eq 2 ]]
[[ "${leaves[0]}" = leaf-alpha.drv ]]
[[ "${leaves[1]}" = leaf-beta.drv ]]

# **These two commands are the reason the submitted object stays a real
# derivation.** Each one resolves the deriving path and then reads the result
# as a derivation, and neither one goes through the goal that builds it. An
# indirection that only the goal follows breaks both.
nix derivation show --file ./submit-drv-any-name.nix graph | jq -e '.derivations | length == 1' > /dev/null
nix build --dry-run --json --file ./submit-drv-any-name.nix graph > /dev/null

# The graph builds through `builtins.outputOf`.
outPath="$(nix build -L --file ./submit-drv-any-name.nix graph --no-link --print-out-paths)"
[[ "$(cat "$outPath")" = "the graph built" ]]

# The relaxation reaches the output that is a derivation, and the name rule
# still holds the other output of the same derivation.
twoOutputs="$(nix build -L --file ./submit-drv-any-name.nix twoOutputs --no-link --print-out-paths)"
[[ "$(echo "$twoOutputs" | wc -l)" -eq 2 ]]
echo "$twoOutputs" | grep -- "-small\.drv$"
echo "$twoOutputs" | grep -- "-two-outputs-dev$"
