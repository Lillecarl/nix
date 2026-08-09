#!/usr/bin/env bash

source common.sh

# builder-rpc-v0
requireDaemonNewerThan "2.35pre20260507"

TODO_NixOS

enableFeatures 'dynamic-derivations ca-derivations'
restartDaemon

NIX_BIN_DIR="$(dirname "$(type -p nix)")"
export NIX_BIN_DIR

# The planner alone. Its output is the reference, and not a derivation.
refPath="$(nix build -L --file ./submit-drvref.nix planner --no-link --print-out-paths)"

echo "$refPath" | grepQuiet -- "-graph.drvref\$"

# The reference names the root derivation, and holds nothing else.
refTarget="$(cat "$refPath")"
echo "$refTarget" | grepQuiet -- "-graph.drv\$"
[[ "$(wc -l < "$refPath")" -eq 1 ]]

# `--scan` recorded the derivation as a reference of the reference.
nix path-info "$refPath" --json --json-format 2 \
    | jq -r '.info[].references | .[]' \
    | grepQuiet -- "-graph.drv\$"

# The trampoline follows the reference, and builds the graph behind it.
outPath="$(nix build -L --file ./submit-drvref.nix graph --no-link --print-out-paths)"

[[ "$(cat "$outPath")" == "the graph built" ]]

# Each leaf built, because the root declares each one as an input. `nix
# derivation show` wraps the map in `derivations`, beside a `version` field.
inputDrvs="$(nix derivation show "$refTarget" | jq -r '.derivations[].inputs.drvs | keys | .[]')"

echo "$inputDrvs" | grepQuiet -- "-leaf-alpha.drv\$"
echo "$inputDrvs" | grepQuiet -- "-leaf-beta.drv\$"
