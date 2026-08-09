with import ./config.nix;

# A planner that registers a graph of derivations and submits a *reference* to
# the root of it, rather than the root itself.
#
# The name of this derivation ends in `.drvref` and not in `.drv`, and the
# output ingests as `nar` and not as `text`. Neither is possible when the
# submitted object is the derivation: `derivation-check.cc` makes the name of
# the outer derivation follow the name of the submitted object, and
# `primops.cc` then permits that name only for a text-ingested derivation with
# one output.
#
# The root derivation declares each leaf as an input, so Nix builds every leaf.
# The root reads no leaf output, because that needs a downstream placeholder,
# and `non-trivial-submitted.nix` leaves the same thing out for the same
# reason.
let
  planner = mkDerivation {
    name = "graph.drvref";

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
        storeDir="$(dirname "$drvPath")"
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

      # The reference is one file, and the file holds one store path.
      # `--scan` finds that path in the text and records it as a reference, so
      # the garbage collector keeps the derivation for as long as the
      # reference lives.
      echo "$rootDrv" > graph.drvref
      ref="$(nix store add --scan -n graph.drvref ./graph.drvref)"
      nix store submit-output "$ref" out
    '';

    __contentAddressed = true;
    outputHashMode = "nar";
    outputHashAlgo = "sha256";
  };
in
{
  inherit planner;
  graph = builtins.outputOf planner.outPath "out";
}
