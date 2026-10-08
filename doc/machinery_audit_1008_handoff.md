# Machinery audit handoff — 2026-10-08 (verification pending)

Branch: `codex/machinery-audit-1008`, based on `origin/master` `6cf9e920d7`. This draft describes the timed-work lane only; other audit lanes are being integrated by the parent agent.

## Timed work

Explicit machinery/power calls fell from 27 to 3: `task_timed` 21 → 2, `task_busy` 5 → 0, `task_start` 1 → 1. Thus 24 calls were retired. Master had already retired the cutout call from the earlier 28-call inventory. Two additional indirect camera/assembly timed `use_tool` calls were converted.

Fifteen fully retired files were added to `timed_forms_converted`: bioprinter; camera and camera assembly; cloning; AIcore; doorbell; feeder; food replicator; IV drip; oxygen pump; supply beacon; suit storage unit; VR console; washing machine; breaker box. Cryopod, medical kiosk and suit cycler were not banned. Scoped bans cover the explicit task forms, not every possible legacy helper.

The port retains master's AIcore latejoin/admin asks and cloning deleted-record cleanup. Supporting fixes publish the real aggregate wire dependency, use the suit-storage tracked setter from stumble handling, explicitly cast oxygen-pump human anatomy access, and remove a stale read annotation. No debt ALLOW or ceiling increase was added.

## Remaining blockers

- Medical kiosk `task_start`: reserves the session/power before asking. Native starts run after asks; no reversible pre-question effect exists.
- Cryopod third-party `task_timed`: the passenger must answer consent while the loader remains the actor. Native asks currently force the actor as answerer.
- Suit cycler `task_timed`: immediate shock can abort before the delay. Native starts ignore the handler's return; moving the shock after the wait changes behavior.
- AIcore retains five unpinned helper-driven `use_tool` construction paths. Those were not represented as retired explicit task calls and were not converted without old-code pins.

## Evidence and tests

Historical old-code pins against `059aac8767` are reused with explicit parent approval, not represented as a fresh current-base execution. Seventeen of 18 compared files are LF-byte-identical; AIcore's three relevant timed bodies match exactly. Individual hashes are in ignored `data/codex-machinery/audit-1008/old-pin-provenance.json`. The earlier run verified 43 real-input old behavior checks. The prior native run had 55 passes, no failures/skips, clean boot and no state leaks; this is historical evidence only.

Ported focused files are `dq_machinery_timed_simple_pin`, `dq_machinery_timed_material_pin`, `dq_machinery_timed_occupant_pin`, and `dq_machinery_timed_conversion_pin`, plus native breaker checks in `dq_hc_machinery_behaviour`. Eighteen scoped snapshots are reused as reviewed expectations. Faster welder, wire-mending cancellation and electric charge/cancellation regressions were added after native conversion and are not claimed as old-code verified. Per-class causes are appended to `doc/rewrite/intended_changes.md`.

Current-branch generation, DreamChecker, ratchets, focused test execution and snapshot review are **pending the parent's single final verification batch**. No full suite was run by this lane. No new capture difference has been approved or blessed by this draft.

## Optional energy/cell appearance audit

Native draw supports the required providers; there is no identified framework gap. Full conversion requires tracking cell charge/max-charge and all writers together with energy-gun providers and dependent redraw paths. The read-only inventory found 45 external `.charge` assignment candidates across 29 production files; these are candidates, not a proven complete semantic inventory. Energy-gun providers still mutate icon state/update held icons; thinktank recharge explicitly redraws its gun and its module overlays need joint migration. This is a supported but broader follow-up lane requiring charge, redraw and cell-swap regressions. No optional appearance source was edited.
