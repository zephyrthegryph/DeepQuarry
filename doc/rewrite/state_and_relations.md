# State and relations

Status legend: **[built]** on `rewrite/dx-framework`; **[in progress]** on `rewrite/f-reactions`
(owner W1); **[planned]** designed only. Overview: [foundation.md](foundation.md).

## 1. State

State is plain vars. Configuration is a type var; behaviour is an override; a table is a proc that
returns a list. A var that other code depends on is **tracked**.

| API | Meaning | Status |
|---|---|---|
| `TRACKED(type, var)` | Generates `set_<var>()`. The setter compares, commits, and **publishes `(src, key)` only when `READERS(src, key)` is non-empty** (`tracked_changed()`). CI rejects writes outside the setter. | [built, A1] |
| `TRACKED_BRIDGED(type, var, CHANNEL)` | Bridge: TRACKED that also raises an OM channel, only for a var an OM stage `wake_on` or `om_watch()` still reads (the machine pipeline's CHANGE_MACHINE_SETTINGS). Removed with S4. | [built, A1] |
| `PUBLISH_CHANGE(E, key)` | Publishes a change key that is not one var (a mob's `MOB_KEY_STATUS`, `MOB_KEY_HEALTH`, ...: the Life presentation reactions read them) when someone reads it. `OM_FIELD` setters publish their var key the same way. | [built, A1] |
| `SETTER(type, var)` | Registers a hand-written setter with side effects. | [built] |
| Tracked base vars | `anchored`, `density`, `opacity` (`set_anchored` / `set_density` / `set_opacity`, hand-written SETTERs). A change publishes the var key; `tracked_bridged_changed()` also raises the channel the type's declared field names (machine / mob) until S4. | [built, B4] |
| `PUBLISHED_BY(type, var, KEY)` | Names the key a var's producers publish (a bit field set through a helper: `hud_updateflag` via `flag_hud_update()`); generated reads use KEY for it and the lints accept it as published. | [built, B4] |
| Machine state keys | `MACHINE_KEY_POWERED` (NOPOWER, written by `set_powered()`), `nameof(use_power)` (`set_use_power()`), `INTEGRITY_KEY_BROKEN` (BROKEN, written by `atom_break()` / `atom_fix()`). | [built, B4] |
| `publish_change(datum/E, key)` | For the rare write outside a setter (raw FFI data, engine callback). Relation writes publish both ends. | [built] |
| `READERS(src, key)` | Union of the static per-type reader mask (composed from `reactions()`) and the instance's dynamic readers (`observe()`). | [in progress] |
| Generated reads | `code/_generated/reads.dm`, written by `tools/ci/derived_reads_lint.py --fix-generated`; CI checks freshness. The reads of `draw()`, `tgui_data()`, `should_run` and `push_to_rust` bodies become `reactions()` entries. | [in progress] |
| `native(key...)` | Read spec for a Rust-owned value; delivery is in [rust.md](rust.md). | [in progress] |
| `cap_set` / `cap_has` / `cap_data` | Capability state bits and per-holder data. | [built] |

**Coalescing.** A write takes effect immediately. The framework coalesces only *idempotent
follow-up work* keyed by entity and output (appearance, HUD, open UI, derived cache, Rust push).
An explosion still applies a damage packet to every target; several hits on one target stay
ordered; only the target's HUD refreshes once afterwards. Bulk processing may be sliced across
ticks; each completed mutation stands alone, so an error in a later slice cannot strand earlier
invalidations behind an open global batch. See [reactions.md](reactions.md) for the contracts.

**Staleness.** Direct-write CI, the generated reads and the drift audit reduce missed changes but
cannot make them impossible while helpers, native state and engine callbacks exist. Critical work
is tested by mutating each declared input; a rule with hard-to-declare dependencies subscribes to a
broad owner change plus a bounded safety resample.

## 2. Relations

A relation is a typed link with a **kind**, declared in the per-type `relations()` table. The
framework writes the reverse end, cleans up both ends on destroy, and publishes a change on both.

```text
/obj/machinery/thing/relations()
    . = ..()
    . += rel_one(nameof(area), /area, kind = PAIRED)
    . += rel_many(nameof(linked), /obj/machinery/other, kind = REF)
```

| Kind | Meaning | Lifetime rule |
|---|---|---|
| `REF` | A points at B. | Cleared when B is deleted; B does not know. |
| `PAIRED` | Two-sided; write one side. | Cleared on both ends when either is deleted. |
| `OWNED` | A owns B. | B moves and dies with A; replacement disposes of the old value by policy. |

Internal kinds live on the same store and are used by the framework rather than declared by hand:

| Internal kind | Backs |
|---|---|
| `GRANT` | `grant(target, what, source, duration=)`: capabilities, modifiers, traits, with a source count. |
| `LISTENER` | `observe(source, trigger, listener, handler)`. |
| `MEMBER` | System membership: `join(system, E, source)` and capability-driven enrolment. |
| `TIMER` | `after(owner, delay, handler, key=, clock=)`. |
| `CONTAINED` | Containment and ledger location. |

**Source counts.** Two features can grant or enrol the same thing; removal by one source leaves it
in place until the last source leaves. This applies to GRANT and MEMBER.

**Shared values and private copies [built, A1].** There is no `shares()` declaration: a var holding a registered
singleton (REGISTRY_TYPE) or a flyweight (an interned capability, reaction, recipe table, declaration entry:
`GLOB.flyweight_types`, code/datums/ownership/flyweight.dm) says so by its type (`var/list/datum/stack_recipe/recipes`);
the ownership lint and the destroy leak check skip it. A var holding a registered prototype or a private copy of one
(the former `proto()`) is `rel_one(nameof(seed), kind = RELK_OWNED, policy = OWN_PRIVATE_COPY)`: teardown deletes
private copies only. Relation kinds stay REF / PAIRED / OWNED.

**Grants [built, A1].** `grant(target, what, source, duration)` / `revoke()` / `granted()`: `what` is a verb path (the
verb store gives the verb while the source holds it), `hidden_verb(path)` (hides it), a capability type (granted
capability), or any other value (a plain RELK_GRANT ledger entry). A text source is a shared `verb_source()`; a datum
source's deletion drops its holds.

**Starting occupant [built].** An owned relation may name what it starts with:
`rel_one(nameof(cell), /obj/item/cell, kind = RELK_OWNED, policy = OWN_SPILL, starts = nameof(cell_type))`.
`starts` is a type, a list (`list(/obj/x = 2)`) for `rel_many`, or `nameof()` a type var, so a map or subtype
override picks the type; a path already in the var (a map edit) wins, an instance in it makes nothing. It is made at
init, before gas, reagents and the subtype's `Initialize()` body ([lifecycle.md](lifecycle.md) section 9); the
policy decides its teardown as for any owned value. `DECLARE_DEFAULT_CHILD` is a wrapper over it.

**Writing.** `rel_link(src, nameof(var), B)` / `rel_unlink()` (never a string name, never `link()`,
which is a BYOND built-in). Ownership writes go through the `own_*` accessors today (`own_set`,
`own_clear`, `consume`, `replace_with`). Typed `rel_one`/`rel_many` with kinds: **[built]**. The declared `type` is stored on the entry
(`OWNE_TYPE`) and every write (`rel_link` / `rel_set` / `rel_add`, `own_set` / `own_add` / `own_put`)
checks it with `own_type_ok()`: null or an `istype()` of the declared type is written; anything else
is refused (the accessor returns null) and reported through `OWN_REPORT` (a `stack_trace`, which fails a
test run; on a server it is logged once per message).
`relations()` with `back =`, `other_deleted =`, `on_unlink =`, `keyed =`, `watch =`, and the
ownership store: **[built]**. The old `ownership()` table and `OWN(...)` forms become `relations()`
entries with kind `OWNED`.

**Hops in reads.** A reaction may read through a relation (`rel(link, nameof(/type::var))`,
`rel_each(list_link, ...)`). A hop through a plain var is refused when the type's table compiles.
Linking or unlinking rebinds the dependent reads.

## 3. Lifetime

Destruction stays a framework transaction ([lifecycle.md](lifecycle.md)): declared refs are
cleared, owned children disposed by policy, and listeners and timers are torn down because they are
relations. A `Destroy()` should have nothing left to do by hand except what no relation kind
expresses.

## 4. Pools

Per-event allocations (damage packets, notices, operation contexts) are `/datum/pooled`; see
[pools.md](pools.md).
