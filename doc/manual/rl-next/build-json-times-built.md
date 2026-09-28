---
synopsis: "`nix build --json` reports `timesBuilt`"
---

`BuildResult` holds a `timesBuilt` field. It counts how many times Nix built a
path. The JSON schema of `BuildResult` describes the field, but `nix build --json`
never printed it.

`nix build --json` now reports `timesBuilt`. A value of more than one shows that
Nix built the path more than one time, for example after a check with `--rebuild`.

Nix prints the field only for a path that it built. A path that is already valid
gets no `timesBuilt`, in the manner of `startTime` and `stopTime`.
