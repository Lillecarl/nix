---
synopsis: "An evaluator frees its builtins when it is destroyed"
prs: []
---

Each evaluator allocated its builtin functions and never freed them, about 84.5 KiB per evaluator.
Programs that create and destroy evaluators through the C API no longer leak this memory.
