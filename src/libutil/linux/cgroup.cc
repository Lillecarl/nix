#include "nix/util/cgroup.hh"
#include "nix/util/signals.hh"
#include "nix/util/util.hh"
#include "nix/util/file-system.hh"
#include "nix/util/finally.hh"

#include <boost/unordered/unordered_flat_set.hpp>
#include <chrono>
#include <cmath>
#include <regex>
#include <thread>

#include <dirent.h>
#include <mntent.h>

namespace nix::linux {

std::optional<std::filesystem::path> getCgroupFS()
{
    static auto res = [&]() -> std::optional<std::filesystem::path> {
        auto fp = fopen("/proc/mounts", "r");
        if (!fp)
            return std::nullopt;
        Finally delFP = [&]() { fclose(fp); };
        while (auto ent = getmntent(fp))
            if (std::string_view(ent->mnt_type) == "cgroup2")
                return ent->mnt_dir;

        return std::nullopt;
    }();
    return res;
}

// FIXME: obsolete, check for cgroup2
StringMap getCgroups(const std::filesystem::path & cgroupFile)
{
    StringMap cgroups;

    for (auto & line : tokenizeString<std::vector<std::string>>(readFile(cgroupFile), "\n")) {
        static std::regex regex("([0-9]+):([^:]*):(.*)");
        std::smatch match;
        if (!std::regex_match(line, match, regex))
            throw Error("invalid line '%s' in %s", line, PathFmt(cgroupFile));

        std::string name = hasPrefix(std::string(match[2]), "name=") ? std::string(match[2], 5) : match[2];
        cgroups.insert_or_assign(name, match[3]);
    }

    return cgroups;
}

bool tryEnableCgroupControllers(const std::filesystem::path & cgroup, std::string_view controllers)
{
    auto subtreeControlPath = cgroup / "cgroup.subtree_control";

    try {
        writeFile(subtreeControlPath, controllers);
        return true;
    } catch (SystemError & e) {
        /* A failure is usual in some correct conditions. For example,
           `cgroup` still has member processes (`EBUSY`), or the system
           did not delegate the cgroup to us (`EACCES`). The caller must
           accept that the applicable statistics are not available. */
        /* MUTATION: this rethrows instead of reporting failure. See the commit message. */
        debug("cannot enable cgroup controllers '%s' in %s: %s", controllers, PathFmt(cgroup), e.what());
        throw;
    }
}

/**
 * Read a cgroup "single value" file. Such a file contains one decimal
 * number. Return `std::nullopt` if the file does not exist, or if the
 * content is not a number. The file does not exist if the applicable
 * controller is not enabled, or if the kernel is too old.
 */
static std::optional<uint64_t> readCgroupSingleValue(const std::filesystem::path & path)
{
    if (!pathExists(path))
        return std::nullopt;

    try {
        return string2Int<uint64_t>(trim(readFile(path)));
    } catch (SystemError & e) {
        debug("cannot read cgroup file %s: %s", PathFmt(path), e.what());
        return std::nullopt;
    }
}

CgroupStats getCgroupStats(const std::filesystem::path & cgroup)
{
    CgroupStats stats;

    auto cpustatPath = cgroup / "cpu.stat";

    if (pathExists(cpustatPath)) {
        for (auto & line : tokenizeString<std::vector<std::string>>(readFile(cpustatPath), "\n")) {
            std::string_view userPrefix = "user_usec ";
            if (hasPrefix(line, userPrefix)) {
                auto n = string2Int<uint64_t>(line.substr(userPrefix.size()));
                if (n)
                    stats.cpuUser = std::chrono::microseconds(*n);
            }

            std::string_view systemPrefix = "system_usec ";
            if (hasPrefix(line, systemPrefix)) {
                auto n = string2Int<uint64_t>(line.substr(systemPrefix.size()));
                if (n)
                    stats.cpuSystem = std::chrono::microseconds(*n);
            }
        }
    }

    /* These two files are present only if the memory controller is
       enabled for this cgroup. `memory.peak` needs Linux 5.19 or later.
       `memory.swap.peak` needs Linux 6.5 or later. */
    stats.memoryPeak = readCgroupSingleValue(cgroup / "memory.peak");
    stats.memorySwapPeak = readCgroupSingleValue(cgroup / "memory.swap.peak");

    return stats;
}

static CgroupStats destroyCgroup(const std::filesystem::path & cgroup, bool returnStats)
{
    if (!pathExists(cgroup))
        return {};

    auto procsFile = cgroup / "cgroup.procs";

    if (!pathExists(procsFile))
        throw Error("%s is not a cgroup", PathFmt(cgroup));

    /* Use the fast way to kill every process in a cgroup, if
       available. */
    auto killFile = cgroup / "cgroup.kill";
    if (pathExists(killFile))
        writeFile(killFile, "1");

    /* Otherwise, manually kill every process in the subcgroups and
       this cgroup. */
    for (auto & entry : DirectoryIterator{cgroup}) {
        checkInterrupt();
        if (entry.symlink_status().type() != std::filesystem::file_type::directory)
            continue;
        destroyCgroup(cgroup / entry.path().filename(), false);
    }

    int round = 1;

    boost::unordered_flat_set<pid_t> pidsShown;

    while (true) {
        auto pids = tokenizeString<std::vector<std::string>>(readFile(procsFile));

        if (pids.empty())
            break;

        if (round > 20)
            throw Error("cannot kill cgroup %s", PathFmt(cgroup));

        for (auto & pid_s : pids) {
            pid_t pid;
            if (auto o = string2Int<pid_t>(pid_s))
                pid = *o;
            else
                throw Error("invalid pid '%s'", pid);
            if (pidsShown.insert(pid).second) {
                try {
                    auto cmdline = readFile(fmt("/proc/%d/cmdline", pid));
                    using namespace std::string_literals;
                    warn("killing stray builder process %d (%s)...", pid, trim(replaceStrings(cmdline, "\0"s, " ")));
                } catch (SystemError &) {
                }
            }
            // FIXME: pid wraparound
            if (kill(pid, SIGKILL) == -1 && errno != ESRCH)
                throw SysError("killing member %d of cgroup %s", pid, PathFmt(cgroup));
        }

        auto sleep = std::chrono::milliseconds((int) std::pow(2.0, std::min(round, 10)));
        if (sleep.count() > 100)
            printError("waiting for %d ms for cgroup %s to become empty", sleep.count(), PathFmt(cgroup));
        std::this_thread::sleep_for(sleep);
        round++;
    }

    CgroupStats stats;
    if (returnStats)
        stats = getCgroupStats(cgroup);

    if (rmdir(cgroup.c_str()) == -1)
        throw SysError("deleting cgroup %s", PathFmt(cgroup));

    return stats;
}

CgroupStats destroyCgroup(const std::filesystem::path & cgroup)
{
    return destroyCgroup(cgroup, true);
}

CanonPath getCurrentCgroup()
{
    auto cgroupFS = getCgroupFS();
    if (!cgroupFS)
        throw Error("cannot determine the cgroups file system");

    auto ourCgroups = getCgroups("/proc/self/cgroup");
    auto ourCgroup = ourCgroups[""];
    if (ourCgroup == "")
        throw Error("cannot determine cgroup name from /proc/self/cgroup");
    return CanonPath{ourCgroup};
}

CanonPath getRootCgroup()
{
    static auto rootCgroup = getCurrentCgroup();
    return rootCgroup;
}

} // namespace nix::linux
