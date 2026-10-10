# Capability users and unused library retirement

Based on the pushed requirements branch at `730d7dcce9`. The verified medical conversion is merged, and the approved library retirement is complete. Lane-ready stamped `51fd2a0296` against master `1e10a8130e`: all gates passed.

## Scope and counts

After the separately verified native medical conversion, retire the unused legacy capability-library leaves. The constructor inventory contains 37 production builder calls: 30 in unused leaves, one former medical builder, and six framework factory forwarders. Content/leaf builder calls therefore fall **31 → 0**. The six bridge factory forwarders remain: five in `code/datums/operations/cap_op.dm` and one in `code/datums/capabilities/library/_library.dm`. The count artifact classifies all six by their called symbol `cap_op`; the latter is the `lib_op` implementation forwarding to `cap_op`.

Framework `capabilities()` dispatch, the bridge and resolver remain live. Two keybinding references to `/datum/interaction/capability` remain for the ix-r2 owner; they are not content builders and are not removed by this task.

By called symbol, production constructor calls are `cap_op` **10 -> 6**, `lib_op` **25 -> 0**, `cap_use_self` **2 -> 0**, and `cap_use_at` **0 -> 0**. The one production `cap_slot` call and one content `capabilities()` override, both medical, are zero. Retained bridge sites are `_library.dm:27`, `operations/cap_op.dm:225/230/234/238/243`, and `capabilities.dm:616`. The two external typed compatibility locals are `keybindings/adapters.dm:358/421`. Legacy table fixtures remain only in tests/benchmarks so the live bridge is still verified.

Retire **25 unused library leaves** and their DME includes: anchor, assembly, block, breakable, cell_holder, cover, emag, embed, entry_points, label, lock, panel, powered, presets, reach, rotate, sharp, signaler, smokable, stamp_target, toggle_state, tool_helpers, two_handed, type_trait and writable. Remove **23 test files whose sole subject is the retired leaf API**, plus their include/registration entries. Do not equate removal of obsolete API tests with additional gameplay coverage.

## Live contracts preserved

Retain `_library.dm`, access, checks, membership and gas_store. Their shared APIs still serve native access checks, slot/item reach, bridge refusals, registry membership and real gas-store ownership. Retain `dx_cap_library_api_tests.dm` with the live **slot_layer** regression and lib_slot fixture; remove only its dead cap_cover fixture, preserving layer/state/insertion/draw assertions.

Port table acceptance, per-holder capability data isolation and aborted cleanup, lifecycle gating and appearance refresh assertions to test-owned capability/data/draw fixtures. Keep all other operation-resolution groups; remove only `dx_cap_library_ops`, whose whole subject is retired builders. Preserve the benchmark refresh workload and tracing while removing its unused legacy machine-basics declaration.

Remove only dead leaf hook calls: obsolete breakable capability writes in atom_defense; the old assembly pulse callback; the old signaler callback; and the base `handle_shield()` fallback, which becomes FALSE. Preserve integrity updates/notices, real assembly host pulse, real radio receiving/logging and every subtype shield override. Remove the dead attached_assembly ownership entry together with its deleted field. Native `/atom/proc/claw_slash` remains independent and intact.

## Prior medical verification, separately attributable

The medical branch's stamped lane-ready result records **28 passed, 0 failed**, clean boot, production compile 0 errors / 36 warnings, test compile 0 errors / 50 warnings, DreamChecker 0 diagnostics and clean ratchets/analyze. That proves the preceding medical conversion; it does **not** verify this leaf deletion. Its scoped medical pin preserves plain clicks and silicon/ghost refusal text while replacing three bridge keys and eleven duplicate refused menu rows. No appearance snapshot rows were blessed.

## Task 2 verification

- Final stamped revision: `51fd2a0296`, master `1e10a8130e`.
- Generation passed. Production/test compile: zero errors, existing 36/50 warnings. DreamChecker: zero diagnostics. Ratchets and analyzer: clean. Boot gate passed.
- Broad focused run `a99104b50a`: **54 passed, 3 failed**. Medical slot/custody/refusal tests, scoped medical pin, retained slot-layer bridge, capability storage/cleanup, shields, assembly, radio and grenade tests passed. Result: `data/test-runs/20261010T012440_a99104b50a_focused.json`.
- Read and repaired the three failures: the missing-parts helper reads the legacy capability list, so its test-owned fixture uses that list; drone access reads the real native menu instead of an absent legacy op; medical resolution checks current plain clicks and named menu insertion/ejection with actual card custody. Production ranking was not changed.
- Failure-only repair `ad22719347`: **27 passed, 1 failed**. Missing-parts and medical resolution passed. The access test changed an untracked map/admin access list after caching a menu; its final fixture sets the override on a separate console before its first menu read and still asserts refusal with the worn engineering ID.
- Final failure-only lane-ready batch: **26 passed, 0 failed**, including mandatory smoke checks. Result: `data/test-runs/20261010T014541_51fd2a0296_focused.json`. Zero stale appearance types; no appearance snapshot rows were blessed.
- Two earlier attempts stopped at compilation without running tests: a helper was deleted with its obsolete test file, then the replacement membership expression needed parentheses. Both failures were diagnosed and repaired. One prematurely launched retry was cancelled; its surviving owned children were also stopped. No other agent's processes were touched.

The official full-tree baseline updater only removes entries: `requirement_bool` **836 -> 834**, `base_vars` **905 -> 902**, `sys/dx_review` **170 -> 160**. A fingerprint comparison against the parent requirements tip confirms no new rows. No baseline or ceiling was raised and no ALLOW was added. Documentation examples naming the removed cover/emag builders were updated to the actual native forms; the documentation lint passes.

No full suite was run. Remaining framework resolver calls are `interactions_for` (8), `op_legacy_candidates` (1), `cap_interactions` (4), `cap_dispatch` (2), and `allows_interaction` (2): **17**, all in the retained bridge/resolver framework. The two external typed consumers are ghost/AI keybinding adapters at `code/modules/keybindings/adapters.dm:358/421`. Construction/slot bridge definitions and compatibility fixtures remain for ix-r2. These are distinct from the zero production content constructor callers.

The access-menu cache can remain stale if an admin changes an untracked access list after opening the menu. This existing map/admin mutation limitation was observed while repairing the fixture; no cache invalidation or tracked-access migration was included here.
