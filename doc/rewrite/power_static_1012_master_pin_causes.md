# Requirement-pin synchronization for master menu changes

These requirement-pin rows reproduce master commit `f5007aa10f` (2026-10-12),
not this branch's source changes. The source classes are window labels,
held-item self-menu filtering, drag-only input filtering, silent refusals,
duplicate labels and unlabelled catch-all naming. Four VR-sleeper serial
literals follow existing stabilization from `9b8f69f7e7` (2026-10-11).

Only the 29 fresh specialized requirement captures from
`20261012T072134_264b48922c` were promoted, with source/target hashes checked.
Their causes and affected types are documented in the generated-plan lane's
`intended_changes.md` section "Requirement pins after master menu fixes";
that lane subsequently passed its normal 32-test gate on `7d361f3ae611`.
Conversion captures are excluded. Factoring changes encoding, not other rows.
This branch still requires its own lane-ready verification.
