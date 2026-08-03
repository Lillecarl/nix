#include <gtest/gtest.h>

#include "nix/store/build-result.hh"
#include "nix/util/tests/characterization.hh"
#include "nix/util/tests/json-characterization.hh"

namespace nix {

class BuildResultTest : public virtual CharacterizationTest
{
    std::filesystem::path unitTestData = getUnitTestData() / "build-result";

public:
    std::filesystem::path goldenMaster(std::string_view testStem) const override
    {
        return unitTestData / testStem;
    }
};

/* ----------------------------------------------------------------------------
 * mergeBuildStats
 * --------------------------------------------------------------------------*/

TEST(BuildResultMergeBuildStats, takesEarliestStartAndLatestStop)
{
    BuildResult a{.startTime = 30, .stopTime = 50};
    a.mergeBuildStats(BuildResult{.startTime = 20, .stopTime = 40});

    EXPECT_EQ(a.startTime, 20);
    EXPECT_EQ(a.stopTime, 50);
}

TEST(BuildResultMergeBuildStats, ignoresUnsetStartTime)
{
    /* A goal that did not run has a startTime of 0. This value does not
       show a start at the epoch. */
    BuildResult a{.startTime = 30, .stopTime = 50};
    a.mergeBuildStats(BuildResult{.startTime = 0, .stopTime = 0});

    EXPECT_EQ(a.startTime, 30);
    EXPECT_EQ(a.stopTime, 50);
}

TEST(BuildResultMergeBuildStats, takesMaximumNotSum)
{
    /* The sub-goals are the outputs of one derivation, and they report
       the same build. A sum multiplies the usage by the number of the
       outputs. */
    BuildResult a{
        .timesBuilt = 1,
        .cpuUser = std::chrono::microseconds(500),
        .cpuSystem = std::chrono::microseconds(600),
    };
    BuildResult b = a;

    a.mergeBuildStats(b);

    EXPECT_EQ(a.timesBuilt, 1u);
    EXPECT_EQ(a.cpuUser->count(), 500);
    EXPECT_EQ(a.cpuSystem->count(), 600);
}

TEST(BuildResultMergeBuildStats, fillsInMissingValues)
{
    BuildResult a{};
    a.mergeBuildStats(BuildResult{.cpuUser = std::chrono::microseconds(500)});

    ASSERT_TRUE(a.cpuUser.has_value());
    EXPECT_EQ(a.cpuUser->count(), 500);
    EXPECT_FALSE(a.cpuSystem.has_value());
}

TEST(BuildResultMergeBuildStats, keepsExistingWhenOtherIsUnset)
{
    BuildResult a{.cpuUser = std::chrono::microseconds(500)};
    a.mergeBuildStats(BuildResult{});

    ASSERT_TRUE(a.cpuUser.has_value());
    EXPECT_EQ(a.cpuUser->count(), 500);
}

using nlohmann::json;

struct BuildResultJsonTest : BuildResultTest,
                             JsonCharacterizationTest<BuildResult>,
                             ::testing::WithParamInterface<std::pair<std::string_view, BuildResult>>
{};

TEST_P(BuildResultJsonTest, from_json)
{
    auto & [name, expected] = GetParam();
    readJsonTest(name, expected);
}

TEST_P(BuildResultJsonTest, to_json)
{
    auto & [name, value] = GetParam();
    writeJsonTest(name, value);
}

INSTANTIATE_TEST_SUITE_P(
    BuildResultJSON,
    BuildResultJsonTest,
    ::testing::Values(
        std::pair{
            "not-deterministic",
            BuildResult{
                .inner{BuildResult::Failure{{
                    .status = BuildResult::Failure::NotDeterministic,
                    .msg = HintFmt("no idea why"),
                    .isNonDeterministic = false, // Note: This field is separate from the status
                }}},
                .timesBuilt = 1,
            },
        },
        std::pair{
            "output-rejected",
            BuildResult{
                .inner{BuildResult::Failure{{
                    .status = BuildResult::Failure::OutputRejected,
                    .msg = HintFmt("no idea why"),
                    .isNonDeterministic = false,
                }}},
                .timesBuilt = 3,
                .startTime = 30,
                .stopTime = 50,
            },
        },
        std::pair{
            "success",
            BuildResult{
                .inner{BuildResult::Success{
                    .status = BuildResult::Success::Built,
                    .builtOutputs{
                        {
                            "foo",
                            {
                                .outPath = StorePath{"g1w7hy3qg1w7hy3qg1w7hy3qg1w7hy3q-foo"},
                            },
                        },
                        {
                            "bar",
                            {
                                .outPath = StorePath{"g1w7hy3qg1w7hy3qg1w7hy3qg1w7hy3q-bar"},
                            },
                        },
                    },
                }},
                .timesBuilt = 3,
                .startTime = 30,
                .stopTime = 50,
                .cpuUser = std::chrono::seconds(500),
                .cpuSystem = std::chrono::seconds(604),
            },
        }));

} // namespace nix
