with import ./config.nix;

# Each planner here submits a store object that has the name of a derivation
# and is not a derivation that belongs at that path. Each one must fail, and
# each one must fail with its own message.
#
# `submit-drv-any-name.nix` is the case that succeeds.
let
  plannerWith =
    extra: name: command:
    mkDerivation (
      {
        inherit name;

        requiredSystemFeatures = [ "builder-rpc-v0" ];

        buildCommand = ''
          set -e
          set -u

          PATH=${builtins.getEnv "NIX_BIN_DIR"}:$PATH
          export NIX_CONFIG='extra-experimental-features = nix-command ca-derivations dynamic-derivations'

          ${command}
        '';

        outputHashMode = "text";
        outputHashAlgo = "sha256";
      }
      // extra
    );

  planner = plannerWith { __contentAddressed = true; };

  # A derivation that parses, and that names no store path, so it is a
  # candidate for a fixed output. A fixed output must have no reference.
  freeAterm = ''Derive([("out","","r:sha256","")],[],[],"${system}","/bin/sh",["-c","true"],[])'';
in
{
  # The name says derivation, and the content is not one.
  notADerivation = planner "submits-junk" ''
    echo "this is not a derivation" > junk.drv
    path="$(nix store add --mode text -n junk.drv ./junk.drv)"
    nix store submit-output "$path" out
  '';

  # The content is a derivation, and the store path is not the path that the
  # content gives it.
  #
  # The derivation names one input source, so the store path of it covers that
  # reference. `nix store add` runs without `--scan`, so the store object
  # records no reference, and the two paths differ.
  wrongPath = planner "submits-misplaced" ''
    echo "an input source" > source
    src="$(nix store add ./source)"

    printf 'Derive([("out","","r:sha256","")],[],["%s"],"%s","/bin/sh",["-c","true"],[])' \
      "$src" "${system}" > misplaced.drv

    path="$(nix store add --mode text -n misplaced.drv ./misplaced.drv)"
    nix store submit-output "$path" out
  '';

  # **A fixed output keeps the name rule.** `DerivationOutput::CAFixed::path`
  # gives the output the store path that the name of this derivation and the
  # declared hash produce, so the submitted object must be at that path, and
  # so it must carry that name. Only a floating output is free.
  fixedOutput =
    plannerWith
      {
        outputHash = builtins.hashString "sha256" freeAterm;
      }
      "fixed"
      ''
        printf '%s' ${builtins.toJSON freeAterm} > free.drv
        path="$(nix store add --mode text -n free.drv ./free.drv)"
        nix store submit-output "$path" out
      '';
}
