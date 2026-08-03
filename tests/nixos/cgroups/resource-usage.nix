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

    # About 64 MiB of anonymous memory; the test expects memoryPeak > 32 MiB.
    ballast=$(head -c 67108864 /dev/zero | tr "\0" "x")

    echo $i ''${#ballast} > $out
  ''
