#!/usr/bin/env bash

source common.sh

# builder-rpc-v0
requireDaemonNewerThan "2.35pre20260507"

TODO_NixOS # can't enable a sandbox feature easily

enableFeatures 'dynamic-derivations ca-derivations'
restartDaemon

NIX_BIN_DIR="$(dirname "$(type -p nix)")"
export NIX_BIN_DIR

# `nix eval --submit` writes the whole graph through the restricted socket and
# submits the root, so each planner runs one command.
#
# The three assertions below repeat for each kind of child, because the kind of
# the child decides when the store knows the output path of the root:
#
# - a floating child gives the root no path until the child is built;
# - an input-addressed child gives the root a path from a hash of the inputs;
# - a floating child under an input-addressed root defers the root.

# `$1` is the attribute of the planner, `$2` is the attribute of the output of
# the graph, and `$3` is the name that the planner submits.
checkGraph() {
    local planner="$1" graph="$2" rootName="$3" drvPath outPath

    drvPath="$(nix build -L --file ./eval-submit.nix "$planner" --no-link --print-out-paths)"

    # The planner is named `planner-*`, and the output carries the name that
    # the evaluator gave the root. The name rule no longer ties the two.
    echo "$drvPath" | grep -- "-$rootName\.drv\$"

    # The output is a derivation that Nix reads, and not a store object that
    # holds the bytes of one. `nix derivation show` reads it without a build.
    [[ "$(nix derivation show "$drvPath" | jq -r '.derivations[].name')" = "$rootName" ]]

    # Two leaves reached the store as inputs of the root, and the evaluator
    # wrote each one. Sort by the name, because the hash comes first and gives
    # no order.
    mapfile -t leaves < <(nix derivation show "$drvPath" | jq -r '.derivations[].inputs.drvs | keys | .[] | sub("^[^-]*-"; "")' | sort)
    [[ ${#leaves[@]} -eq 2 ]]
    [[ "${leaves[0]}" = eval-leaf-a.drv ]]
    [[ "${leaves[1]}" = eval-leaf-b.drv ]]

    # Both commands resolve the deriving path and then read the result as a
    # derivation, and neither one goes through the goal that builds it.
    nix derivation show --file ./eval-submit.nix "$graph" | jq -e '.derivations | length == 1' > /dev/null
    nix build --dry-run --json --file ./eval-submit.nix "$graph" > /dev/null

    # The graph builds, and the root read each child.
    outPath="$(nix build -L --file ./eval-submit.nix "$graph" --no-link --print-out-paths)"
    [[ "$(cat "$outPath")" = "$(printf 'alpha\nbeta')" ]]
}

# Every derivation of the graph floats.
checkGraph plannerCa graphCa eval-graph

# Every derivation of the graph is input-addressed. The evaluator computes each
# output path from a hash of the derivation modulo its inputs, so the graph
# needs no realisation to name its outputs.
checkGraph plannerIa graphIa eval-graph

# An input-addressed root over one floating child. The root is deferred.
checkGraph plannerMixed graphMixed eval-graph

# **The dynamic graph, over three levels.** The outer planner submits the
# derivation of a second planner, that planner submits the root of a graph, and
# the root gives the file. `builtins.outputOf` follows each level.
innerDrv="$(nix build -L --file ./eval-submit.nix plannerDyn --no-link --print-out-paths)"
echo "$innerDrv" | grep -- "-planner-inner\.drv\$"
[[ "$(nix derivation show "$innerDrv" | jq -r '.derivations[].name')" = planner-inner ]]

# The inner planner asks for the same system feature, because it submits too.
nix derivation show "$innerDrv" | jq -e '.derivations[].env.requiredSystemFeatures == "builder-rpc-v0"' > /dev/null

# `builtins.storePath` inside the outer sandbox gave the script of the inner
# planner a context, so the script is an input of the inner planner and the
# garbage collector keeps it.
nix derivation show "$innerDrv" | jq -e '.derivations[].inputs.srcs | length == 1' > /dev/null

# The second level gives the root of the graph, which is a derivation again.
graphDrv="$(nix build -L --file ./eval-submit.nix graphDrvDyn --no-link --print-out-paths)"
echo "$graphDrv" | grep -- "-eval-graph\.drv\$"

# The third level gives the file.
dynOut="$(nix build -L --file ./eval-submit.nix graphDyn --no-link --print-out-paths)"
[[ "$(cat "$dynOut")" = "$(printf 'alpha\nbeta')" ]]

# **The evaluator gives the same derivation as a hand-written one.** The `ca`
# graph and the `dyn` graph reach the same root through different routes, so
# the two store paths agree.
caDrv="$(nix build -L --file ./eval-submit.nix plannerCa --no-link --print-out-paths)"
[[ "$caDrv" = "$graphDrv" ]]

# `--submit` gives no output of its own.
expectStderr 1 nix eval --submit out --raw --file ./eval-submit.nix plannerCa \
    | grepQuiet "takes none of"
