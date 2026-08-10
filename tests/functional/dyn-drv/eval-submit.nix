with import ./config.nix;

# **The evaluator runs inside the build, and writes the graph.** Nothing here
# renders ATerm, and nothing names a store path that the evaluator did not
# make. `submit-drv-any-name.nix` is the same shape with a hand-written
# derivation, and that file is the test of the name rule alone.
#
# Each planner is named `planner-*`, and each root that a planner submits is
# named `eval-graph`. The two names no longer have to agree, so a planner can
# submit a derivation whose name it computes when it runs.
#
# Four graphs, and each one puts a different kind of child under the root:
#
# - `ca`: every derivation floats, and each output path comes from the build.
# - `ia`: every derivation is input-addressed, so each output path is known
#   before the build.
# - `mixed`: an input-addressed root over one floating child. The root is
#   therefore deferred, and the root has no output path until the child is
#   built.
# - `dyn`: the root is a second planner, so `builtins.outputOf` chains three
#   times to reach the file.
let
  # The graph itself. `builtins.toFile` records each store path of the context
  # of this string as a reference, so the whole closure reaches the sandbox as
  # an input of the planner that reads the file.
  graphExpr = builtins.toFile "eval-submit-graph.nix" ''
    let
      floating = {
        __contentAddressed = true;
        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
      };

      base =
        { name, script }:
        {
          inherit name;
          system = "${system}";
          builder = "${shell}";
          args = [ "-c" script ];
          PATH = "${path}";
        };

      # A floating content-addressed derivation, and an input-addressed one.
      ca = args: derivation (base args // floating);
      ia = args: derivation (base args);

      leafA = mk: mk { name = "eval-leaf-a"; script = "echo alpha > $out"; };
      leafB = mk: mk { name = "eval-leaf-b"; script = "echo beta > $out"; };

      # The root reads each child, so each child is a real input and not only
      # a name in the `inputDrvs` field.
      root = mk: a: b: mk {
        name = "eval-graph";
        script = "cat ''${a} ''${b} > $out";
      };
    in
    {
      ca = root ca (leafA ca) (leafB ca);
      ia = root ia (leafA ia) (leafB ia);
      mixed = root ia (leafA ca) (leafB ia);
    }
  '';

  # The build command of the inner planner of the `dyn` graph. It is a file,
  # because a script inside a string inside a string needs an escape for each
  # level, and this way it needs none.
  innerScript = builtins.toFile "eval-submit-inner.sh" ''
    set -e
    set -u

    PATH=${builtins.getEnv "NIX_BIN_DIR"}:$PATH
    export NIX_CONFIG='extra-experimental-features = nix-command ca-derivations dynamic-derivations'

    nix eval --submit out --file ${graphExpr} ca
  '';

  # The second level of the `dyn` graph. The evaluator inside the outer
  # planner reads this file and writes the derivation of a second planner.
  #
  # **`builtins.storePath` is what makes the script an input.** The two paths
  # below are plain text in this file, so the inner evaluator gives them no
  # context of their own. `builtins.storePath` asks the daemon for that
  # context, and the restricted socket answers only because the allowlist
  # permits `EnsurePath`. `sandbox-eval.nix` tests that operation directly.
  innerExpr = builtins.toFile "eval-submit-inner.nix" ''
    {
      inner = derivation {
        name = "planner-inner";
        system = "${system}";
        builder = "${shell}";
        args = [ "-c" ". ''${builtins.storePath "${innerScript}"}" ];
        PATH = "${path}";

        requiredSystemFeatures = [ "builder-rpc-v0" ];

        __contentAddressed = true;
        outputHashMode = "text";
        outputHashAlgo = "sha256";
      };
    }
  '';

  # `outputHashMode = "text"` stays necessary. Every derivation ingests as
  # `text`, and `checkCAOutput` compares the method that the derivation
  # declares with the method of the submitted store object.
  planner =
    { name, file, attr }:
    mkDerivation {
      inherit name;

      requiredSystemFeatures = [ "builder-rpc-v0" ];

      buildCommand = ''
        set -e
        set -u

        PATH=${builtins.getEnv "NIX_BIN_DIR"}:$PATH
        export NIX_CONFIG='extra-experimental-features = nix-command ca-derivations dynamic-derivations'

        # One command evaluates the graph, writes each derivation of it
        # through the restricted socket, and submits the root as the output
        # `out` of this build.
        nix eval --submit out --file ${file} ${attr}
      '';

      __contentAddressed = true;
      outputHashMode = "text";
      outputHashAlgo = "sha256";
    };

  plannerCa = planner {
    name = "planner-ca";
    file = graphExpr;
    attr = "ca";
  };
  plannerIa = planner {
    name = "planner-ia";
    file = graphExpr;
    attr = "ia";
  };
  plannerMixed = planner {
    name = "planner-mixed";
    file = graphExpr;
    attr = "mixed";
  };
  plannerDyn = planner {
    name = "planner-dyn";
    file = innerExpr;
    attr = "inner";
  };
in
{
  inherit
    plannerCa
    plannerIa
    plannerMixed
    plannerDyn
    ;

  graphCa = builtins.outputOf plannerCa.outPath "out";
  graphIa = builtins.outputOf plannerIa.outPath "out";
  graphMixed = builtins.outputOf plannerMixed.outPath "out";

  # Three store objects, one after the other. The output of `plannerDyn` is
  # the derivation of the inner planner. The output of that derivation is the
  # root of the graph, which is a derivation again. The output of the root is
  # the file.
  graphDrvDyn = builtins.outputOf plannerDyn.outPath "out";
  graphDyn = builtins.outputOf (builtins.outputOf plannerDyn.outPath "out") "out";
}
