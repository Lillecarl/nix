with import ./config.nix;

mkDerivation {
  name = "sandbox-eval";

  requiredSystemFeatures = [ "builder-rpc-v0" ];

  buildCommand = ''
    set -e
    set -u

    PATH=${builtins.getEnv "NIX_BIN_DIR"}:$PATH
    export NIX_CONFIG='extra-experimental-features = nix-command ca-derivations dynamic-derivations'

    mkdir mine
    echo "made in the sandbox" > mine/file
    mine="$(nix store add -n mine ./mine)"

    # appendContext always calls ensurePath
    context="$(nix eval --impure --raw --expr "
      builtins.head (builtins.attrNames (builtins.getContext (
        builtins.appendContext \"\" { \"$mine\" = { path = true; }; })))
    ")"
    [[ "$context" == "$mine" ]]

    [[ "$(nix eval --impure --raw --expr "builtins.storePath \"$mine\"")" == "$mine" ]]

    # A path outside the closure of this build is still refused
    outside="$(dirname "$mine")/00000000000000000000000000000000-outside"
    if nix eval --impure --raw --expr "
      builtins.appendContext \"\" { \"$outside\" = { path = true; }; }
    " 2> refused; then
      echo "appendContext accepted a path outside the closure" >&2
      exit 1
    fi
    [[ "$(cat refused)" == *"cannot substitute unknown path"* ]]

    mkdir result
    echo ok > result/status
    nix store submit-output "$(nix store add -n sandbox-eval ./result)" out
  '';

  __contentAddressed = true;
  outputHashMode = "nar";
  outputHashAlgo = "sha256";
}
