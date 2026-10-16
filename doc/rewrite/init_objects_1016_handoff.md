# Object initializer burn-down

Branch: `codex/init-burndown-objects`.

The analyzer has reduced the init baseline from 4,111 to 3,841 rows,
including `code/game/objects` from 571 to 301. Exactly 270 rows were
removed and none added. Source declarations and regression fixtures are
committed; compilation, DreamChecker and focused lane-ready proof are pending.

The leaf setup, ownership, constructor and ordering changes and retained
contracts are listed in `init_objects_nonitems_1016_handoff.md` and
`init_objects_items_handoff.md`. Retained initializers need their original
pre-parent, mapload, constructor-argument or lifetime boundary; they were not
moved into wrappers to silence the lint. No new ALLOW was added.

## Additional leaf cohort (verification pending)

Three further baseline rows have source conversions prepared, not yet counted by
the analyzer: the two permanent candles light through native completion-phase
setup, and the integrated-circuit implant links its declared assembly there.
These types have no retained descendant Initialize tail to reorder. The candle
message, glow, fuel exemption and snuff/re-light behavior remain unchanged; the
assembly remains owned by its implant, with the same non-owning reverse link.

`dq_init_objects_permanent_candles` checks both real candle constructors, actual
lit appearances, unchanged fuel, snuff and re-light behavior, plus an ordinary
unlit control. `dq_init_objects_circuit_implant` checks actual child identity,
location, reverse link and destruction ownership. Both are in the already-wired
`dq_init_objects_weapons_tests.dm`. No compile, generation, baseline update or
test was run for this supplemental cohort.

## Consolidated follow-up (verification pending)

The first native gate compiled with zero errors and zero DreamChecker diagnostics and passed ratchets, but reported 81 passing and six failing tests. The two constructor fixture assumptions have been corrected (forced deletion for a component-owned light; deterministic real-human starting nutrition). Master-only operation key changes are documented separately. The look failures exposed independent fixture sampling/isolation defects; these have explicit regressions and are not hidden with blanket snapshot updates.

Additional source migrations use existing native setup, owned factories, `param(apply=...)`, and a real mapload-aware persistence capability. They cover material weapons, tanks, communicator presentation, starting item actions, temporary constructor inputs, persistence eligibility and ghost addresses. Qualifying remaining initializers are retained without new ALLOW annotations. Exact final counts and test results await the consolidated verification.

## Current verified source result

The final source pass shrank init from **4,111 to 3,712** rows globally; all 399 removals are in code/game/objects, which fell from **571 to 172** rows. Counter comparison against origin/master proves zero added baseline identities (including duplicate-row multiplicity). Full ratchets pass with no unused annotations. Three focused semantic-holder Rust regressions and four native draw-contract proof regressions pass. The previous initial gate had clean production compilation and DreamChecker, but the expanded final cohort has not yet had its DM verification; the serialized base-vars gate runs first. No stamp or push is claimed.
