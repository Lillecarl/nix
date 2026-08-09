with import ./config.nix;

# A planner that registers a graph of derivations, and submits the root of that
# graph as its output.
#
# **The name of this derivation says nothing about the name of the root.** The
# planner is `planner`, and the root that it submits is `graph.drv`. The name
# rule of a built output compares the two, so before this change the planner
# had to carry the name of a result that it computes when it runs.
# `text-hashed-output.nix` is the same test under the old rule, and the
# derivation there is named `hello.drv` for that reason.
#
# The output still ingests as `text`, because every derivation ingests as
# `text`, and `checkCAOutput` compares the method that the derivation declares
# with the method of the submitted object.
#
# The root derivation declares each leaf as an input, so Nix builds every leaf.
# The root reads no leaf output, because that needs a downstream placeholder,
# and `non-trivial-submitted.nix` leaves the same thing out for the same
# reason.
let
  planner = mkDerivation {
    name = "planner";

    requiredSystemFeatures = [ "builder-rpc-v0" ];

    buildCommand = ''
      set -e
      set -u

      PATH=${builtins.getEnv "NIX_BIN_DIR"}:$PATH
      export NIX_CONFIG='extra-experimental-features = nix-command ca-derivations dynamic-derivations'

      # Cannot write the placeholder literally, or Nix reads it as the *outer*
      # derivation referring to itself and substitutes the string too soon.
      placeholder=$(nix eval --raw --expr 'builtins.placeholder "out"')

      declare -A drvs=()
      for word in alpha beta; do
        read -r -d "" json <<EOF || true
      {
        "args": ["-c", "echo $word > \$out"],
        "builder": "${shell}",
        "env": {
          "out": "$placeholder",
          "PATH": ${builtins.toJSON path}
        },
        "inputs": { "drvs": {}, "srcs": [] },
        "name": "leaf-$word",
        "outputs": { "out": { "method": "nar", "hashAlgo": "sha256" } },
        "system": "${system}",
        "version": 4
      }
      EOF
        drvPath="$(echo "$json" | nix derivation add)"
        drvs[$word]="$(basename "$drvPath")"
      done

      read -r -d "" json <<EOF || true
      {
        "args": ["-c", "echo the graph built > \$out"],
        "builder": "${shell}",
        "env": {
          "out": "$placeholder",
          "PATH": ${builtins.toJSON path}
        },
        "inputs": {
          "drvs": {
            "''${drvs[alpha]}": { "outputs": ["out"], "dynamicOutputs": {} },
            "''${drvs[beta]}": { "outputs": ["out"], "dynamicOutputs": {} }
          },
          "srcs": []
        },
        "name": "graph",
        "outputs": { "out": { "method": "nar", "hashAlgo": "sha256" } },
        "system": "${system}",
        "version": 4
      }
      EOF
      rootDrv="$(echo "$json" | nix derivation add)"

      # The submitted object is the derivation itself, at the store path that
      # the contents of the derivation give it. Nothing is copied, and nothing
      # names it from a distance.
      nix store submit-output "$rootDrv" out
    '';

    __contentAddressed = true;
    outputHashMode = "text";
    outputHashAlgo = "sha256";
  };
  # **The relaxation reaches one output, and not the whole derivation.** This
  # planner submits a derivation for `out`, and an ordinary store object for
  # `dev`. The name rule still holds `dev` to `two-outputs-dev`.
  twoOutputs = mkDerivation {
    name = "two-outputs";
    outputs = [
      "out"
      "dev"
    ];

    requiredSystemFeatures = [ "builder-rpc-v0" ];

    buildCommand = ''
      set -e
      set -u

      PATH=${builtins.getEnv "NIX_BIN_DIR"}:$PATH
      export NIX_CONFIG='extra-experimental-features = nix-command ca-derivations dynamic-derivations'

      printf 'Derive([("out","","r:sha256","")],[],[],"${system}","/bin/sh",["-c","true"],[])' > small.drv
      drv="$(nix store add --mode text -n small.drv ./small.drv)"
      nix store submit-output "$drv" out

      # `outputHashMode` covers every output, so this one ingests as text too.
      echo "an ordinary output" > devfile
      dev="$(nix store add --mode text -n two-outputs-dev ./devfile)"
      nix store submit-output "$dev" dev
    '';

    __contentAddressed = true;
    outputHashMode = "text";
    outputHashAlgo = "sha256";
  };
in
{
  inherit planner twoOutputs;
  graph = builtins.outputOf planner.outPath "out";
}
