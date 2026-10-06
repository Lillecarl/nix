---
synopsis: "Destroying an `EvalState` releases its store"
prs: []
---

An `EvalState` that had parsed a path literal or imported a file kept its store alive after it was destroyed.
For a daemon store, that included the connection pool.
Programs that use the C or C++ API and create an `EvalState` per request no longer leak a store and its daemon connections each time.
