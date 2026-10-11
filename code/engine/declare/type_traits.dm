// Type traits, the trait blocks of base types (doc/rewrite/final_api.html section 1, "Trait blocks"): per-type data a domain owns, declared in the type's CAPABILITIES
// block instead of as vars on a base type.
//
//	CAPABILITIES(/obj/machinery/firealarm)
//		configure(uses_power(channel = ENVIRON, idle = 2, active = 6))
//
// A trait kind is a static singleton entry (code/engine/declare/static_entries.dm): read without an instance, compiled once at world setup,
// parents first. The base type of a domain declares the trait with its defaults; a subtype changes what it inherits with configure(kind(...)),
// naming only what changes (an argument left null is inherited). Each type ends up with one shared, read-only /datum/type_trait of the kind,
// built at setup: type_trait_of(holder, kind) reads it with no instance cost.
//
// A value that changes at run time (a machine whose parts set its draw) is an override: type_trait_own(holder, kind) gives the holder its own copy
// (copy on write, in /datum's type_trait_overrides, never on the base type), and the domain's setter writes it and publishes the change under the key
// its readers declare. A holder that never writes keeps reading the shared one.
//
// A new trait: a /datum/type_trait subtype with one var per value (and copy_values()), a constructor proc returning entry_make(kind, null, list(args)), STATIC_ENTRY(kind)
// and an /datum/entry_engine/type_trait subtype naming the two. The domain's reader (power_of(M)) is type_trait_of() typed.

/// The values of one trait kind for one type (shared, read-only) or one holder (its override).
/datum/type_trait
	/// The entry kind this trait is declared by.
	var/kind

/// Sets the values an entry names (null arguments are left as they are: inherited, or the datum's default).
/datum/type_trait/proc/apply_args(list/named)
	for(var/name in named)
		if(isnull(named[name]))
			continue // not named: inherited
		var/value = named[name] == TRAIT_NONE ? null : named[name] // TRAIT_NONE: a subtype that sets the value to nothing
		if(!(name in vars))
			stack_trace("[type]: the trait has no value [name]")
			continue
		vars[name] = value // ALLOW(api): a trait datum's values are set from its declaration's arguments by name

/// Writes this trait's values into `into` (a fresh one of the same type). A subtype copies its own vars.
/datum/type_trait/proc/copy_values(datum/type_trait/into)
	return

/// A copy the holder may write (type_trait_own()).
/datum/type_trait/proc/copy()
	var/datum/type_trait/made = new type
	made.kind = kind
	copy_values(made)
	return made

/datum/entry_engine/type_trait
	static_kind = TRUE
	singleton = TRUE
	/// The /datum/type_trait subtype this kind builds.
	var/trait_type = /datum/type_trait
	/// The key the kind's reader READS_AS: set_trait() publishes it.
	var/publish_key
	/// The base type the kind is declared on (a holder outside it has no such trait).
	var/base_type = /datum
	/// Old var name -> field: the base-type vars the trait replaced, which a map edit or VV may still name ("active_power_usage" = "active").
	var/list/var_names

/// A subtype's configure(kind(...)) over the inherited declaration: what it does not name stays.
/datum/entry_engine/type_trait/merge(datum/entry/old, datum/entry/changes)
	var/list/merged = old.args ? old.args.Copy() : list()
	for(var/name in changes.args)
		if(!isnull(changes.args[name]))
			merged[name] = changes.args[name]
	return entry_make(kind, null, merged)

/// One shared trait per declaring table, indexed by every type under it.
/datum/entry_engine/type_trait/static_built(list/by_type)
	var/list/built_of_table = list()
	var/list/table = list()
	for(var/type in by_type)
		var/datum/type_table/T = by_type[type]
		if(!(T in built_of_table))
			var/datum/centry/C = static_find(T, kind)
			var/datum/entry/E = C?.item
			var/datum/type_trait/made = null
			if(E)
				made = new trait_type
				made.kind = kind
				made.apply_args(E.args)
			built_of_table[T] = made
		var/datum/type_trait/known = built_of_table[T]
		if(known)
			table[type] = known
	GLOB.type_trait_tables[kind] = table

/// kind -> type -> the shared /datum/type_trait (built once at setup by the kinds' engines).
GLOBAL_LIST_EMPTY(type_trait_tables)

/// kind -> the trait a type with no declaration reads (the datum's defaults).
GLOBAL_LIST_EMPTY(type_trait_defaults)

/datum
	/// kind -> this holder's own /datum/type_trait (type_trait_own()): its run-time values. Null (and free: BYOND stores only a var that
	/// differs from its default) while it reads its type's. Not in the rx record: a destroyed holder's teardown still reads its own values
	/// (a machine's draw leaves the channel it was moved to).
	var/tmp/list/type_trait_overrides

/// The trait of `kind` that `holder` reads: its own override, else its type's declaration, else the kind's defaults. Read only.
/proc/type_trait_of(datum/holder, kind)
	READS_FROM() // the domain's reader names the key it reads as (READS_AS), and its setters publish it
	RETURN_TYPE(/datum/type_trait)
	if(isnull(holder))
		return type_trait_default(kind) // a read through an empty slot (worn?.x): the kind's defaults
	var/datum/type_trait/own = holder.type_trait_overrides?[kind]
	if(own)
		return own
	if(!SSstatic_entries.ready)
		static_entries_ensure("type_trait_of([holder.type], [kind])")
	var/datum/type_trait/shared = GLOB.type_trait_tables[kind]?[holder.type]
	if(shared)
		return shared
	return type_trait_default(kind)

/// The trait of `kind` that `type` declares (no instance), or the kind's defaults.
/proc/type_trait_of_type(type, kind)
	READS_FROM() // declared per type: constant after setup
	RETURN_TYPE(/datum/type_trait)
	if(!SSstatic_entries.ready)
		static_entries_ensure("type_trait_of_type([type], [kind])")
	return GLOB.type_trait_tables[kind]?[type] || type_trait_default(kind)

/// The kind's defaults (a type under no declaration).
/proc/type_trait_default(kind)
	RETURN_TYPE(/datum/type_trait)
	var/datum/type_trait/known = GLOB.type_trait_defaults[kind]
	if(known)
		return known
	var/trait_type = /datum/type_trait
	for(var/datum/entry_engine/type_trait/engine_type as anything in subtypesof(/datum/entry_engine/type_trait))
		if(engine_type::kind == kind)
			trait_type = engine_type::trait_type
			break
	var/datum/type_trait/made = new trait_type
	made.kind = kind
	GLOB.type_trait_defaults[kind] = made
	return made

/// `holder`'s own copy of its trait of `kind`, made on first use (copy on write): the one a domain's setter writes.
/proc/type_trait_own(datum/holder, kind)
	RETURN_TYPE(/datum/type_trait)
	var/datum/type_trait/own = holder.type_trait_overrides?[kind]
	if(own)
		return own
	var/datum/type_trait/shared = type_trait_of(holder, kind)
	own = shared.copy()
	own.kind = kind
	LAZYSET(holder.type_trait_overrides, kind, own)
	return own

/// Sets one field of `holder`'s trait of `kind` at run time: the holder's own copy (copy on write), then the kind's key is published so readers
/// follow. Returns TRUE when the value changed. The domain setters (set_active_power_usage(), set_hitsound()) are this with a fixed field.
/proc/set_trait(datum/holder, kind, field, value)
	var/datum/type_trait/now = type_trait_of(holder, kind)
	if(!(field in now.vars))
		stack_trace("set_trait: [kind] has no field [field]")
		return FALSE
	if(now.vars[field] == value)
		return FALSE
	var/datum/type_trait/own = type_trait_own(holder, kind)
	own.vars[field] = value // ALLOW(api): the one generic trait writer; the field is checked against the trait's vars above
	var/key = type_trait_engine(kind)?.publish_key
	if(key)
		tracked_changed(holder, key)
	return TRUE

/// The engine of a trait kind (its trait type, published key, base type and old var names).
/proc/type_trait_engine(kind)
	RETURN_TYPE(/datum/entry_engine/type_trait)
	return entry_engine_for(kind)

/// Every trait kind's engine.
/proc/type_trait_engines()
	var/list/engines = GLOB.type_trait_engine_list
	if(!engines.len)
		for(var/datum/entry_engine/type_trait/engine_type as anything in subtypesof(/datum/entry_engine/type_trait))
			var/datum/entry_engine/type_trait/E = entry_engine_for(engine_type::kind)
			if(E)
				engines += E
	return engines

/// Every trait kind's engine (type_trait_engines(), filled on first use).
GLOBAL_LIST_EMPTY(type_trait_engine_list)

/// The trait field an old base-type var name now lives in, for `holder`: list(kind, field), or null. What the map loader and VV use to route a
/// write of a var that left the base type (a map's `active_power_usage = 7500` on a mixer) through set_trait().
/proc/type_trait_field_for_var(datum/holder, var_name)
	for(var/datum/entry_engine/type_trait/E as anything in type_trait_engines())
		if(!istype(holder, E.base_type))
			continue
		var/field = E.var_names?[var_name]
		if(field)
			return list(E.kind, field)
	return null

/// Resolves a by-name write to a trait field: `@kind.field` (what VV lists) or an old base-type var name. list(kind, field), or null.
/proc/type_trait_field_named(datum/holder, name)
	if(!istext(name))
		return null
	if(copytext(name, 1, 2) == "@")
		var/dot = findtext(name, ".")
		if(!dot)
			return null
		var/kind = copytext(name, 2, dot)
		var/field = copytext(name, dot + 1)
		var/datum/entry_engine/type_trait/E = type_trait_engine(kind)
		if(!istype(E) || !istype(holder, E.base_type) || type_trait_plain_vars()[field] || !(field in type_trait_of(holder, kind).vars))
			return null
		return list(kind, field)
	return type_trait_field_for_var(holder, name)

/// Every trait field `holder` has, for VV: list("@kind.field" = value, ...).
/proc/type_trait_fields_of(datum/holder)
	var/list/out = list()
	for(var/datum/entry_engine/type_trait/E as anything in type_trait_engines())
		if(!istype(holder, E.base_type))
			continue
		var/kind = E.kind
		var/datum/type_trait/T = type_trait_of(holder, kind)
		for(var/field in T.vars)
			if(type_trait_plain_vars()[field])
				continue
			out["@[kind].[field]"] = T.vars[field]
	return out

/// The vars every trait datum has (type, kind, ...): not trait fields.
/proc/type_trait_plain_vars()
	var/list/out = GLOB.type_trait_plain_var_names
	if(!out.len)
		var/datum/type_trait/plain = new
		for(var/name in plain.vars)
			out[name] = TRUE
	return out

/// The vars of a bare /datum/type_trait (type_trait_plain_vars(), filled on first use).
GLOBAL_LIST_EMPTY(type_trait_plain_var_names)
