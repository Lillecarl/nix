#include "nix/fetchers/fetch-settings.hh"
#include "nix/fetchers/fetch-to-store.hh"
#include "nix/store/tests/libstore.hh"
#include "nix/util/memory-source-accessor.hh"

#include <gtest/gtest.h>

namespace nix {

class FetchToStoreTest : public LibStoreTest
{
protected:
    FetchToStoreTest()
        : LibStoreTest(openStore("dummy://", {{"read-only", "false"}}))
    {
    }

    fetchers::Settings settings;
};

TEST_F(FetchToStoreTest, forgetSrcToStoreCopiesAgain)
{
    auto accessor = make_ref<MemorySourceAccessor>();
    auto path = accessor->addFile(CanonPath("/file"), "old");
    auto oldCopy = fetchToStore(settings, *store, path, FetchMode::Copy);

    accessor->addFile(CanonPath("/file"), "new");
    EXPECT_EQ(fetchToStore(settings, *store, path, FetchMode::Copy), oldCopy);

    settings.forgetSrcToStore(path);
    EXPECT_NE(fetchToStore(settings, *store, path, FetchMode::Copy), oldCopy);
}

} // namespace nix
