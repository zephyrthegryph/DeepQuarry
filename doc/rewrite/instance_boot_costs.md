# Per-instance boot costs (boot-speed item 4, part 2)

Profile: `DQ_WORLD_PARAMS=boot_profile=1 bash tools/dq_focused_test.sh --boot` on boot-speed/precompute (382086f4d4), seconds, BYOND
profiler (inflates real time). Two baselines differ with machine load (caps_init 13.0 / 8.0); the second, quieter one is used below.

| Item | Inclusive | What is in it |
|---|---|---|
| `caps_init` | 8.0 (36,329 calls) | self 0.2. `engine_holder_init` 7.1, the first-instance table builds (`own_table_of` miss, already cut by part 1), `rx_type_enrols`, derived/verb setup |
| `engine_holder_init` | 7.1 (16,526) | self 0.2. `hooks_change_baseline` 1.7 (`change_value` 91k reads), capability `on_holder_init` hooks, starting contents (a nested Initialize of each starting occupant), `stat_holder_init` |
| `rel_set` | 5.2 (39,353) | self 0.2. `rel_view_set` 3.2 / `_rel_attach` of the actual links, first-use table builds |
| `static_entries_build` | 4.2 (1) | `type_trait/static_built` 2.6 (self 2.1, 10 calls), the rest is the block compile |

All four are inclusive times: almost none of it is the named proc. What is left after part 1 is either real per-instance work (links made,
hooks baselined, occupants created) or nested calls that are counted again under their own names (`InitAtom` 31.7 contains all of them).

## Fix 1 (landed): `static_built` scanned its seen-tables list per type

`if(!(T in built_of_table))` on an assoc list scans the keys, so each of the 10 trait kinds walked the (types x tables) product: self
2.1 s of the 2.6 s. A `seen[T]` lookup makes it types + tables. `dq_type_trait_tables_equal_scan` builds both ways for every kind and compares
the types, the trait values and which types share a trait object.

## Not fixable safely here (written up, not done)

- `rel_set` / `rel_view_set`: the link writes themselves; speeding them up changes the reverse-index bookkeeping. Needs a design change
  (batching links of an atom's init), not a local fix.
- `hooks_change_baseline` (1.7): one `change_value` per hook per holder at init; caching it needs the hook's inputs, which differ per holder.
  A cache would be shadow state of the value. Left.
- `rx_type_enrols` (240k calls, 1.1 s self, mostly profiler call overhead): already cached per type; the remaining cost is the call. A
  second inline cache at the call sites would duplicate the cache. Left.
