# D5 declaration cleanup

Branch `codex/D5`, based on `origin/master` at `274d176a88`.

The late-join landmark uses a declared conditional registry membership instead of joining imperatively in `Initialize()`. Its instance-specific `simulated` setting remains. `dq_d5_landmark_registration` checks both registry views, ordinary-marker exclusion and actual deletion cleanup.

The common task rules reserve relation/ownership declarations. The owned-child sites need `starts =` on exactly those declarations, so they are retained rather than disguised as setup work. They cover the hotspot's group, frame circuit, flipper pAI, telecube mate, living body, MMI-holder brain, item identity, two energy-gun cell paths and archaeological talking atom. The archaeology file is being handled separately by A1; D5 does not duplicate that algorithm conversion.

The archaeological reagent row is interleaved with constructing and decorating a randomly selected find; it is part of A1's replacement-generation job. There is no behavior-preserving isolated default reagent declaration for that conditional amount.

The transport `Initialize(list/assets)` is a manually invoked configuration callback, not an atom's creation lifecycle. `after_init()` would run at transport creation rather than after its current asset list is supplied, changing captured preloads and configuration reload behavior. The existing `after()` stays; the callback is not renamed to evade the lint.

Baseline counts and verification are pending. No new annotation or baseline raise; no merge or push.

## Current verification barrier (2026-10-15)

Generation and the owned `decl` check pass (47 to 46 findings), but full ratchets
reject the new `registry(..., when = is_latejoin_landmark)` predicate: its read of
inherited `name` adds one `untracked_inputs/stat_input_untracked` site (86 to 87).
The original imperative join was a boot-time snapshot; native conditional membership
needs reactive publication of that name, or a declared boot-snapshot membership form.
Neither can be introduced here without changing protected tracking declarations or
adding debt. No read is hidden, no annotation or baseline is raised, and no compile
or test world was run for this refreshed branch. D5 is blocked and is not stamped;
the other scoped retained sites remain described above.
