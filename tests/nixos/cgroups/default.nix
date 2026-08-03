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
