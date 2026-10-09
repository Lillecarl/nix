---
synopsis: "Ctrl-C stops a long evaluation"
prs: []
---

The evaluator now checks for an interrupt at every function call.
It used to check only while it printed a value, so Ctrl-C or SIGTERM did not stop a long-running evaluation, such as a large `builtins.foldl'` loop.
