{ }:

with import <nixpkgs> { };

runCommand "resource-usage"
  {
    requiredSystemFeatures = "uid-range";
  }
  ''
    # Use a measurable quantity of CPU time. The test asserts only that
    # `cpuUser` is more than zero. Thus the exact quantity does not matter.
    i=0
    while [ $i -lt 200000 ]; do
      i=$((i + 1))
    done

    # Allocate approximately 64 MiB of anonymous memory. The test asserts that
    # `memoryPeak` is more than 32 MiB. Thus the test shows that Nix reports a
    # true measurement, and not a small default value.
    ballast=$(head -c 67108864 /dev/zero | tr "\0" "x")

    echo $i ''${#ballast} > $out
  ''
