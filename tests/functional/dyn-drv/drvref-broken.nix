with import ./config.nix;

# Three broken derivation references. Each one gets its own message, because a
# reader must not learn that a reference is broken from a parse error of a
# derivation that was never a derivation.
let
  buildSubmitting =
    name: command:
    mkDerivation {
      inherit name;

      requiredSystemFeatures = [ "builder-rpc-v0" ];

      buildCommand = ''
        set -e
        set -u

        PATH=${builtins.getEnv "NIX_BIN_DIR"}:$PATH
        export NIX_CONFIG='extra-experimental-features = nix-command ca-derivations dynamic-derivations'

        ${command}
      '';

      __contentAddressed = true;
      outputHashMode = "nar";
      outputHashAlgo = "sha256";
    };

  planners = {
    empty = buildSubmitting "empty.drvref" ''
      : > empty.drvref
      ref="$(nix store add -n empty.drvref ./empty.drvref)"
      nix store submit-output "$ref" out
    '';

    notADerivation = buildSubmitting "not-a-drv.drvref" ''
      mkdir plain
      echo "not a derivation" > plain/file
      plain="$(nix store add --scan -n plain ./plain)"

      echo "$plain" > not-a-drv.drvref
      ref="$(nix store add --scan -n not-a-drv.drvref ./not-a-drv.drvref)"
      nix store submit-output "$ref" out
    '';

    # No `--scan` here. The path is absent, so a scan would refuse to record
    # it as a reference and the planner would fail for the wrong reason.
    absent = buildSubmitting "absent.drvref" ''
      mkdir anchor
      echo anchor > anchor/file
      anchor="$(nix store add -n anchor ./anchor)"
      storeDir="$(dirname "$anchor")"

      echo "$storeDir/00000000000000000000000000000000-absent.drv" > absent.drvref
      ref="$(nix store add -n absent.drvref ./absent.drvref)"
      nix store submit-output "$ref" out
    '';
  };
in
builtins.mapAttrs (_name: planner: {
  inherit planner;
  followed = builtins.outputOf planner.outPath "out";
}) planners
