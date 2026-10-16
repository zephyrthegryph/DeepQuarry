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

## Status (2026-10-13, end of lane round 2)

Landed, each consumer logging `native change set: ...` per request:

- **Domain versions:** demand certificates are carried for clean selections (about 750k per edit;
  0 to 964 dropped). A per-host memo removes about 1.1M repeat issues. Tree issue CPU went from
  16.1 s to 0.25 s.
- **Tree splice** (`metadata_splice.rs`): added, removed and changed member rows, including
  implicit callables, are spliced in fresh-build order with remapped dense IDs. It reuses the
  prefix chunks of the arena. It declines on type rows, a member on a new or implicit owner,
  duplicates, inherited redeclarations, overrides without a base, ambiguous intrinsic anchors, and
  anchors that would move an implicit callable. Verified equal to the full constructor
  (`DMB_SPLICE_VERIFY=1`) and covered by `metadata_splice_tests.rs`.
- **Store lock relief** (prerequisite for consumer 3): claims of already-claimed variants are
  counted atomically under a read lock, and the lease roster insert is deferred until the next
  roster read. Admission versions get a per-thread first-level cache. Initializer classification
  went from 2.8 s to 1.0 s.
- **Selection-owner publication** skips the demand-store sweep when no type was removed. There is
  a full sweep every 32 revisions, because pruning only bounds memory.

Not done this round:

- **Define edits:** directive replay already hits 5,628 of 5,629 intervals. The cost left is fixed
  planning overhead (about 0.5–0.9 s) and re-parsing the 97 files whose expansion changed.
- **Maps:** the full compile stages still run, but their memo checks are now cheap. A map-only
  path needs the composition model's map sections retained (the patch base keeps only list rows
  and procedure code).
- **In-place DMB patch for defaults:** a numeric default edit changes 2 bytes, in the Variables
  table. Patching needs three things: a retained (type, var) to variable-record index plus the
  section offset; the new value from scalar resolution; and a decline whenever a lowering receipt
  reads that `OwnerScalar` domain (`initial()` and const folding). Added or removed procs and vars
  renumber tables. Making them patchable means changing fresh ID order, which moves the BYOND
  parity baseline, so it is not recommended.

## Status (round 3)

- **Type splice:** new and removed types (explicit, implicit and nested) are spliced. The splice
  replays the full constructor's first-encounter order after the engine prefix
  (`authored_type_start`), applies its parent rules (explicit `parent_type`, the `/datum` rule),
  remaps TypeIds and recertifies the hierarchy. It declines when an existing type's parent,
  explicit flag or synthetic flag would change, and on cycles or missing explicit parents.
- **Default patch** (`body_patch::try_default_patch`): the in-place update reports pure numeric
  default edits of formal non-const vars (flags 0 or tmp), bound to the base tree's identity.
  - The patch rewrites only those Variables-table records in the retained image. Records are found
    by skipping the procedure table after the last list row.
  - It skips ABI, lowering, initializers, link and composition. It still captures startup and ABI
    facts once, for the query host.
  - It declines on `initial(...)` naming the var, on body, input or archive changes, and when a
    record does not hold the old value.
  - String defaults are not patched: a new string changes the offset-ciphered string table, and
    every later byte moves.
- **Link and composition:** measured per step. Composition is about 1.15 s for a leaf var: members
  and headers 0.54, procedure emit 0.22, types 0.12, encode 0.12. Encode already reuses list rows.
  Link is about 1.9 s: table assignment 0.5–0.7 (now bulk-built maps), required types 0.6, orders
  0.4.
- **Limit:** with fresh-build ID order kept, added or removed procs and vars renumber
  encounter-ordered tables. Their link and composition stay whole-program (about 3 s), so 2.5 s is
  not reachable for those edits without either an ID-order change or record-level relinking of
  every shifted reference.

## Addendum: stable, edit-friendly numbering (user decision 2026-10-14)

Incremental output no longer has to be byte-identical to a fresh build. It must be semantically
equivalent: the same program after IDs and table order are normalized, keeping every order that
the runtime can observe. A full build always produces fresh numbering. Incremental requests keep
the previous numbering and extend it.

### Retained edit model

The generation already retains the composed `Dmb` model, the `LinkTables` (key to index), the
list-row image and the field-record map. A structural patch edits the retained model in place and
re-encodes it with list-row reuse (about 0.12 s; the string cipher is re-applied on encode, so
appending strings is cheap). The link tables are extended, never reassigned.

### Rules per table

| Table | New entry | Removed entry | Observable order kept |
|---|---|---|---|
| Strings | appended | left unreferenced | none (IDs only) |
| Procedures | appended (new index = table length) | record kept, unreferenced and dropped from its class lists (tombstone) | each class's proc and verb lists stay in fresh declaration order |
| Variables (records) | appended | tombstone; dropped from class var lists | each class's var list order (`vars` iteration) stays fresh |
| Lists | appended rows; changed rows spliced | old row left unreferenced | n/a |
| Types (classes) | appended **only** when fresh first-encounter order also puts it last; otherwise full path | full path | class table order (`typesof`, type iteration) must equal fresh |
| Instances, map objects | appended | tombstone | map-object order within the map stays fresh |

Each class's member lists are re-derived from the projection of the edited classes only, so their
order equals a fresh build's. Overrides are runtime lookups through the class chain. Static
references (`..()`, typed proc values, `call()` targets) are re-bound by relinking the dependent
units.

### Dependent units

Units whose lowering read a domain the change set dirtied (the demand tokens dropped by the carry)
are relowered through the lowering memo, relinked against the extended tables and spliced into
the model, as body patches already do. A dependent unit count over `PATCH_LIMIT` falls back.

### Compaction

Tombstones and orphan strings are counted on the generation. A full build (cold start, a declined
patch, or tombstones over 5 % of any table) restores fresh numbering. Every fallback logs its
reason.

### Verification

- Until `dmb-equiv` lands on `dmb/takeover`: the six_session tests and the harness compare patched
  output to a fresh build with `dmb-opendream`'s structural comparator (classes and procs paired by
  path, typed operands resolved). They require zero discrepancies, plus an exact match of
  class-table order and per-class var/proc list orders.
- Unchanged-numbering patches (defaults) keep the byte oracle.
- The runtime-observable order list comes from the `dmb/equiv` doc once it exists. Until then:
  class order, per-class var and proc/verb list order, and map-object order.

## Addendum: code motion and the synced model (2026-10-16, lane `tools/dmb-frontend`)

Two admission gaps made common edits fall back to a 20-28 s full compile. Both are closed and both
are compared with a fresh build (`six_session_contract_tests`, `dmb-equiv` with debug lines).

### Edits that only move code

A comment line, blank line, documentation block or new `#define` between declarations changes no
declaration, but it changes the expanded text outside bodies (comments and blank lines survive
expansion; a directive line does not) or shifts lines the old `LineMap` could not explain, since
that map is derived from body line counts alone.

`SourceShape` now keeps a file roster hash and the text of every captured file (`SourceText`
clones: the frontend and the prepared-source cache already own those buffers, so nothing is
copied). When the tree identity and roster are unchanged, `body_patch_lines.rs` aligns the old and
new text of each changed file: the significant tokens outside every body (the first token of a line
carries its indentation) must be the same sequence, and the k-th token's old and new line give a
piecewise-constant shift. Directive lines are compared like any token unless the expanded-text
skeleton hash is equal, in which case they are skipped (they added no expanded text). Any
disagreement declines with the first differing token. The map feeds the existing machinery:
bodies that moved are relowered at their new line, initializer debug lines are relinked through
`relink_shifted`, prefix warnings shift.

### Appends after body patches

`patch_rows` splices code rows into the retained image but left the retained composed model
(`generation.inputs.model`) at its own encoding, so the next structural append saw
`generation.encoded != base` and declined. The patch slot now records the rows spliced since the
model's encoding (`model_rows`, anchored to the hash of `current.encoded`). An append applies them
to a copy of the model with `Dmb::patch_list_rows`, which splices the certified list image, and
requires the result to hash to the patch base before editing it. Any mismatch declines. Rows reset
whenever the model is re-encoded (`patch_model`) or replaced (`patch_variable_values`).

### What still declines

Removed vars and procs, new types, edits inside declaration text (initializer expressions other
than a numeric default), edits that change the tree identity and `#define` edits whose expansion
changes text outside a body. Every decline runs a full build, which installs a fresh patch base
for the next edit.
