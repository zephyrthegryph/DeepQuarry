# Native power leaf moves: 2026-10-13 handoff

Branch: codex/phase-d-power-leaves-1013.

The move commit 93e92312de relocates four fully native files into
code/domains/power/content, preserving their relative paths:

- fusion/fusion_circuits.dm
- singularity/particle_accelerator/particle_chamber.dm
- singularity/particle_accelerator/particle_power.dm
- smes_prefabs.dm

All four are 100% identical renames. Only their existing DME include paths change,
with include order preserved. A separate fixture commit uses the existing native
relation operation for hand-card insertion; it does not change power behavior.

After merging master 4702c4af68, the old stamp correctly failed carry-over because
master changed request and contract dependencies. A fresh lane-ready run on
e632e47d3fa9 passed production compilation, DreamChecker and all ratchets, with
54 tests passed and zero failed. Boot had zero runtimes and warnings. Evidence:
data/test-runs/20261013T191705_e632e47d3f.json. The resulting stamped commit is
11634f5cb6; this handoff is its documentation-only child.

Focused power coverage: dq_p2_smes/mapped_presets,
mapped_presets_one_sided, mapped_coils_set_capacity_and_io and
point_of_interest_unit_starts_full_and_open. Both mandatory requirement and
conversion pins and the lane-ready smoke/incremental look checks ran. Circuit
and accelerator leaf declarations have no dedicated behavior claim in this batch.

No legacy forms were converted, baselines raised, or ALLOW annotations added.
The only recorded look-key change is the hand-card hash caused by master's
852173317d explicit TRACKED declaration; its dependency names are unchanged.
