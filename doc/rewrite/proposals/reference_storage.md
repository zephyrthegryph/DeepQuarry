# Reference storage: relations or weak refs, nothing else (approved 2026-10-12)

A deleted object is collected only when nothing references it. A reference that nothing clears keeps the
object alive past `qdel()`; the collector fails its check five minutes later and hard-deletes it, a
full-world reference walk (150 ms and up on the live server). Every hard delete on the live server is one
such reference.

## The rule

Every stored reference to an atom or datum is one of two kinds:

| Kind | Forms | On delete |
|---|---|---|
| Declared relation | `owns_one`, `owns_many`, `ref_one`, `ref_many`, `links()`, `slot()` in the type's `CAPABILITIES` block (the legacy `owns()` / `rel_one()` / `rel_many()` tables and `OWN`/`REL` lines still declare them on master) | the destroy transaction clears both ends; owned values are disposed of by `on_destroy` |
| Weak ref | `entity_handle(x)` read back with `resolve_handle(h)` (the final spelling is `ref_token` / `resolve_token`, final_api.html section 6) | nothing to clear: the handle stops resolving |

"Stored" covers every place a value outlives the proc that put it there:

- a var (instance, `static`, `global`, `GLOBAL_*`);
- a list's members, assoc keys and assoc values, on a var or in a proc's `var/static/list`;
- a sparse slot;
- a deferred call's arguments: `after()`, `every()`, request and job payloads already capture every datum
  argument as a handle (`capture_args()`, `code/engine/time/handles.dm`); `CALLBACK` is banned outside the
  core (the `ownership` lint);
- caches, pools, queues, indexes: key by a handle, an id or a type, hold handles.

Not references, so free: locals and local lists (scratch for one call); turfs and areas (never deleted);
registry and flyweight instances, kernel systems and controllers (never `qdel()`ed); values (`/image`,
`/mutable_appearance`, `/icon`, `/matrix`, `/regex`). A pooled record (a notice, a context) holds its
entities for one delivery and is reset on release.

### What to write

| Today | Write |
|---|---|
| `var/obj/item/cell/cell` set by hand, cleared in `on_destroy()` | `owns_one(nameof(cell), /obj/item/cell)` (or `slot()` when it sits inside the holder) |
| `var/mob/user` pointing at something it does not own | `ref_one(nameof(user), on_unlink = ...)` |
| two vars that name each other | `links(/A::a, /B::b)` |
| `var/list/members` filled with `+= x` | `ref_many(nameof(members), /type)` (or `owns_many`) and `rel_add()` / `rel_remove()` |
| a global or system list of live objects | a `membership()` registry, or a `ref_many` on the system |
| a cache keyed by an object | key by `entity_handle(x)` (or the object's id), store handles |
| a waiter or deferred record holding its target | `entity_handle(target)`; `resolve_handle()` at fire time, drop the record when it is null |
| a reference that must survive only one call (`ending_causes`) | drop it in the same call that set it, whatever path the call took |

## The lint

`stored_refs` (`tools/analyze/src/lints/stored_refs.rs`, scopes in `tools/ci/lint_scopes.toml`) reads the
typed model (the full dreammaker parse):

- `var`: a var whose declared type is an atom or datum (not a turf, an area, a client, a registry,
  flyweight, system or controller type) that no relation declares, reported at the declaration;
- `list`: a list var, global or proc-static list that some proc fills with a value whose static type is an
  atom or datum (`L += x`, `L |= x`, `L[k] = x`, `L[x] = v`, `L.Add(x)`, `L.Insert(i, x)`, `L = list(x)`,
  and the LAZY* macros, which the parser expands), unless a many relation declares it. The static type is
  what the model can say: `src`, `usr`, a parameter, a local, a var reached by `a.b`, `new /type`, a typed
  list's element, a proc declared `as /type`. A value from an untyped call is not seen: the lint
  under-counts, it never guesses.

The reference machinery itself (relation tables, handles, the lifecycle transaction, the collector) and
tests are exempt by path. The baseline (`tools/ci/stored_refs_baseline.txt`) is shrink-only:
`analyze baseline --update --lint stored_refs` after each wave. No new `ALLOW(stored_refs)`.

Seeded 2026-10-12: 1,768 sites (var 1,391, list 377); 1,737 after generated output was exempted (var 1,374, list 363).

## The GC sweep test

`/datum/unit_test/dq_gc_sweep` (normal tier, `code/modules/unit_tests/dq_gc_sweep_tests.dm`) creates and
deletes a representative set (machines, items, a human with an outfit, simple mobs, a window datum opened
and closed, HUD screens, lights) and, once the collector's filter pass has run, checks that no subject is
left in its check queue with any reference besides the queue's own. A surplus reference fails the test and
runs the reference finder on that object, so the log names the holder. No waiting for the collector's
five-minute check. The judgement is plain zero for every subject: there are no per-family baselines.

Two things the test depends on, both learned the hard way:

- Count in a proc of its own, before reading anything from the object. A frame that has read a var of an
  object (`D.gc_destroyed`) holds one more reference to it until the frame returns, so a count taken in
  the middle of a loop that also reads the object is one too high for every subject. That once looked like
  a hidden reference in machines, bags and living mobs (none of them had one) and was worked around with
  per-family baselines, a dropped cat and a throwaway last mob. `dq_gc_sweep_controls()` proves the count
  is exact (zero for a datum only its queue entry names, one for a datum a variable also holds) before the
  sweep trusts it.
- The sweep also checks `GLOB.latency_sweep_holders`: a deleted holder leaves it in
  `lifecycle_dematerialize()`, so the list does not keep dead machines, bags or mobs for the sweep cursor
  to prune.

## Waves

1. **Live hard deletes** (this lane's first slice). The live server's `PERF_PROFILE` garbage section
   (2026-10-12) named two types:
   - `/atom/movable/screen` [0x2000007], every round about five minutes after boot. The reference finder
     (unit-test logs) found it in the global `ending_causes` list: a caused ending whose `qdel()` never
     reached `ending_begin()` left its entry, which held the thing and its `by` (the screen) for the rest
     of the round. Fix: `ending_qdel()` records the cause, deletes, and drops the entry in the same call
     unless a collecting scope deferred the delete; every engine verb goes through it.
   - `/datum/tgui` (and its `/datum/tgui_window`): `close()` skipped `SStgui.on_close()` when the UI's
     window relation had already been cleared (a deleted window), so the spent UI stayed in `all_uis`,
     `autoupdating` and its object's `open_tguis`. Fix: the deregistration runs on every close. The client
     session's asset waiters held their target strongly; they hold a handle now.
2. Caches, pools and queues (the `list` rule's proc-static and global lists).
3. Deferred-call payloads and waiters that still hold objects.
4. Legacy instance lists (`var/list/x` of live objects) to `ref_many` / `owns_many`.
5. Object vars to `ref_one` / `owns_one` / `links()`, worst types first.

Each wave lowers the baseline and lands on its own.
