#!/usr/bin/env bash

source common.sh

# builder-rpc-v0
requireDaemonNewerThan "2.35pre20260507"

TODO_NixOS

enableFeatures 'dynamic-derivations ca-derivations'
restartDaemon

NIX_BIN_DIR="$(dirname "$(type -p nix)")"
export NIX_BIN_DIR

# Each planner succeeds. The reference is only read when something follows it.
nix build -L --file ./drvref-broken.nix empty.planner --no-link
nix build -L --file ./drvref-broken.nix notADerivation.planner --no-link
nix build -L --file ./drvref-broken.nix absent.planner --no-link

expectStderr 1 nix build -L --file ./drvref-broken.nix empty.followed --no-link \
    | grepQuiet "derivation reference .* is empty"

expectStderr 1 nix build -L --file ./drvref-broken.nix notADerivation.followed --no-link \
    | grepQuiet "which is not a derivation"

expectStderr 1 nix build -L --file ./drvref-broken.nix absent.followed --no-link \
    | grepQuiet "which no store holds"
