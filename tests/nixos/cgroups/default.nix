{ nixpkgs, ... }:

{
  name = "cgroups";

  nodes = {
    host =
      { config, pkgs, ... }:
      {
        virtualisation.additionalPaths = [ pkgs.stdenvNoCC ];
        environment.systemPackages = [ pkgs.jq ];
        nix.extraOptions = ''
          extra-experimental-features = nix-command auto-allocate-uids cgroups
          extra-system-features = uid-range
        '';
        nix.settings.use-cgroups = true;
        nix.nixPath = [ "nixpkgs=${nixpkgs}" ];
      };
  };

  testScript =
    { nodes }:
    ''
      start_all()

      host.wait_for_unit("multi-user.target")

      # A build that finishes must report its timing and its CPU time to the
      # client. The builder reads the CPU time from the cgroup of the build.
      # `DerivationTrampolineGoal` then merges the fields from the goals of
      # the outputs. Without the merge the client gets the default values,
      # and `nix build --json` shows no such field.
      #
      # This test is the only place that covers the whole path. A unit test
      # cannot make a true cgroup, and the functional tests have no root.
      host.succeed(
          "NIX_REMOTE=daemon nix build --auto-allocate-uids --no-link --json "
          "--file ${./resource-usage.nix} > /tmp/resource-usage.json"
      )
      host.succeed("cat /tmp/resource-usage.json >&2")
      host.succeed(
          "jq --exit-status '.[0] | "
          "(.startTime > 0) and (.stopTime >= .startTime) and "
          "has(\"cpuUser\") and has(\"cpuSystem\") and (.cpuUser > 0)"
          "' /tmp/resource-usage.json"
      )

      # The build allocates approximately 64 MiB. Thus `memoryPeak` must be
      # more than 32 MiB. A default value or a wrong file gives a smaller
      # number, and the test fails.
      #
      # `memory.swap.peak` needs Linux 6.5 or later. Thus `memorySwapPeak`
      # can be absent. The machine has no swap, and so the value must be
      # zero where the kernel does report it.
      host.succeed(
          "jq --exit-status '.[0] | "
          "has(\"memoryPeak\") and (.memoryPeak > 33554432) and "
          "((has(\"memorySwapPeak\") | not) or (.memorySwapPeak == 0))"
          "' /tmp/resource-usage.json"
      )

      # This test covers a build that succeeds only. A build that fails
      # reports `memoryPeak` as well, because the merge happens before the
      # goal reports the failure. No test here can show that.
      # `nix build --json` prints the JSON after a build that succeeds only:
      # `Installable::build()` throws first, and `BuiltPathWithResult` models
      # successful outputs alone. The unit test
      # `BuildResultMergeBuildStats.keepsFailureAndTakesMemory` covers the
      # merge for a result that reports a failure.

      # Nix did not build this path a second time, because it is already
      # valid. Thus the result must hold no field of a build. Without this
      # assertion a merge that always writes a number passes the test above.
      host.succeed(
          "NIX_REMOTE=daemon nix build --auto-allocate-uids --no-link --json "
          "--file ${./resource-usage.nix} > /tmp/resource-usage-2.json"
      )
      host.succeed("cat /tmp/resource-usage-2.json >&2")
      host.succeed(
          "jq --exit-status '.[0] | "
          "(has(\"memoryPeak\") | not) and (has(\"startTime\") | not)"
          "' /tmp/resource-usage-2.json"
      )

      # Start build in background
      host.execute("NIX_REMOTE=daemon nix build --auto-allocate-uids --file ${./hang.nix} >&2 &")
      service = "/sys/fs/cgroup/system.slice/nix-daemon.service"

      # Wait for cgroups to be created
      host.succeed(f"until [ -e {service}/nix-daemon ]; do sleep 1; done", timeout=30)
      host.succeed(f"until [ -e {service}/nix-build-uid-* ]; do sleep 1; done", timeout=30)

      # Check that there aren't processes where there shouldn't be, and that there are where there should be
      host.succeed(f'[ -z "$(cat {service}/cgroup.procs)" ]')
      host.succeed(f'[ -n "$(cat {service}/nix-daemon/cgroup.procs)" ]')
      host.succeed(f'[ -n "$(cat {service}/nix-build-uid-*/cgroup.procs)" ]')
    '';

}
