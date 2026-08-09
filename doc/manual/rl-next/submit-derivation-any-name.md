---
synopsis: "A submitted output may be a derivation with a name of its own"
---

`nix store submit-output` accepts a derivation as a floating
content-addressed output, and the name of that derivation no longer has to
follow the name of the derivation that submits it.

A planner in a `builder-rpc-v0` build registers a graph of derivations and
then submits the root of that graph. The name of the root is a result of the
plan, and the previous rule compared it with the name of the planner. So a
planner had to declare the name of a result that it computes when it runs,
and the planner also had to end its own name in `.drv`, which
`builtins.derivation` permits only for a text-hashed derivation with one
output named `out`.

A submitted derivation now keeps a stronger identity than the name gives it.
Nix reads the derivation and computes the store path of it again, and it
refuses the output when that path is not the path where the derivation is.
This check also covers a submitted derivation whose name does follow the old
rule, which the name comparison alone never proved.

A fixed output keeps the name rule, because the name of the derivation and
the declared hash together give a fixed output its store path.
