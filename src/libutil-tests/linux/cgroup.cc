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
    });
}

} // namespace nix::linux
