// Shared keyed caches (doc/rewrite/caching.md).
//
// One line declares a cache: its name, a builder proc and an invalidation policy.
//
//   DECLARE_SHARED_CACHE(wall_facts, GLOBAL_PROC_REF(build_wall_facts), SC_ON_NOTICE(/datum/notice/material_facts_changed))
//   var/list/facts = CACHED(wall_facts, material_key)
//
// The store is a plain global list, so a hit is one list index, the same cost as a
// hand-rolled `var/static/list/cache`. A miss calls the
// cache datum, which builds, interns and stores the value.
//
// Keys: CACHED() keys must be stable: text, a type path, or a registered singleton (a fetched
// decl, a registered material). Never a number (a number indexes a list by position) and never
// a ref (`ref()`/`\ref` in a text key): refs are recycled after a delete, so a key built from one
// can return another object's value. Use a registry id, a type path or SHARED_CACHE_UID(D).
// Test builds runtime on a numeric, ref-bearing or unstable object key. Use CACHED_INT() for small positive integers and
// CACHED2()/CACHED3() or CACHED_KEY() for several key arguments.
//
// Values handed out are SHARED. Never write into a returned list; Copy() it first.
// Test builds verify every hit against a snapshot and runtime on a mutation.

// ---- Invalidation policies (the third argument) ----
/// Never invalidated (still clearable by INVALIDATE_SHARED_CACHE()).
#define SC_NEVER null
/// Cleared when the world notice `path` (or a subtype) is published: its publisher calls shared_cache_notice(path) first.
#define SC_ON_NOTICE(path) list("notice", path)
/// Cleared only by INVALIDATE_SHARED_CACHE() (an explicit version bump).
#define SC_EXPLICIT list("explicit")

// ---- Flags (DECLARE_SHARED_CACHE_EX) ----
/// Identical built lists share one instance across every interning cache.
#define SC_INTERN (1<<0)
/// Keys are small positive integers, looked up with CACHED_INT() in a flat list.
#define SC_INT_KEYS (1<<1)

/// A raw global for the framework's own state (code/datums/shared_cache). Raw globals, not GLOB:
/// caches register during global var init, which may run before GLOB exists, and the fast path
/// reads its store without a GLOB datum lookup. Only the framework uses this.
#define SHARED_CACHE_GLOBAL(decl) var/##decl

/// Declares cache N. BUILDER is a proc path; it receives the key (CACHED/CACHED_INT)
/// or the extra arguments (CACHED_KEY/CACHED2/CACHED3) and returns the value.
#define DECLARE_SHARED_CACHE(N, BUILDER, POLICY) DECLARE_SHARED_CACHE_EX(N, BUILDER, POLICY, 0, 0)

/// DECLARE_SHARED_CACHE() with a max entry count (0: unbounded; otherwise an
/// approximate LRU in two generations) and SC_* flags.
#define DECLARE_SHARED_CACHE_EX(N, BUILDER, POLICY, MAX, FLAGS) var/list/_scs_##N = list();var/_sch_##N = 0;var/datum/shared_cache/_sc_##N = new /datum/shared_cache(#N, BUILDER, POLICY, MAX, FLAGS)

/// A stable, never-reused string id for datum D, for cache keys of datums with no registry id
/// (a key must never embed a ref: refs are recycled). Registered materials use
/// MATERIAL_CACHE_ID(), decls their type path.
#define SHARED_CACHE_UID(D) (D.shared_cache_uid || shared_cache_assign_uid(D))

/// A material's stable cache id (material_cache_id(): registry id, else a never-reused uid).
#define MATERIAL_CACHE_ID(M) (M.shared_cache_uid || material_cache_id(M))

/// Drops every entry of cache N (a version bump).
#define INVALIDATE_SHARED_CACHE(N) _sc_##N.invalidate()
/// The cache datum of N (stats, tests).
#define SHARED_CACHE(N) _sc_##N

/// The release fast path, whatever the build (benchmarks measure it in test builds). Hits are
/// counted only with -DSHARED_CACHE_STATS (about 60 ns a lookup, a fifth of the lookup itself);
/// misses, builds, entries and size are always counted. Test builds count hits in guarded().
#ifdef SHARED_CACHE_STATS
#define CACHED_FAST(N, K) (++_sch_##N && _scs_##N[K] || _sc_##N.miss(K))
#define CACHED_INT_FAST(N, I) (++_sch_##N && (I) <= length(_scs_##N) && _scs_##N[I] || _sc_##N.miss_int(I))
#define _CACHED_KEY_FAST(N, K, A...) (++_sch_##N && _scs_##N[K] || _sc_##N.miss(K, ##A))
#else
#define CACHED_FAST(N, K) (_scs_##N[K] || _sc_##N.miss(K))
#define CACHED_INT_FAST(N, I) ((I) <= length(_scs_##N) && _scs_##N[I] || _sc_##N.miss_int(I))
#define _CACHED_KEY_FAST(N, K, A...) (_scs_##N[K] || _sc_##N.miss(K, ##A))
#endif
/// The counted form, whatever the build (the benchmark's comparison arm).
#define CACHED_COUNTED(N, K) (++_sch_##N && _scs_##N[K] || _sc_##N.miss(K))

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
// Test builds: every hit is verified against the snapshot taken at build time.
#define CACHED(N, K) _sc_##N.guarded(K)
#define CACHED_KEY(N, K, A...) _sc_##N.guarded(K, ##A)
#define CACHED_INT(N, I) _sc_##N.guarded_int(I)
#else
#define CACHED(N, K) CACHED_FAST(N, K)
#define CACHED_KEY(N, K, A...) _CACHED_KEY_FAST(N, K, ##A)
#define CACHED_INT(N, I) CACHED_INT_FAST(N, I)
#endif

/// Two key arguments; the builder receives (A, B).
#define CACHED2(N, A, B) CACHED_KEY(N, "[A]|[B]", A, B)
/// Three key arguments; the builder receives (A, B, C).
#define CACHED3(N, A, B, C) CACHED_KEY(N, "[A]|[B]|[C]", A, B, C)
