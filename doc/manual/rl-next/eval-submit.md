---
synopsis: "`nix eval --submit` registers a graph from inside a build"
prs: []
issues: []
---

`nix eval` has a new flag, `--submit` *output-name*. The flag makes the
evaluation register the derivation that the expression gives, as the output
*output-name* of the derivation that runs now.

The flag works inside a build that asks for the `builder-rpc-v0` system
feature. That feature gives the builder a restricted daemon socket.

A planner needed two steps before this flag. The planner wrote the graph, read
the store path of the root, and then ran `nix store submit-output` with that
path. The evaluator already writes each derivation of the graph through the
socket, so the second step now needs no separate command:

```console
# nix eval --submit out --file ./graph.nix root
```
