with import ./config.nix;

# The evaluator, run inside a `builder-rpc-v0` sandbox.
#
# `builtins.storePath` and `builtins.appendContext` are the two primops that
# attach store context, and each one makes exactly one call to the daemon:
# `ensurePath`. The restricted builder answers that call by asserting that the
# path is in the input closure of this build, or that this builder added the
# path. It substitutes nothing.
#
# `path` in `config.nix` is coreutils alone, so this builder uses no other
# tool. A `[[ ... ]]` test replaces `grep`.
mkDerivation {
  name = "sandbox-eval";

  requiredSystemFeatures = [ "builder-rpc-v0" ];

  buildCommand = ''
    set -e
    set -u

    PATH=${builtins.getEnv "NIX_BIN_DIR"}:$PATH
    export NIX_CONFIG='extra-experimental-features = nix-command ca-derivations dynamic-derivations'

    # A store object that this builder made. The restricted store records each
    # path that this builder adds, so `isAllowed` accepts this one.
    mkdir mine
    echo "made in the sandbox" > mine/file
    mine="$(nix store add --scan -n mine ./mine)"
    storeDir="$(dirname "$mine")"

    # `builtins.appendContext` calls `ensurePath` with no guard in front of it,
    # so this line works only when the allowlist permits the operation. It is
    # the load-bearing assertion of this test.
    context="$(nix eval --impure --raw --expr "
      builtins.head (builtins.attrNames (builtins.getContext (
        builtins.appendContext \"ok\" { \"$mine\" = { path = true; }; })))
    ")"
    if [[ "$context" != "$mine" ]]; then
      echo "appendContext gave '$context', expected '$mine'" >&2
      exit 1
    fi

    # `builtins.storePath` reaches the same operation. It skips the call when
    # the evaluator already has the path mounted, so this line can pass for a
    # second reason. It is here to show that the primop works, and not to show
    # which of the two reasons applied.
    stored="$(nix eval --impure --raw --expr "builtins.storePath \"$mine\"")"
    if [[ "$stored" != "$mine" ]]; then
      echo "storePath gave '$stored', expected '$mine'" >&2
      exit 1
    fi

    # A path that this builder never added, and that is no input of this
    # derivation. The restricted store refuses it. `appendContext` does not
    # touch the file system, so the path needs no file behind it.
    outside="$storeDir/00000000000000000000000000000000-not-in-this-closure"
    if nix eval --impure --raw --expr "
      builtins.appendContext \"no\" { \"$outside\" = { path = true; }; }
    " > /dev/null 2> refused; then
      echo "appendContext accepted a path outside the closure" >&2
      exit 1
    fi
    if [[ "$(cat refused)" != *"cannot substitute unknown path"* ]]; then
      echo "unexpected message for a path outside the closure:" >&2
      cat refused >&2
      exit 1
    fi

    mkdir result
    echo ok > result/status
    out="$(nix store add -n sandbox-eval ./result)"
    nix store submit-output "$out" out
  '';

  __contentAddressed = true;
  outputHashMode = "nar";
  outputHashAlgo = "sha256";
}
