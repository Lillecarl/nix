#include "nix/cmd/command-installable-value.hh"
#include "nix/main/common-args.hh"
#include "nix/main/shared.hh"
#include "nix/store/store-api.hh"
#include "nix/store/store-cast.hh"
#include "nix/store/submit-store.hh"
#include "nix/expr/eval.hh"
#include "nix/expr/eval-inline.hh"
#include "nix/expr/value-to-json.hh"

#include <nlohmann/json.hpp>

namespace nix {

struct CmdEval : MixJSON, InstallableValueCommand, MixReadOnlyOption
{
    bool raw = false;
    std::optional<std::string> apply;
    std::optional<std::filesystem::path> writeTo;
    std::optional<std::string> submitOutput;

    CmdEval()
        : InstallableValueCommand()
    {
        addFlag({
            .longName = "raw",
            .description = "Print strings without quotes or escaping.",
            .handler = {&raw, true},
        });

        addFlag({
            .longName = "apply",
            .description = "Apply the function *expr* to each argument.",
            .labels = {"expr"},
            .handler = {&apply},
        });

        addFlag({
            .longName = "write-to",
            .description = "Write a string or attrset of strings to *path*.",
            .labels = {"path"},
            .handler = {&writeTo},
        });

        addFlag({
            .longName = "submit",
            .description = R"(
  Submit the derivation that this expression gives, as the output *output-name*
  of the derivation that runs now.

  This works only inside a build that asks for the `builder-rpc-v0` system
  feature, which gives the builder a restricted daemon socket. It replaces a
  read of `drvPath` followed by a separate `nix store submit-output`.

  The evaluator writes each derivation of the graph through that socket, so a
  planner needs no other command to register the graph.
)",
            .labels = {"output-name"},
            .handler = {&submitOutput},
        });
    }

    std::string description() override
    {
        return "evaluate a Nix expression";
    }

    std::string doc() override
    {
        return
#include "eval.md"
            ;
    }

    Category category() override
    {
        return catSecondary;
    }

    void run(ref<Store> store, ref<InstallableValue> installable) override
    {
        if (raw && json)
            throw UsageError("--raw and --json are mutually exclusive");

        if (submitOutput && (raw || json || writeTo))
            throw UsageError("--submit gives no output of its own, so it takes none of --raw, --json and --write-to");

        auto state = getEvalState();

        auto [v, pos] = installable->toValue(*state);
        NixStringContext context;

        if (apply) {
            auto vApply = state->allocValue();
            state->eval(state->parseExprFromString(*apply, state->rootPath(".")), *vApply);
            auto vRes = state->allocValue();
            state->callFunction(*vApply, *v, *vRes, noPos);
            v = vRes;
        }

        if (submitOutput) {
            logger->stop();

            /* A derivation stands for its output `out`, which is the rule
               that interpolation of a derivation follows. `outPath` carries
               the context that names the derivation. */
            state->forceValue(*v, pos);
            if (state->isDerivation(*v)) {
                auto * outPath = v->attrs()->get(state->s.outPath);
                if (!outPath)
                    state->error<TypeError>("derivation has no 'outPath' attribute to submit").debugThrow();
                v = outPath->value;
            }

            auto derivedPath =
                state->coerceToSingleDerivedPath(pos, *v, "while evaluating the expression to submit as an output");

            /* **The derivation is the thing to submit, and not its output.**
               A planner registers a derivation that no build made yet, so
               `Built` names an output that does not exist. The `drvPath`
               field of it names the derivation that the evaluator wrote, and
               that store object is what the output of this build is. A plain
               store path goes through as it is, which is what
               `nix store submit-output` takes. */
            auto toSubmit = std::visit(
                overloaded{
                    [&](const SingleDerivedPath::Opaque & opaque) -> SingleDerivedPath { return opaque; },
                    [&](const SingleDerivedPath::Built & built) -> SingleDerivedPath { return *built.drvPath; },
                },
                derivedPath.raw());

            require<SubmitStore>(*store).submitOutput(toSubmit, *submitOutput);
        }

        else if (writeTo) {
            logger->stop();

            if (pathExists(*writeTo))
                throw Error("path '%s' already exists", writeTo->string());

            [&](this const auto & recurse, Value & v, const PosIdx pos, const std::filesystem::path & path) -> void {
                state->forceValue(v, pos);
                if (v.type() == nString) {
                    copyContext(v, context);
                    writeFile(path, v.string_view());
                } else if (v.type() == nAttrs) {
                    [[maybe_unused]] bool directoryCreated = std::filesystem::create_directory(path);
                    // Directory should not already exist
                    assert(directoryCreated);
                    for (auto & attr : *v.attrs()) {
                        std::string_view name = state->symbols[attr.name];
                        try {
                            if (name == "." || name == "..")
                                throw Error("invalid file name '%s'", name);
                            recurse(*attr.value, attr.pos, path / name);
                        } catch (Error & e) {
                            e.addTrace(
                                state->positions[attr.pos], HintFmt("while evaluating the attribute '%s'", name));
                            throw;
                        }
                    }
                } else
                    state->error<TypeError>("value at '%s' is not a string or an attribute set", state->positions[pos])
                        .debugThrow();
            }(*v, pos, *writeTo);
        }

        else if (raw) {
            logger->stop();
            auto string = state->coerceToString(noPos, *v, context, "while generating the eval command output");
            writeFull(getStandardOutput(), *string);
        }

        else if (json) {
            printJSON(printValueAsJSON(*state, true, *v, pos, context, false));
        }

        else {
            ValuePrinter printer(*state, *v, PrintOptions{.force = true, .derivationPaths = true}, &context);
            logger->cout("%s", printer);
        }

        state->ensureLazyPathsCopied(context);
    }
};

static auto rCmdEval = registerCommand<CmdEval>("eval");

} // namespace nix
