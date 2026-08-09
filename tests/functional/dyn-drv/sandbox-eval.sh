#!/usr/bin/env bash

source common.sh

# builder-rpc-v0
requireDaemonNewerThan "2.35pre20260507"

TODO_NixOS

enableFeatures 'dynamic-derivations ca-derivations'
restartDaemon

NIX_BIN_DIR="$(dirname "$(type -p nix)")"
export NIX_BIN_DIR

outPath="$(nix build -L --file ./sandbox-eval.nix --no-link --print-out-paths)"

[[ "$(cat "$outPath/status")" == ok ]]
