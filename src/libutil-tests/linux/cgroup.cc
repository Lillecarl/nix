#include <gtest/gtest.h>

#include "nix/util/cgroup.hh"
#include "nix/util/file-system.hh"

namespace nix::linux {

/* `getCgroupStats` reads only a set of known files in the given directory.
   Thus these tests use a synthetic "cgroup". They do not need a privilege,
   and they do not need a real cgroup2 mount. */

struct CgroupStatsTest : ::testing::Test
{
    std::filesystem::path tmpDir = createTempDir();
    AutoDelete delTmpDir{tmpDir, /*recursive=*/true};

    void writeCgroupFile(std::string_view name, std::string_view contents)
    {
        writeFile(tmpDir / name, contents);
    }
};

TEST_F(CgroupStatsTest, emptyCgroupHasNoStats)
{
    auto stats = getCgroupStats(tmpDir);

    EXPECT_FALSE(stats.cpuUser.has_value());
    EXPECT_FALSE(stats.cpuSystem.has_value());
    EXPECT_FALSE(stats.memoryPeak.has_value());
    EXPECT_FALSE(stats.memorySwapPeak.has_value());
}

TEST_F(CgroupStatsTest, readsCpuStats)
{
    /* This is the layout of a true build cgroup. `usage_usec` is the sum of
       the two other values. `getCgroupStats` does not read it. */
    writeCgroupFile("cpu.stat", "usage_usec 2933845\nuser_usec 1813317\nsystem_usec 1120528\n");

    auto stats = getCgroupStats(tmpDir);

    ASSERT_TRUE(stats.cpuUser.has_value());
    EXPECT_EQ(stats.cpuUser->count(), 1813317);
    ASSERT_TRUE(stats.cpuSystem.has_value());
    EXPECT_EQ(stats.cpuSystem->count(), 1120528);
}

TEST_F(CgroupStatsTest, readsPartialCpuStat)
{
    /* One field can be present when the other field is absent. */
    writeCgroupFile("cpu.stat", "user_usec 1813317\n");

    auto stats = getCgroupStats(tmpDir);

    ASSERT_TRUE(stats.cpuUser.has_value());
    EXPECT_EQ(stats.cpuUser->count(), 1813317);
    EXPECT_FALSE(stats.cpuSystem.has_value());
}

TEST_F(CgroupStatsTest, ignoresUnparseableCpuValue)
{
    /* Do not stop a build if we cannot read a statistics file. */
    writeCgroupFile("cpu.stat", "user_usec not a number\nsystem_usec 1120528\n");

    EXPECT_NO_THROW({
        auto stats = getCgroupStats(tmpDir);
        EXPECT_FALSE(stats.cpuUser.has_value());
        ASSERT_TRUE(stats.cpuSystem.has_value());
        EXPECT_EQ(stats.cpuSystem->count(), 1120528);
    });
}

TEST_F(CgroupStatsTest, nonexistentCgroupDoesNotThrow)
{
    EXPECT_NO_THROW({
        auto stats = getCgroupStats(tmpDir / "does-not-exist");
        EXPECT_FALSE(stats.cpuUser.has_value());
        EXPECT_FALSE(stats.memoryPeak.has_value());
    });
}

TEST_F(CgroupStatsTest, readsMemoryPeaks)
{
    /* A single-value cgroup file ends with a newline. */
    writeCgroupFile("memory.peak", "538841088\n");
    writeCgroupFile("memory.swap.peak", "4096\n");

    auto stats = getCgroupStats(tmpDir);

    ASSERT_TRUE(stats.memoryPeak.has_value());
    EXPECT_EQ(*stats.memoryPeak, 538841088U);
    ASSERT_TRUE(stats.memorySwapPeak.has_value());
    EXPECT_EQ(*stats.memorySwapPeak, 4096U);
}

TEST_F(CgroupStatsTest, readsZeroPeaksAsPresent)
{
    /* A peak of zero is a true measurement, and not an absent one. This is
       the usual value of `memory.swap.peak` on a host that did not swap. */
    writeCgroupFile("memory.peak", "0\n");
    writeCgroupFile("memory.swap.peak", "0\n");

    auto stats = getCgroupStats(tmpDir);

    ASSERT_TRUE(stats.memoryPeak.has_value());
    EXPECT_EQ(*stats.memoryPeak, 0U);
    ASSERT_TRUE(stats.memorySwapPeak.has_value());
    EXPECT_EQ(*stats.memorySwapPeak, 0U);
}

TEST_F(CgroupStatsTest, swapPeakAbsentOnOlderKernels)
{
    /* `memory.peak` needs Linux 5.19 or later. `memory.swap.peak` needs
       Linux 6.5 or later. Thus `memory.swap.peak` can be absent when
       `memory.peak` is present. */
    writeCgroupFile("memory.peak", "1234567890\n");

    auto stats = getCgroupStats(tmpDir);

    ASSERT_TRUE(stats.memoryPeak.has_value());
    EXPECT_EQ(*stats.memoryPeak, 1234567890U);
    EXPECT_FALSE(stats.memorySwapPeak.has_value());
}

TEST_F(CgroupStatsTest, ignoresUnparseableMemoryValue)
{
    writeCgroupFile("memory.peak", "not a number\n");

    EXPECT_NO_THROW({
        auto stats = getCgroupStats(tmpDir);
        EXPECT_FALSE(stats.memoryPeak.has_value());
    });
}

TEST_F(CgroupStatsTest, readsCpuAndMemoryTogether)
{
    /* A build cgroup gives the CPU time and the memory usage together. */
    writeCgroupFile("cpu.stat", "usage_usec 2933845\nuser_usec 1813317\nsystem_usec 1120528\n");
    writeCgroupFile("memory.peak", "538841088\n");
    writeCgroupFile("memory.swap.peak", "0\n");

    auto stats = getCgroupStats(tmpDir);

    ASSERT_TRUE(stats.cpuUser.has_value());
    EXPECT_EQ(stats.cpuUser->count(), 1813317);
    ASSERT_TRUE(stats.cpuSystem.has_value());
    EXPECT_EQ(stats.cpuSystem->count(), 1120528);
    ASSERT_TRUE(stats.memoryPeak.has_value());
    EXPECT_EQ(*stats.memoryPeak, 538841088U);
    ASSERT_TRUE(stats.memorySwapPeak.has_value());
    EXPECT_EQ(*stats.memorySwapPeak, 0U);
}

/* ----------------------------------------------------------------------------
 * tryEnableCgroupControllers
 * --------------------------------------------------------------------------*/

TEST(tryEnableCgroupControllers, failsGracefullyOnNonCgroup)
{
    auto tmpDir = createTempDir();
    AutoDelete delTmpDir(tmpDir, /*recursive=*/true);

    /* A usual directory has no `cgroup.subtree_control` file. A write to a
       path that does not exist must report a failure, and must not throw.
       Thus a build continues where we cannot enable the controller. */
    EXPECT_NO_THROW({ EXPECT_FALSE(tryEnableCgroupControllers(tmpDir / "not-a-cgroup", "+memory")); });
}

} // namespace nix::linux
