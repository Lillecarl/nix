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

    echo $i > $out
  ''
