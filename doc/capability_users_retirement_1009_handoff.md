# Capability users and unused library retirement

Based on the pushed requirements branch at `730d7dcce9`. The verified medical conversion is merged, and the reviewed library retirement is applied. Final combined verification is pending.

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

## Task 2 verification — pending

- Exact tested revision/stamp: pending.
- Generation and production/test compile: pending.
- DreamChecker, lint and ratchets/analyze: pending.
- Focused retained/ported fixtures, native shields, assembly and radio behavior: pending; use the reviewed focus manifest, not the full suite.
- Scoped medical pin and actual medical clicks/menu/custody/refusals: pending if selected by root's final batch.
- Baselines: run the official shrink-only updater after the sweep; report actual before/after fingerprints. No added baseline/ceiling or debt ALLOW is authorized.

Generation and changed-source analyzer preflight passed. The official full-tree baseline updater only removes entries: `requirement_bool` **836 -> 834**, `base_vars` **905 -> 902**, `sys/dx_review` **170 -> 160**. A fingerprint comparison against the parent requirements tip confirms no new rows. No baseline or ceiling was raised and no ALLOW was added. The combined runtime focus contains 33 selected groups plus the mandatory handoff smoke/incremental pins; result remains pending.

No full suite is requested. Final handoff must distinguish this task's results from the earlier medical branch and name any remaining bridge or keybinding ownership work.
