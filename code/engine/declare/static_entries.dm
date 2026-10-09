// Static entries (doc/rewrite/proposals/loot_and_map_resolvers.md): entries of a CAPABILITIES block that are read without an instance.
//
// A loot table or a map-time resolver belongs to a type that is never made (an /obj/random is resolved before it is instanced, a /loot/...
// table is a datum nobody holds). Its entry is declared in the type's CAPABILITIES block like any other, but a kind marked
// STATIC_ENTRY(kind) (code/__defines/engine/markers.dm) does not go into the instance chain, where a table is built from the first
// instance: `analyze gen declare` leaves it out of declared_entries() and writes it into declared_static_blocks() instead. The kernel's
// static_entries system compiles those blocks once at world setup, before the first map load, parents first, into one lean table per
// declaring type, and hands the result to the engine of each kind (an /datum/entry_engine with static_kind = TRUE) to build its caches.
//
// Inheritance is the table builder's: a subtype's block is compiled over its nearest declaring ancestor's table. A kind marked
// singleton (one table, one resolver) takes at most one entry per type; a subtype that has inherited one changes it with
// configure(kind(...)), which the kind's engine merges (merge()); a plain second declaration is an error.
//
// Nothing here ever builds lazily: after setup a lookup only reads (static_entry_of(), the engines' own caches). A lookup before setup
// is reported and answered by building at once, so a boot-order mistake is loud.

/datum/entry_engine
	/// TRUE: entries of this kind are declared in CAPABILITIES blocks but read from the static tables (no instance).
	var/static_kind = FALSE
	/// TRUE: a type declares at most one entry of this kind; a subtype changes it with configure().
	var/singleton = FALSE

/// The entry a subtype ends up with when it writes configure(changes) over the inherited `old` (a static kind with singleton = TRUE).
/datum/entry_engine/proc/merge(datum/entry/old, datum/entry/changes)
	return changes

/// Called once after setup, with every type's nearest static table (type => /datum/type_table, null for a type under no declaring ancestor):
/// the engine of a static kind builds its caches here, from the tables, before any lookup.
/datum/entry_engine/proc/static_built(list/by_type)
	return

SYSTEM_DEF(static_entries)
	name = "Static entries"
	/// type => its nearest static table; null until setup ran.
	var/list/tables_by_type
	/// TRUE once the engines of the static kinds were told.
	var/ready = FALSE

/datum/system/static_entries/initialize()
	static_entries_build()

/// Reports a static lookup made before the static entries were set up (a boot-order mistake) and sets them up at once. A system's api: other
/// folders call this, never SSstatic_entries.
/proc/static_entries_ensure(asked)
	if(SSstatic_entries.ready)
		return
	stack_trace("[asked] before the static entries were set up")
	static_entries_build()

/// Compiles the static blocks and tells the engines of the static kinds. Once; the system runs it at setup.
/proc/static_entries_build()
	if(SSstatic_entries.ready)
		return
	var/list/blocks = declared_static_blocks()
	var/list/sizes = list() // subtree size => the declaring types of that size
	for(var/type in blocks)
		var/size = length(typesof(type))
		if(!sizes["[size]"])
			sizes["[size]"] = list()
		sizes["[size]"] += type
	var/list/order = list()
	for(var/size_text in sizes)
		order += text2num(size_text)
	sortTim(order, GLOBAL_PROC_REF(cmp_numeric_dsc)) // an ancestor's subtree is strictly bigger than any descendant's: parents come first
	var/list/by_type = list()
	for(var/size in order)
		var/list/same_size = sizes["[size]"]
		sortTim(same_size, GLOBAL_PROC_REF(cmp_type_text_asc))
		for(var/type in same_size)
			var/list/row = blocks[type]
			var/datum/type_table/table = static_compile(type, by_type[type], row[1], row[2], row[3])
			for(var/sub in typesof(type))
				by_type[sub] = table
	SSstatic_entries.tables_by_type = by_type
	SSstatic_entries.ready = TRUE
	for(var/datum/entry_engine/engine_type as anything in subtypesof(/datum/entry_engine))
		var/kind = engine_type::kind
		var/datum/entry_engine/engine = kind ? entry_engine_for(kind) : null
		if(engine?.static_kind)
			engine.static_built(by_type)

/// Sorts type paths by their text.
/proc/cmp_type_text_asc(a, b)
	return cmp_text_asc("[a]", "[b]")

/// Sorts numbers, biggest first.
/proc/cmp_numeric_dsc(a, b)
	return b - a

/// One block's static table over its ancestor's `parent` (null: none): the entries of file:line, in order, each with its own line.
/proc/static_compile(type, datum/type_table/parent, file, line, list/entries)
	RETURN_TYPE(/datum/type_table)
	var/datum/type_table/T = new
	T.owner_type = type
	T.items = parent ? parent.items.Copy() : list()
	T.caps = list()
	var/origin = entry_origin_text(file, line)
	for(var/item in entry_flatten(entries))
		if(istype(item, /datum/entry/line))
			var/datum/entry/line/L = item
			origin = entry_origin_text(file, L.line, L.section_name)
			continue
		static_apply(T, item, origin)
	return T

/// Applies one declared item of a static block.
/proc/static_apply(datum/type_table/T, item, origin)
	var/datum/entry/E = item
	if(!istype(E))
		table_error(T, origin, declare_rule(RULE_NOT_AN_ENTRY), "[item] is not an entry", "a static block holds the constructors of its kinds (loot(), map_resolver(), ...) and configure() of them")
		return
	if(E.kind == ENTRY_CONFIGURE)
		static_configure(T, E, origin)
		return
	var/datum/entry_engine/engine = entry_engine_for(E.kind)
	if(!engine?.static_kind)
		table_error(T, origin, declare_rule(RULE_STATIC), "[E.kind] is not a static entry", "only kinds marked STATIC_ENTRY() are read without an instance")
		return
	if(engine.singleton)
		var/datum/centry/known = static_find(T, E.kind)
		if(known)
			table_error(T, origin, declare_rule(RULE_STATIC), "[E.kind]() is already declared for [T.owner_type] or an ancestor (at [known.origin])", "change what the supertype declared with configure([E.kind](...)); a second [E.kind]() would silently replace it")
			return
	table_add_item(T, E, origin, null, null, E.key)

/// configure(kind(...)) of a static entry: the engine's merge over the inherited entry, in the inherited entry's place.
/proc/static_configure(datum/type_table/T, datum/entry/E, origin)
	var/datum/entry/changes = E.args["def"]
	if(!istype(changes))
		table_error(T, origin, declare_rule(RULE_CONFIGURE), "configure() of a static block takes an entry constructor, got [changes]", "configure(loot(chance = 20))")
		return
	var/datum/entry_engine/engine = entry_engine_for(changes.kind)
	if(!engine?.static_kind)
		table_error(T, origin, declare_rule(RULE_CONFIGURE), "configure([changes.kind](...)) names no static kind", "only kinds marked STATIC_ENTRY() are configured here")
		return
	var/datum/centry/known = static_find(T, changes.kind)
	if(!known)
		table_error(T, origin, declare_rule(RULE_CONFIGURE), "configure([changes.kind](...)) names a [changes.kind] the type does not inherit", "declare it with [changes.kind](...) in this block, or configure one an ancestor declares")
		return
	var/datum/entry/merged = engine.merge(known.item, changes)
	var/at = T.items.Find(known)
	var/datum/centry/C = new
	C.item = merged // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	C.origin = origin
	C.eff_key = known.eff_key
	T.items[at] = C // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)

/// The centry of `kind` in a static table (the first), or null.
/proc/static_find(datum/type_table/T, kind)
	RETURN_TYPE(/datum/centry)
	for(var/datum/centry/C as anything in T.items)
		var/datum/entry/E = C.item
		if(istype(E) && E.kind == kind)
			return C
	return null

/// The static table of `type`: its own block over its ancestors', or the nearest ancestor's; null when no ancestor declares one.
/proc/static_table_of(type)
	RETURN_TYPE(/datum/type_table)
	static_entries_ensure("static_table_of([type])")
	return SSstatic_entries.tables_by_type[type]

/// The entry of `kind` that `type` ends up with (declared by it or an ancestor, configure()s applied), or null.
/proc/static_entry_of(type, kind)
	RETURN_TYPE(/datum/entry)
	var/datum/type_table/T = static_table_of(type)
	if(!T)
		return null
	var/datum/centry/C = static_find(T, kind)
	return C?.item

/// Every type with a static table of its own: the types that wrote a CAPABILITIES block holding a static kind (not their subtypes).
/proc/static_declaring_types()
	RETURN_TYPE(/list)
	. = list()
	static_entries_ensure("static_declaring_types()")
	for(var/type in SSstatic_entries.tables_by_type)
		var/datum/type_table/T = SSstatic_entries.tables_by_type[type]
		if(T.owner_type == type)
			. += type
