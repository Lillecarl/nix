#!/usr/bin/env bash

source common.sh

# builder-rpc-v0
requireDaemonNewerThan "2.35pre20260507"

TODO_NixOS # can't enable a sandbox feature easily

enableFeatures 'dynamic-derivations ca-derivations'
restartDaemon

NIX_BIN_DIR="$(dirname "$(type -p nix)")"
export NIX_BIN_DIR

expectFailure() {
    local attr="$1"
    local message="$2"
    local out
    out="$(expectStderr 1 nix build -L --file ./submit-drv-broken.nix "$attr" --no-link)"
    echo "$out" | grepQuiet -- "$message"
}

# The submitted object has the name of a derivation, and does not parse as one.
#
# **The store refuses this one before the output check reads it.**
# `LocalStore::registerValidPath` parses every path whose name ends in `.drv`,
# and it then calls `checkInvariants`. So the failure comes from `nix store
# add` in the builder, and the message is the message of the parser.
expectFailure notADerivation "error parsing derivation"

# The submitted object parses, and its store path is not the path that its own
# contents give it.
#
# `checkInvariants` above does not catch this one. That function compares the
# name of the derivation with the name in the path, and it compares each
# output path of an input-addressed derivation. The derivation here has a
# floating content-addressed output, so it has no output path to compare, and
# the name agrees. Only a re-computation of the whole store path finds it.
expectFailure wrongPath "which is a derivation that belongs at"

# A fixed output keeps the name rule, because the store path of a fixed output
# comes from the name of the derivation that declares it.
expectFailure fixedOutput "was named 'free.drv', expected 'fixed'"
