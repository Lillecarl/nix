---
synopsis: "Builds report the peak memory usage when Nix uses cgroups"
---

With [`use-cgroups`](@docroot@/command-ref/conf-file.md#conf-use-cgroups), Nix now
records the peak memory usage and the peak swap usage of a build. `nix build --json`
reports them as `memoryPeak` and `memorySwapPeak`, in bytes.

Both values are necessary. In cgroup v2, the kernel removes the pages that go to swap
from the memory usage of the cgroup. Thus on a host that swaps, `memoryPeak` alone is
less than the true memory demand of the build.

The values come from `memory.peak` (Linux 5.19 or later) and `memory.swap.peak`
(Linux 6.5 or later, with swap support). These files exist only when the daemon can
enable the memory controller for the build cgroups. A build through a client that is
not the daemon reports no memory values.

Nix sends the two values over the worker protocol with the new `build-result-memory`
protocol feature.
