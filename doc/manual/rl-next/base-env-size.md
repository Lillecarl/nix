---
synopsis: "Registering many primops no longer overflows the base environment"
prs: []
---

The evaluator allocated room for 128 builtins, and wrote past the end of that allocation when more were registered.
A stock evaluator already fills 117 of them, so a plugin or a program that embeds Nix and registers about ten primops of its own could exceed it.
The size now follows the number of registered primops.
