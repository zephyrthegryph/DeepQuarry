// Type tables (Phase 4 track 4c, doc/rewrite/init_and_turfs.md sec 3.1).
//
// Facts that are the same for every instance of a type are worked out once per
// type and kept here, instead of being looked up again by every instance on
// every materialize/dematerialize. Today that is what on_materialize() has to
// do for a type: join unconditional registries, subscribe rules, start the
// engine. Map load materializes ~490 k atoms, most of them turfs whose
// type needs none of the three, so one lookup here replaces three lookups and
// a registry walk per atom.
//
// Every source the table reads is itself built once and never changes after
// the world has started (the registry declarations, GLOBAL_TABLE_GET(dq_rules), the OM
// registry), so a cached row never goes stale.

/// The type joins at least one unconditional registry on materialize.
#define TYPE_TABLE_JOINS_REGISTRIES (1<<0)
/// The type declares any registry at all (conditional ones included): it must leave them on dematerialize.
#define TYPE_TABLE_HAS_REGISTRIES (1<<1)
/// The type has rules (code/datums/rules/).
#define TYPE_TABLE_HAS_RULES (1<<2)
/// The type has engine declarations (code/engine/).
#define TYPE_TABLE_HAS_SCHED (1<<3)
/// The type has materialize-time lifecycle declarations (code/datums/lifecycle/declarations.dm).
#define TYPE_TABLE_HAS_DECLS (1<<4)
/// Any of these means on_materialize() has work for the type.
#define TYPE_TABLE_MATERIALIZE_WORK (TYPE_TABLE_JOINS_REGISTRIES|TYPE_TABLE_HAS_RULES|TYPE_TABLE_HAS_SCHED|TYPE_TABLE_HAS_DECLS)
/// Set on every built row, so a type with no facts is still cached.
#define TYPE_TABLE_BUILT (1<<23)

/// The type table row (TYPE_TABLE_* bits) of `thing`'s type, built on first use.
/proc/atom_type_table(datum/thing)
	var/static/list/rows = list()
	var/bits = rows[thing.type]
	if(bits)
		return bits
	bits = TYPE_TABLE_BUILT
	for(var/datum/registry/registry as anything in thing.type_registries())
		bits |= TYPE_TABLE_HAS_REGISTRIES
		if(!registry.conditional)
			bits |= TYPE_TABLE_JOINS_REGISTRIES
	// membership(joins =) joins its registries at materialize, conditional ones included (membership.dm).
	if(isatom(thing) && cap_registries_of(thing))
		bits |= TYPE_TABLE_JOINS_REGISTRIES
	if(dq_rules_for_type(thing.type))
		bits |= TYPE_TABLE_HAS_RULES
	if(entity_type_has_decl(thing.type))
		bits |= TYPE_TABLE_HAS_SCHED
	var/datum/lifecycle_decls/decls = lifecycle_decls_of(thing)
	if(decls && (decls.work & DECL_WORK_MATERIALIZE))
		bits |= TYPE_TABLE_HAS_DECLS
	rows[thing.type] = bits
	return bits

// Initialize-free types (sec 3.1). A type with no per-instance Initialize() state sets
// init_from_table; SSatoms.InitAtom() then calls table_initialize() in place of the whole
// Initialize() chain (and its arglist). table_initialize() applies the type's facts with the
// fewest writes it can. Space (~310 k turfs on Southern Cross) and the fixed-fabric turfs use it.
// A type is on the path when its nearest declared ancestor (itself included) is declared TRUE: rows of
// GLOB.init_from_table_declared below (hand-written) and GLOB.init_from_table_generated (code/content/atom/init_from_table_types.dm,
// tools/ci/init_table_candidates.py --write). A hand row wins over a generated one for the same path. A subtype that overrides
// Initialize() must be declared FALSE, or the override would never run: the init lint's `table_init_overrides` (ceiling 0).
// The flags are per-type data, so they live in one table, not as a var on /atom.

/// Hand-declared init_from_table rows (`path = TRUE|FALSE`, one per line: the init lint and the generator read them).
GLOBAL_LIST_INIT(init_from_table_declared, list(
	/turf/space = TRUE,
	/turf/space/transit = FALSE,
	/turf/open/fixed = TRUE,
	/turf/open/fixed/fake_space = FALSE,
	/turf/open/fixed/map = FALSE,
	/turf/open/fixed/beach/water = FALSE,
	/turf/open/fixed/wall/planetary = FALSE,
	/turf/open/fixed/floor/sky = FALSE
))

/// type -> TRUE for every type on the table-init path (built once, nearest declared ancestor wins).
GLOBAL_LIST_INIT(init_from_table_types, build_init_from_table_types())

/proc/build_init_from_table_types()
	// The two declaration tables may come later in the global init order: initialize them here if so.
	if(!GLOB.init_from_table_generated)
		GLOB.InitGlobalinit_from_table_generated()
	if(!GLOB.init_from_table_declared)
		GLOB.InitGlobalinit_from_table_declared()
	var/list/rows = GLOB.init_from_table_generated.Copy()
	var/list/declared = GLOB.init_from_table_declared
	for(var/path in declared)
		rows[path] = declared[path]
	// Shallow paths first, so a deeper row overrides its ancestors' subtree.
	var/list/by_depth = list()
	for(var/path in rows)
		var/depth = length(splittext("[path]", "/"))
		while(length(by_depth) < depth)
			by_depth += list(list())
		by_depth[depth] += path
	var/list/out = list()
	for(var/list/level as anything in by_depth)
		for(var/path in level)
			var/on = rows[path]
			for(var/type in typesof(path))
				if(on)
					out[type] = TRUE
				else
					out -= type
	return out

/// What /atom/Initialize() does, for an init_from_table type. Overrides must not call Initialize().
/atom/proc/table_initialize()
	SHOULD_CALL_PARENT(TRUE)
	flags |= ATOM_INITIALIZED
	BOOT_PHASE_BEGIN(bp_decls)
	lifecycle_decls_init(src, TRUE)
	BOOT_PHASE_END(bp_decls, "lifecycle_decls_init" + BOOT_KIND(src), src)
	BOOT_PHASE_BEGIN(bp_caps)
	caps_init(src, TRUE)
	BOOT_PHASE_END(bp_caps, "caps_init" + BOOT_KIND(src), src)
