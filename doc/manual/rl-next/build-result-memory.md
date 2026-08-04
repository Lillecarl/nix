---
synopsis: "Builds report the peak memory usage when Nix uses cgroups"
---

Nix can run a build in its own cgroup. To do this, enable the
[`cgroups`](@docroot@/development/experimental-features.md#xp-feature-cgroups)
experimental feature and the
[`use-cgroups`](@docroot@/command-ref/conf-file.md#conf-use-cgroups) setting.

For such a build, Nix now records the peak memory usage and the peak swap usage. It
already recorded the CPU time. `nix build --json` reports the two new values as
`memoryPeak` and `memorySwapPeak`, in bytes.

Both values are necessary. On a host that swaps, `memoryPeak` alone is less than the
true memory demand of the build. In cgroup v2, the kernel removes the pages that go
to swap from the memory usage of the cgroup, and adds them to the swap usage.

`memoryPeak` needs Linux 5.19 or later. `memorySwapPeak` needs Linux 6.5 or later,
and it needs a kernel with swap support. Without swap support the kernel does not
make the `memory.swap.peak` file, and Nix reports no value.

To get the two values, the memory controller must be enabled for the cgroup of the
build. The daemon enables it one time, at start.

In cgroup v2, a cgroup cannot hold processes and enable controllers for its children
at the same time. A write to `cgroup.subtree_control` fails with `EBUSY` when the
cgroup holds a process. Nix makes the cgroup of each build below the cgroup that
holds Nix itself. Thus the write succeeds only when that cgroup is empty.

The daemon makes its cgroup empty. At start, `nix-daemon` makes a `nix-daemon`
sub-cgroup and moves itself into it. It then enables the memory controller. The
cgroup of each build is a sibling of the daemon, and so it gets the controller.

A client stays in its own cgroup, and so that cgroup is never empty. Thus a build
reports the two values through the daemon only.

Note the reach of this change. The daemon writes to the `cgroup.subtree_control`
file of its parent cgroup. Thus every child of that cgroup gets memory accounting,
and not only the builds of Nix. Memory accounting has a small cost in the kernel.
The `use-cgroups` setting turns the whole feature off.

`cpuUser` and `cpuSystem` do not have this limit. `cpu.stat` is a core file of
cgroup v2, and it needs no controller.

Nix sends the two values over the worker protocol with the new `build-result-memory`
protocol feature. Thus a remote build also reports them, if both sides know the
feature.
