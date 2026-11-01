---
synopsis: "New setting `count-calls`"
prs: []
---

The new [`count-calls`](@docroot@/command-ref/conf-file.md#conf-count-calls) setting does what the [`NIX_COUNT_CALLS`](@docroot@/command-ref/env-common.md#env-NIX_COUNT_CALLS) environment variable does: it counts function calls, primop calls and attribute selections for the statistics that `NIX_SHOW_STATS` prints.
Unlike the environment variable, it can be set per evaluator, for example by a program that embeds Nix.
The environment variable keeps working.
