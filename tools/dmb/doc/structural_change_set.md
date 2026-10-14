# Structural change set

Status: design, 2026-10-13 (lane `dmb/incr5`). Target from DESIGN.md §6.1: a new var/proc or a
changed default in at most 2.5 s with the daemon running, output byte-identical to a fresh build
of the same compiler.

## Problem

A body edit is cheap because the runner has one typed fact ("only these bodies changed") and
every later stage consumes it. A structural edit has no such fact. Each stage notices "something in
the declaration skeleton changed" and re-runs over the whole program, then recovers reuse item by
item through memo keys and receipts. Item-level reuse is already high (48,681/48,681 lowering hits,
210,222/210,223 initializer hits on a leaf var), so the cost that remains is the *checking*:
258k members walked by tree resolution, ~350k domain versions recomputed for the lowering memo,
210k initializer receipts replayed, every ABI unit re-admitted, every map/resource order rebuilt.

## The change set

Computed once per request, right after declaration parsing, from the retained previous
`KeyedDeclarations` and the current one (`KeyedDeclarations::delta_since` already gives the rows):

```
StructuralChangeSet {
  types:   per owner path: Added | Removed | ParentChanged { old, new } | MembersChanged
  members: per (owner, name, kind): Added | Removed | DefaultChanged | MetadataChanged
           | ModeChanged
  order_changed: bool          // declaration order moved (rows reordered, not edited)
  names:   set of member names touched (any owner)
  defines: per file: changed macro names, and the files whose expansion read them
  maps:    changed .dmm paths
  bodies:  changed procedure bodies (existing body-patch input)
}
```

Derived queries every consumer uses:

- `affected_types()`: changed owners plus all their descendants (current hierarchy, and the old one
  for removed/reparented types).
- `domain_dirty(ReadDomain)`: `OwnerHierarchy(t)` is dirty iff `t` is in a reparented/added/removed
  subtree; owner+name domains (`OwnerCallable`, `OwnerVariable`, `OwnerScalar`) are dirty iff the
  name is in `names` and the owner is an affected type, or the hierarchy of the owner is dirty;
  name-only domains (`GlobalProc`, `UniqueStaticVar`, `MemberCallableName`, ...) are dirty iff the
  name is in `names`; `Tree` and catalog domains are dirty on any structural change.
- `is_empty()`, `only_defaults()`, `only_bodies()`.

The set is conservative: any row the classifier does not understand marks the request
`Unclassified(reason)` and every consumer takes its full path. That keeps correctness reducible to
"the full path is correct" plus "a dirty predicate never says clean for a domain whose answer
changed".

## Consumers, in payoff order

1. **Domain versions (lowering memo, initializer receipts, ABI admission).** The tree carries a
   `DomainVersionCache` (domain -> `Option<u128>`). A new tree inherits the previous tree's cache
   minus every entry for which `domain_dirty` holds; misses are computed by the existing issuer and
   inserted. Within a request each domain is computed once instead of 3-4 times per memo hit
   (`versions()`, `accepted()`, the observer loop, `changed_read`). Version values do not change
   meaning: an inherited entry is exactly what the issuer would recompute, which the debug check
   (`DMB_DOMAIN_CACHE_VERIFY=1`) asserts by recomputing every inherited entry.
2. **Tree resolution.** Default-only changes already update in place (`MetadataDependencies::update`).
   Extend it to added/removed members and types: dense `MemberId`s follow declaration order, so an
   insert renumbers later members. The update rebuilds the arena by splicing the changed owners' rows
   into the retained arena in fresh-build order, remaps `previous` links with an old->new id table,
   and reruns previous/metadata resolution and certification only over `affected_types()`.
   Fallback: parent changes outside a leaf subtree, duplicate declarations, engine changes.
3. **Initializer classification.** Receipts for writes whose owner is not affected and whose
   recorded domains are all clean are accepted without replay; only affected owners re-classify.
   Class projection is recomputed for affected types only and spliced into the retained projection.
4. **ABI and roster.** Units of procedures whose owner is unaffected and whose ABI read domains are
   clean keep their admitted layout; only affected owners and added procs are recomputed.
5. **Defines.** The directive memo records, per expanded file, the macro names its expansion read.
   A define edit re-expands only files that read a changed macro; others replay. Today the whole
   directive plan is re-matched (~0.8 s).
6. **Maps.** Only changed `.dmm` files are re-parsed; map projection splices their rows.
7. **Link/encode.** For default changes the retained DMB is patched in place (initializer proc
   bytes and string table tail). For added/removed procs/vars a patch is possible only when the
   fresh-build ID order places the new entry at the end of its table; otherwise relink. Making ID
   order patch-friendly changes fresh output too, so it is a separate, explicit decision.

Every consumer logs `change set: <stage> full (<reason>)` when it falls back.

## Correctness

- Parity is always against a fresh build of the same compiler (DMB and RSC bytes).
- `six_session` byte-parity tests per scenario: edit, revert, and chained edits (leaf var, default,
  new proc, removed proc, removed var, new type, define, map).
- The harness byte oracle runs on every measured row.
- `DMB_DOMAIN_CACHE_VERIFY=1` recomputes inherited cache entries and panics on a mismatch.
