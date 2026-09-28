// Type tables (Phase 4 track 4c, doc/rewrite/init_and_turfs.md sec 3.1).
//
// Facts that are the same for every instance of a type are worked out once per
// type and kept here, instead of being looked up again by every instance on
// every materialize/dematerialize. Today that is what on_materialize() has to
// do for a type: join unconditional registries, subscribe rules, start the
// object model. Map load materializes ~490 k atoms, most of them turfs whose
// type needs none of the three, so one lookup here replaces three lookups and
// a registry walk per atom.
//
// Every source the table reads is itself built once and never changes after
// the world has started (the registry declarations, dq_rules(), the OM
// registry), so a cached row never goes stale.

/// The type joins at least one unconditional registry on materialize.
#define TYPE_TABLE_JOINS_REGISTRIES (1<<0)
/// The type declares any registry at all (conditional ones included): it must leave them on dematerialize.
#define TYPE_TABLE_HAS_REGISTRIES (1<<1)
/// The type has rules (code/datums/rules/).
#define TYPE_TABLE_HAS_RULES (1<<2)
/// The type has object-model declarations (code/datums/om/).
#define TYPE_TABLE_HAS_OM (1<<3)
/// Any of these means on_materialize() has work for the type.
#define TYPE_TABLE_MATERIALIZE_WORK (TYPE_TABLE_JOINS_REGISTRIES|TYPE_TABLE_HAS_RULES|TYPE_TABLE_HAS_OM)
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
	if(dq_rules_for_type(thing.type))
		bits |= TYPE_TABLE_HAS_RULES
	if(om_type_has_decl(thing.type))
		bits |= TYPE_TABLE_HAS_OM
	rows[thing.type] = bits
	return bits
