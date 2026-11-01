{ nixpkgs, ... }:

{
  name = "cgroups";

  nodes = {
    host =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        virtualisation.additionalPaths = [ pkgs.stdenvNoCC ];
        nix.extraOptions = ''
          extra-experimental-features = nix-command auto-allocate-uids cgroups
          extra-system-features = uid-range
        '';
        nix.settings.use-cgroups = true;
        nix.settings.substituters = lib.mkForce [ ];
        nix.nixPath = [ "nixpkgs=${nixpkgs}" ];
      };
  };

  testScript =
    { nodes }:
    ''
      start_all()

      host.wait_for_unit("multi-user.target")

      # Start build in background
      host.execute("NIX_REMOTE=daemon nix build --auto-allocate-uids --file ${./hang.nix} >&2 &")
      service = "/sys/fs/cgroup/system.slice/nix-daemon.service"

      # Wait for cgroups to be created, the build cgroup wherever it appears
      host.succeed(f"until [ -e {service}/nix-daemon ]; do sleep 1; done", timeout=30)
      host.wait_until_succeeds(f"find {service} -maxdepth 2 -type d -name 'nix-build@*' | grep -q .", timeout=30)

      # Build cgroups must sit beside nix-daemon, not inside it: nix-daemon
      # holds processes, so it cannot delegate controllers to them.
      builds = host.succeed(f"find {service} -maxdepth 2 -type d -name 'nix-build@*'").split()
      misplaced = [b for b in builds if not b.startswith(f"{service}/nix-build@")]
      assert not misplaced, f"build cgroups inside nix-daemon: {misplaced}"

      # Check that there aren't processes where there shouldn't be, and that there are where there should be
      host.succeed(f'[ -z "$(cat {service}/cgroup.procs)" ]')
      host.succeed(f'[ -n "$(cat {service}/nix-daemon/cgroup.procs)" ]')
      host.succeed(f'[ -n "$(cat {service}/nix-build@*/cgroup.procs)" ]')

      # Check controllers.
      host.succeed(f'[ -n "$(cat {service}/cgroup.subtree_control)" ]')
      host.succeed(f'[ -n "$(cat {service}/nix-build@*/memory.peak)" ]')
    '';

}
