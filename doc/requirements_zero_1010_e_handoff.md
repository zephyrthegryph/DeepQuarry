# Requirements burn-down E (2026-10-10)

Branch: `codex/requirements-zero-1010-e`. Stamped code commit: `64d889d2b5d4e39d717d57c73b684e16d9b72279`, tested against master `0a65e7c903`. Later commits in this landing contain documentation only.

## Conversions

`requirement_bool` shrank **306 → 193 (-113)**: machinery/power 47, food/industrial 36, clothing/mobs 30. Complete callback and override families return null or their original reason; ordinary Boolean query consumers keep their contract. Five already-native hydroponics adapters were folded, separately from the baseline reduction. No baseline or ceiling increased, no new ALLOW, no resolver/bridge/keybinding edits.

Old-code coverage recorded 30 concrete pin files (2,458 rows), with existing pins covering the scoped 73-root cohort. Initial old-code focused coverage passed after correcting a pump fixture's non-owning cell-view cleanup. Equipment-fit/rules tables were left for the subsequently approved native consumer protocol; no token substitution was used.

## Pin causes and fixture repairs

Master silicon Use rows follow `1b7d651912`, with master `13f4c81362` carrying the floor-light refresh. The older Equip evidence was a stale file; no resolver defect or Equip re-bless is claimed. Frame rotation follows master `b1c5e`. Master `a5f0148bfd`/`19329aee16` carried cabinet/controller pin changes. See `intended_changes.md` for per-class causes.

The pin producer now captures primary ownership diagnostics repeatably and cleans partial objects after failed construction. A controlled constructor regression verifies two genuine failures produce the same primary diagnostic and leave no partial fixture products. Nikki still has an invalid declared chest configuration; this landing makes its primary OWN diagnostic stable, not its production declaration valid.

The embedded airlock controller's fresh 68 rows exactly match the pre-`a5f0148bfd` golden. That master commit had recorded a constructor runtime caused by another radio recipient (delivery excludes the sender). Per-target cleanup removes partial recipients; the original rows are restored with the cause documented. The exact previous recipient is not identified. Docking-port runtime remains recorded, and no ownership framework fix is claimed.

Sleeper fixtures initialize persistent status caches before leak snapshots and preserve coalesce_runs. Generator fixtures clear synthetic fuel before destruction. Known smoke leaks remain in construction floor (coalesce_runs), canister_welder (test_prompts), and nutrition-heal contagion indexing; these are queued for the dedicated hygiene landing.

## Verification

The broad E batch passed all behavior assertions; its remaining failures were pin comparisons. After diagnosed master pin updates and producer isolation repairs, lane-ready completed **30 passed, 0 failed**: smoke, `dq_conversion_pin`, `dq_requirement_protocol_pin`, `dq_requirement_fifth_pin`, constructor diagnostics and fixture isolation. Result: `data/test-runs/20261010T232721_64d889d2b5_focused.json`.

Production: zero errors (43 existing DreamMaker warnings). Test build: zero errors (57 existing warnings); final snapshot-only repair reused it. DreamChecker: zero diagnostics. Analyze and ratchets clean. Incremental look pins: no changed types. No full suite or shard run. Git note `refs/notes/lane-ready` records the exact tested commit and base.

Remaining on this branch: **193** Boolean requirement fingerprints. Native consumer forms and REQ table conversion follow on later branches. Next audited cohort: 152 sites (67 items/body/NIF, 85 structures/records/subsystems), plus 41 further callbacks. Drafts and old-boundary coverage require review and verification on current master before application.
