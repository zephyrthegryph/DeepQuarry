# Base-variable burn-down

Canonical branch: `codex/base-vars-burndown`. Repairs are prepared on `codex/base-vars-burndown-repair` in a separate worktree so the running 8a95eeaad4 gate keeps its original source.

## Source result

The initial baseline was 539 rows. Current master 3240597db6 has 537; this source has **386**. It removes **151 identities from current master**, with **zero additions**, including duplicate multiplicities. The total reduction from the original baseline is 153, including two upstream removals. No ALLOW or ceiling was added.

The first cohorts move transforms, emotes, body/status snapshots, profile preferences, behaviour state, heat samples, borrowed references, material emission samples, lighting and voice/butchery configuration into their actual native owners. Per-cohort handoffs are historical checkpoints; these counts supersede them. Master's newly reactive redgate requirement retains its real tracked field and setters rather than this branch's earlier sparse version.

The next cohort removes another 23 fields: machinery interaction settings (5); object break configuration (3); radiation/speech configuration (3); item retention/tooling/combat configuration (4); augment return association (1); optical configuration/view association (2); unused mob scratch fields (3); the obsolete item health placeholder (1); and spawn-temperature configuration (1). The native heat body remains the runtime temperature authority. Trait defaults, inherited explicit-null overrides and public map/VV copy-on-write routes are preserved. Existing implant tool ownership remains separate from the borrowed return relation.

## Verification and repairs

The original 8a95eeaad4 gate compiled production and tests without errors, passed DreamChecker and ratchets, but failed its boot/runtime checks. It is not a successful stamp. Its old 584 conversion-row differences are 23 aborted constructor dumps, not completed behavior captures; none was blessed.

Prepared repairs add missing real static roots and static markers, restore the original HUD deadline boundary, correct clock and transform test assumptions against the actual native clocks/original image implementation, isolate fixture archive/counter state, compose prone density with independent sources, normalize native identities before look probes, and reapply the approved internal-storage admission-before-link fix. The hidden slime-state reuse guard remains strict.

The repaired source and the 23-field cohort passed generation and all ratchets before the final equivalent time-define formatting. The focused repair list contains 42 explicit selectors: failed tests, newly affected regressions, and the mandatory requirement/conversion pins. No replacement runtime pass, final DreamChecker result, lane-ready stamp or push is claimed yet. Test worlds remain serialized.

## Remaining contracts

386 baseline rows remain. Five burning fields are retained because granted capability draw providers cannot yet preserve the arbitrary retained appearance contract. Four lighting references retain disposal-phase ownership. Reactive borrowed references need published sparse relation dependencies; owned references must retain replacement/clear/contained semantics. No shadow record, unproved sparse association, or manual qdel glue substitutes for those contracts. Later cohorts are source proposals until their native ownership and phase proofs are complete.

Live-client optical rendering is not covered by the headless lifetime tests; connected-client offset code is unchanged. The documented optical cleanup fix prevents a lost viewer or old view teardown from leaving stale zoom state or clearing a replacement view.
