---
synopsis: "Builds report their peak memory usage when Nix uses cgroups"
prs: []
---

With [`use-cgroups`](@docroot@/command-ref/conf-file.md#conf-use-cgroups), Nix records the peak memory and peak swap usage of a build.
`nix build --json` reports them as `memoryPeak` and `memorySwapPeak`, in bytes.

Both are needed: cgroup v2 moves swapped-out pages from the memory count to the swap count, so on a host that swaps `memoryPeak` alone understates what the build needed.

The values come from `memory.peak` (Linux 5.19 or later) and `memory.swap.peak` (Linux 6.5 or later, with swap support).
These files exist only when the daemon can enable the memory controller for build cgroups, so a build without the daemon reports no memory values.

The daemon sends the values to clients that support the new `build-result-memory` protocol feature.
