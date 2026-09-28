---
synopsis: "`nix build --json` reports the timing of a build again"
---

The documentation of `nix build --json` shows a `startTime` field and a `stopTime`
field. `BuildResult` also holds the CPU time of a build in `cpuUser` and `cpuSystem`.
But the client did not get these four fields.

Nix sends the result of a build up through `DerivationTrampolineGoal`. This goal kept
only the status and the outputs of the build. It left the timing fields and the
resource fields at their default values.

`DerivationTrampolineGoal` now merges these fields from its sub-goals. Thus
`nix build --json` reports `startTime`, `stopTime`, `cpuUser` and `cpuSystem` again.
The sub-goals are the outputs of one derivation, and they report the same build. Thus
Nix takes the maximum value and not the sum.
