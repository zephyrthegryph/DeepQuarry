# Shared caches

A shared cache holds a value built from a key and reused by every caller: an overlay list per
(icon, connection bits), the facts of a material, a per-type table of declarations. Before this
framework each one was hand-rolled (about 80 `var/static/list/*cache` and `GLOBAL_LIST_*(*cache)`
sites), each with its own key format, its own invalidation or none, no stats, and nothing to
stop a caller writing into a list every other caller shares.

Code: `code/__defines/shared_cache.dm` (macros), `code/datums/shared_cache/shared_cache.dm`
(miss path, policies, interning, LRU, stats, mutation guard). Tests:
`code/modules/unit_tests/dq_shared_cache_tests.dm`. Bench:
`code/modules/benchmarks/shared_cache.dm`. Lint: `tools/ci/cache_lint.py`.

This is not the per-entity declared-cache machinery (`declared_cache_vars()`,
`CACHE_ON_CHANGE`/`CACHE_ON_EVENT`/`CACHE_ON_RELATION`, object_model.md): those clear one var on
one entity. A shared cache is global and keyed. The per-type appearance table in the
declarative lifecycle work (declarative_lifecycle.md) is meant to sit on top of this as its
backing store.

## 1. Declaring and reading

```dm
/proc/build_window_overlays(icon_file, basestate, connections)
	. = list()
	...

DECLARE_SHARED_CACHE(window_overlays, GLOBAL_PROC_REF(build_window_overlays), SC_NEVER)

/obj/structure/window/update_overlays()
	add_overlay(CACHED3(window_overlays, icon, basestate, connections))
```

| Macro | Use |
|---|---|
| `DECLARE_SHARED_CACHE(name, builder, policy)` | Top level, once. `builder` is a proc path. |
| `DECLARE_SHARED_CACHE_EX(name, builder, policy, max, flags)` | With a max entry count (0: none) and `SC_*` flags. |
| `CACHED(name, key)` | Builder receives `key`. Key: text, a type path or a datum. **Never a number.** |
| `CACHED2(name, a, b)`, `CACHED3(name, a, b, c)` | Key `"[a]\|[b]..."`; builder receives `(a, b[, c])`. |
| `CACHED_KEY(name, key, args...)` | Explicit key; builder receives `args` (pass `src` when a builder needs the instance but the key is its type). |
| `CACHED_INT(name, i)` | `SC_INT_KEYS` caches: small positive integers, a flat list. |
| `INVALIDATE_SHARED_CACHE(name)` | Drop every entry (a version bump). Works under every policy. |
| `SHARED_CACHE(name)` | The cache datum (stats, tests). |

Builders take everything from their arguments and may return a falsy value (it is cached once,
off the fast path). Don't call `CACHED()` from a global var initializer.

## 2. Invalidation policies

| Policy | Cleared when |
|---|---|
| `SC_NEVER` | never (static data: icons, types, constant configuration) |
| `SC_ON_EVENT(path)` | an event of `path` or a subtype is emitted on `GLOB.om_world` (`om_wants()` answers TRUE for it, so `OM_EMIT_WORLD` allocates it) |
| `SC_ON_WORLD_CHANGE(bits)` | `om_changed(GLOB.om_world, bits)` raises one of `bits` |
| `SC_EXPLICIT` | only `INVALIDATE_SHARED_CACHE(name)` |

Policy hooks are registered on the cache's first build, so a cache nobody reads costs nothing.
The hooks are a null check in `om_emit()`/`om_wants()` and a mask test in
`om_dispatch_change()`.

## 3. Cost

The store is a plain global list (`_scs_<name>`). In release builds `CACHED(n, k)` expands to

```dm
(_scs_n[k] || _sc_n.miss(k))
```

one list index, with the proc call only on a miss: the same code as a hand-rolled inline
static-list lookup. Hits are counted only with `-DSHARED_CACHE_STATS` (a global counter,
`_sch_<name>`, bumped per lookup) and always in test builds; misses, builds, entries,
evictions and size are always counted. `CACHED_FAST()` is the release form in any build and
`CACHED_COUNTED()` the counted one (the benchmark uses both, since bench builds are test builds).

`tools/build/build.sh bench --scenario=shared_cache --runs=3`, 2,000,000 lookups over 64 warm
keys, per lookup including the loop:

| Arm | ns |
|---|---|
| hand-rolled inline `var/static/list` (`L[k] \|\| build`) | 340 ±33 |
| hand-rolled static list inside a getter proc (the common shape) | 671 ±47 |
| `CACHED()` release | 354 ±18 (1.08x inline ±0.06, within noise) |
| `CACHED_INT()` release | 361 ±30 |
| `CACHED()` with hit counting (`-DSHARED_CACHE_STATS`) | 429 ±33 |
| `CACHED()` in a test build (mutation guard) | 2348 ±166 |

## 4. Interning, bounds and memory

- `SC_INTERN`: built lists with the same contents (primitives, types, datums by ref) share one
  instance across every interning cache. Appearances need no help: BYOND already interns them.
- `max` > 0: an approximate LRU in two generations. The young generation holds at most `max / 2`
  entries; when it fills it becomes the old one (the previous old one is dropped and counted as
  evictions). A hit in the old generation promotes the entry. Hits in the young generation cost
  nothing extra, so bounded caches keep the fast path. Use a bound for unbounded key spaces:
  colours, free text, per-mob appearance strings, JSON.
- The OM Profiler (Debug, "OM Profiler") has a **Caches** tab: hits, misses, hit rate, entries,
  evictions, clears and an approximate size (24 bytes per entry plus a 64-entry sample of the
  values).

## 5. Mutation guard (test builds)

Values are shared. Never write into a returned list; `Copy()` it first. In test builds
(`UNIT_TESTS`), `CACHED()` goes through `guarded()`: every list built is snapshotted, every hit is
compared with its snapshot (`~=`), and a difference runtimes with the cache name and key, then
restores the entry. `dq_shared_cache_sweep` checks every cache at the end of the run. Numeric keys
also runtime in test builds.

## 6. What stays hand-rolled

Registries, constant tables built once at init (typecaches, gas prototypes), per-instance
state, pools written from many places, and caches that need single-entry expiry keep their lists
with `// ALLOW(cache): <reason>`. `tools/ci/cache_lint.py` (run by `check_ratchets.sh`, ceiling 0)
refuses any new `var/static/list/*cache*`, `GLOBAL_LIST_*(*cache*)` or top-level
`var/list/*cache*` without one. Names containing `typecache` are not counted.
