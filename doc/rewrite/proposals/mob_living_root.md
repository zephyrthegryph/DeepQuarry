# Proposal: where do `/mob/living` ops live? (K23)

Status: option B approved and landed (rewrite/living): one `living_abilities()` line in the block, the entries in `code/library/mob/living_abilities.dm`. Option C is still the end state.

## The problem

A type has exactly one `CAPABILITIES(T)` block; a second one is a gen error (`declaration_block` lint, `TWO_HINT`). The one for
`/mob/living` is in `code/modules/combat_ai/integration/mob_living.dm`, which is protected combat AI code. It is the whole
composition root of every living mob (clocks, owned slots, `ref_many`s, `drag_onto`), not an AI block, but it sits in the AI folder.

So an ability that belongs to every living mob (healing rainbows, shred limb, butchering, the revert from a beast form, `yank_out`,
the dog-borg and slug escapes, `lick_wounds` on non-humans) has nowhere to declare its `op(...)` without editing protected AI code.
The 40 or so timed leftovers in `/mob/living` procs are blocked on this and nothing else (they are listed under `living_powers.dm`,
`station_special_abilities.dm` `_living_` procs, `species_shapeshift.dm`, `mob.dm:1013` in `.lane/w9*.leftovers`).

A granted `/datum/capability` is not a way round it: `sem/keys` resolves a `perform_op("key")` literal against the `op()` entries it can
find, and an op declared by a granted capability's `entries()` is not found, so the call site fails the key check.

## Options

### A. Move the root to `code/library/mob/living.dm` (a pure move)

Cut the block and the two var lines it needs next to it out of the AI file into the mob library; the AI file keeps its `ai_brain`
slot, its getters and `Initialize()` hook. The move itself is mechanical, but it edits (deletes lines from) a protected file, and the
`owns_one(nameof(ai_brain), ...)`, `on_change(STAT_AI_AUTHORITY ...)` and `STAT_RELEVANCE` entries are the AI's and would have to stay
in the AI file, which by the one-block rule they cannot. So A forces a split of the block, which is option C anyway.

### B. The block includes a library proc of entries (recommended)

The pattern is already in that block: `living_action_status_contributions()` is a plain proc returning entries, declared in the library
and named once in the block. Add one line,

```
CAPABILITIES(/mob/living)
	...
	living_abilities()
```

and put the entries in `code/library/mob/living_abilities.dm`:

```
/proc/living_abilities()
	return list(
		op("healing_rainbows", menu(), ...),
		op("shred_limb", ...),
		section("butchering", "doc", op("butcher", ...)))
```

(`section(name, "doc")` groups a type's own entries, doc section 11.) Every `/mob/living` op then lives in the library, one file per ability
group if the proc grows (`living_abilities()` returns `living_butchering() + living_shapeshift() + ...`), the analyzer resolves the keys
as it does for any `op()` in a `CAPABILITIES` block, and handler procs stay on the content types as for any other op.

Cost: one added line in the protected file, a single approval, no other change to it. No analyzer work. The line cannot break the AI
(it adds ops; the AI reads none of them), and the block's order is unchanged.

### C. Multiple contributing blocks merged by gen

Let a type have the one root `CAPABILITIES(T)` and any number of `CAPABILITIES_ADD(T, lane)` blocks in other files; `analyze gen` merges
them in file order, and the lints (`declaration_block`, `ownership`, key resolution) treat the union as the type's block. This is the right
end state (the doc's "one type groups its own entries with `section()`" read across files, and it also frees `/mob`, `/obj/item`, `/atom/movable`
where other lanes will hit the same wall). It touches the analyzer (`declaration_block.rs`, `decls.rs`, `gen.rs`, the key index) and the
doc, and it needs a rule for the order of entries and a way to see all contributors in `explain_type`. About a week of work and a doc decision
(section 21), so not for this wave.

### D. Let `sem/keys` resolve granted capabilities

Resolve a `perform_op` key declared by a `/datum/capability/x/entries()` that the call site names (`perform_op(user, src, CAP_KEY("x", "op"))`).
It keeps all new ops out of every root block but makes the key check depend on a runtime grant and breaks the "an op is where its type declares it"
reading that `explain_type` and the menu golden rely on. Rejected.

## Recommendation

**B now, C later.** B is one line in the protected file, follows the precedent in the same block, and unblocks the whole class today; the
mob lane can then convert the `/mob/living` leftovers into `code/library/mob/living_abilities.dm` without touching AI code again. C is the proper
design and replaces `living_abilities()` with a contributing block when it lands (the entries move unchanged).

Needs from the user: approval to add the one line `living_abilities()` to `CAPABILITIES(/mob/living)` in
`code/modules/combat_ai/integration/mob_living.dm`. Until then the `/mob/living` timed leftovers stay legacy.
