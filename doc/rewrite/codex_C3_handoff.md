# C3 silicon entry sweep

Source-only handoff; root owns generation, compilation, tests, baseline updates and the gate.

## Inventory

15 baseline occurrences outside machinery, onclick, helpers and modules. Five fingerprints removed; ten remain. This is a source inventory, not an analyzer result.

| File | Before | After | Change |
|---|---:|---:|---|
| game/mecha/mecha.dm | 1 | 0 | Actor supplies real cockpit credentials: human active hand, ID and belt in original order; borg internal ID; other actors none. |
| game/objects/items/devices/scanners/health.dm | 1 | 0 | Scanner needs native silicon actor-kind or existing dexterity requirement, with identical refusal text. |
| game/objects/items/devices/vacpack.dm | 1 | 0 | Actor supplies actual menu ports and module destinations; borg module bag retains precedence over carried bag. |
| game/objects/structures/watercloset.dm | 1 | 0 | Native non-borg allowance composed with the original player/body requirement for borgs. |
| library/structures/climb.dm | 1 | 0 | Ordered requirements preserve gate and solidity refusal before native AI no-hands refusal, then the remaining physical checks. |

Vacuum output callbacks also remove two unbaselined robot type branches by retrieving actual actor-owned destinations. Module lookup and carried lookup remain separate, preserving every original relation setter occurrence and precedence. No gameplay keys, delays, messages or state setters changed. Requirement pin graph differences, if any, are caused only by replacing compound callbacks with ordered/composed native requirements; output refusals must remain identical.

## Focused tests

New file: code/modules/unit_tests/dq_object_silicon_boundary_tests.dm. Include after dq_silicon_provider_tests.dm. No new production files or production includes.

- dq_silicon/c3_requirement_routes: actual scanner composition permits real AI/borg, rejects dog with identical text; toilet refuses clientless borg but permits non-borg; real railing's ordered requirements give AI the no-hands refusal.
- dq_silicon/c3_mecha_credentials: real human hand ID and borg internal ID grant/refuse as actual access changes; AI has no physical cockpit credentials.
- dq_silicon/c3_vacuum_ports: exact port order and actual carried/module destination identities.

Existing coverage: dq_climb/a_crate_takes_three_and_a_half_seconds and dq_climb/a_cliff_is_too_steep_without_climbing_shoes. Root should include requirement and conversion pins in the gate.

## Remaining occurrences and exact blockers

| File | Remaining contract |
|---|---|
| items/devices/flash.dm | Robot animation is unreachable after the carbon-only early guard. Deleting it would delete protected existing setters and a relation call, so the entire old block is retained under this task's strict scope. |
| items/robot/robot_parts.dm | Shell remote-MMI self-replication check is one branch inside a multi-part legacy construction effect. It needs per-part input ops with the shell restriction attached to remote-MMI insertion, preserving OP_PASS and all prior part processing. |
| structures/girders.dm | Explicit construct_wall_wait invocation computes 1.5-second borg versus 4-second other timing. A native actor-kind timing selection must also migrate that explicit invocation; disguising the kind check inside another duration helper is not a conversion. |
| buckling.dm | Shared user_buckle_mob controls actual dragged occupant separately from actor and has round-start/message ordering. Needs buckle operation/context migration across its callers, preserving forced/silent and actor-versus-rider roles. |
| effects/mines.dm | Public interact() rejects AI while two tool ops call it. A native split must migrate the public window entry and tool routes together; merely pre-gating tools would leave direct interact access changed or allow generic hit fallback. |
| items.dm | No-slot silicon unequip bypass serves gripper inventory, independently of normal slot accessibility. Needs the shared inventory/provider unequip consumer migrated, not a wrapped type predicate. |
| items/weapons/handcuffs.dm | can_place is shared by attack entry, delayed completion and legcuff/bola override: borg adjacency replaces aggressive grab, while self bypass applies to every kind. Needs coordinated actor grip provider and all attack consumers, outside a local op-only edit. |
| items/weapons/storage/storage.dm | Shared try_quick_empty restricts human/borg, then checks incapacity, adjacency and belly location; native storage capability owns its op in library/containers outside C3. Requires caller and public empty entry migration together. |
| items/weapons/tape.dm | can_place serves native timed eye/mouth ops, their completion checks and legacy attack hand-cuff path. Native robot allowance on just the timed op would fail again during completion and change legacy cuffing. Requires common grip/attack consumer migration. |
| structures.dm | Public can_touch supplies ordered adjacency, restraint message, status and AI no-hands message to shared structure callers. Requires shared physical touch provider/context migration across those callers; a native kind predicate wrapper is explicitly rejected. |

No build/test jobs were started by this worker. git diff --check passes. Protected source-line multiset comparison against HEAD reports zero losses for existing setter calls, relation/ownership calls and TRACKED/OWN/REL declarations. The unreachable flash block was restored byte-for-byte from HEAD as requested.

Root preflight: generated trackedcheck and silicon check clean; silicon_entry baseline103 ->98 (five removed). Testmanifest wired. Runtime gate pending.

## Existing access bug found during verification

`/obj/mecha/check_access()` is unchanged from `origin/master` 4ab2e15fe1.
Its internals-access branch returns true for a matching access, then falls through
to a final true even when a present ID has no matching entries. This is an existing
security-access bug, not a new intended behavior. This migration preserves it;
the fixture checks the real card provider, present-card parity, and real refusal
after the human drops the credential. Fixing the access policy is a separate task.
The first gate passed 46 tests; its missing fixture capability context caused six
failures. The repair passed 51 with one incorrect old-access expectation. The final
failure-only mecha gate is pending; these earlier results are not a stamp.
