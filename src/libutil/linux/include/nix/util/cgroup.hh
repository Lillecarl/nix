#pragma once
///@file

#include <chrono>
#include <cstdint>
#include <optional>
#include <filesystem>

#include "nix/util/types.hh"
#include "nix/util/canon-path.hh"

namespace nix::linux {

std::optional<std::filesystem::path> getCgroupFS();

StringMap getCgroups(const std::filesystem::path & cgroupFile);

struct CgroupStats
{
    std::optional<std::chrono::microseconds> cpuUser, cpuSystem;

    /**
     * The peak memory usage and the peak swap usage, in bytes. These
     * two fields are available only if the memory controller is enabled
     * for the cgroup, and the kernel is new enough. `memory.peak` needs
     * Linux 5.19 or later. `memory.swap.peak` needs Linux 6.5 or later.
     */
    std::optional<uint64_t> memoryPeak, memorySwapPeak;
};

/**
 * Read statistics from the given cgroup.
 */
CgroupStats getCgroupStats(const std::filesystem::path & cgroup);

/**
 * Destroy the cgroup denoted by 'path'. The postcondition is that
 * 'path' does not exist, and thus any processes in the cgroup have
 * been killed. Also return statistics from the cgroup just before
 * destruction.
 */
CgroupStats destroyCgroup(const std::filesystem::path & cgroup);

CanonPath getCurrentCgroup();

/**
 * Get the cgroup that should be used as the parent when creating new
 * sub-cgroups. The first time this is called, the current cgroup will be
 * returned, and then all subsequent calls will return the original cgroup.
 */
CanonPath getRootCgroup();

} // namespace nix::linux
