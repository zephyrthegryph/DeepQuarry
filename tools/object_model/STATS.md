# Generated stat domains

Add a domain and its stat rows to `stat_definitions.json`, then run
`python tools/object_model/stat_definitions.py`. The JSON catalog is the single
source for compact IDs, rules, bounds, and named DM methods. Run the generator
with `--check` in CI to reject stale output.

Each stat has a name, combine rule (`add`, `multiply`, `max`, `min`, or `flags`),
baseline, minimum, and maximum. A domain also declares the owner change mask.
The generator emits `/datum/object_model/stat_block/<domain>` and
`/datum/object_model/stat_draft/<domain>`.

```dm
var/datum/object_model/stat_block/example/S = new(owner)
S.set_base_accuracy(20)
var/datum/object_model/stat_draft/example/D = new
D.add_accuracy(-10)
S.set_source(wound, D)
var/accuracy = S.get_accuracy()
S.remove_source(wound)
```

`set_source` replaces the whole contribution from one source. Deleting a source
automatically removes its contribution. A source that merely stops contributing
must call `remove_source`; a relation adapter can automate this when an edge
is removed. Deleting the block owner deletes the block. The block stores flat lists
for effective values and sparse `[ID, value]` pairs for each source, so a
source modifying one stat does not allocate a full array of all stat slots.
It recomputes on read. Setters and source changes mark the owner through
`om_mark_changed` only when the input changes. Current content is not migrated.

The numeric APIs are generated from stat names. Callers should use those named
methods; `set_base_stat` and `contribute` exist for generated methods and
framework adapters. The planned strict-write linter must treat direct writes
to those methods' storage as forbidden before a converted domain can rely on
change tracking for correctness.
