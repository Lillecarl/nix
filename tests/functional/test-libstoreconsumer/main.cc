#include "nix/store/globals.hh"
#include "nix/store/store-open.hh"
#include "nix/store/build.hh"
#include "nix/store/build-result.hh"
#include <iostream>

int main(int argc, char ** argv)
{
    using namespace nix;

    try {
        if (argc != 2) {
            std::cerr << "Usage: " << argv[0] << " store/path/to/something.drv\n";
            return 1;
        }

        std::string drvPath = argv[1];

        initLibStore();

        auto store = nix::openStore();

        // build the derivation

        std::vector<DerivedPath> paths{DerivedPath::Built{
            .drvPath = makeConstantStorePathRef(store->parseStorePath(drvPath)), .outputs = OutputsSpec::Names{"out"}}};

        const auto results = store->getBuilder()->buildPathsWithResults(paths, bmNormal);

        for (const auto & result : results) {
            /* Print the statistics of every result, and not only of a
               result that reports a success. A consumer of the libstore
               API gets these fields for a build that fails as well.
               `nix build --json` cannot show this, because it prints the
               JSON only after a build that succeeds.

               Print to stderr, because stdout carries the output paths. */
            std::cerr << "status=" << (result.tryGetSuccess() ? "success" : "failure") << "\n";
            std::cerr << "timesBuilt=" << result.timesBuilt << "\n";
            std::cerr << "startTime=" << result.startTime << "\n";
            std::cerr << "stopTime=" << result.stopTime << "\n";

            if (auto * successP = result.tryGetSuccess()) {
                for (const auto & [outputName, realisation] : successP->builtOutputs) {
                    std::cout << store->printStorePath(realisation.outPath) << "\n";
                }
            }
        }

        return 0;

    } catch (const std::exception & e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }
}
