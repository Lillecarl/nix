---
synopsis: "`nix build --json` reports the timing of a build again"
prs: []
---

`nix build --json` now reports `startTime`, `stopTime`, `cpuUser` and `cpuSystem` again, both for local builds and through the daemon.
`DerivationTrampolineGoal` passed only the status and outputs of a build up to the caller, so these fields kept their default values.
Users of the libstore API also get these fields for a build that fails.
