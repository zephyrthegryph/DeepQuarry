// Profile records (doc/rewrite/proposals/base_vars.md, final_api.html "Profile records").
//
// Character identity and preferences (a human's hair and eye colours, its age and records, a mob's vore toggles) are not
// vars on the base type: they are fields of a record the holder owns, declared in its CAPABILITIES block:
//
//	CAPABILITIES(/mob/living/carbon/human)
//		profile(nameof(looks), /datum/record/appearance)
//
// A record holds data fields only (no procs besides the TRACKED_DATA setters). It is built when its holder is made, before
// the holder's Initialize() runs, so init code may write it; it is deleted with the holder. A field a draw reads is declared
// TRACKED_DATA(/datum/record/x, field): its setter publishes the field's key on the record and on the holder, so whatever
// reads the key on the holder (a draw, an on_change()) follows. Copying a character (prefs apply, cloning, DNA, shapeshift)
// is record_copy(), one call per record instead of a var-by-var copy proc.

/// A profile record: data fields only, one owner (profile()), copied whole by record_copy().
/datum/record

/// profile(nameof(var), /datum/record/T, fields = list(field = value)): the holder owns one T in var, built before the holder's init and
/// deleted with it. `fields` gives a type's own starting values (a subtype's fields add to its ancestors', field by field), where the old
/// base-type var was overridden in the type's definition: profile(nameof(vore_prefs), /datum/record/vore_prefs, fields = list("digestable" = FALSE)).
/proc/profile(var_name, type, fields = null)
	var/datum/entry/E = owns_one(var_name, type, starts = type)
	if(fields)
		E.args["profile_set"] = fields
	return E

/// var name -> list(field = value): the merged profile(fields =) values of D's type, ancestors first (cached per type).
/proc/profile_sets_of(datum/D)
	var/static/list/by_type = list()
	if(D.type in by_type)
		return by_type[D.type]
	var/list/sets = null
	var/list/chain = list()
	D.declared_entries(chain)
	for(var/datum/entry/E in chain)
		if(E.kind != ENTRY_OWNS_ONE || !islist(E.args["profile_set"]))
			continue
		var/var_name = E.args["var"]
		LAZYINITLIST(sets)
		LAZYINITLIST(sets[var_name])
		var/list/fields = sets[var_name]
		var/list/given = E.args["profile_set"]
		for(var/field in given)
			fields[field] = given[field]
	by_type[D.type] = sets
	return sets

/// Builds the profile records of a new mob before anything of its type runs (/atom/New()): a mob's Initialize() writes them
/// before its parent's init would build an ordinary starting occupant.
/proc/profiles_build(datum/D)
	var/list/starts = own_table_of(D).start_vars
	if(!starts)
		return
	for(var/var_name in starts)
		var/path = starts[var_name]
		if(!ispath(path, /datum/record) || !isnull(D.vars[var_name]))
			continue
		var/datum/record/R = new path
		var/list/fields = profile_sets_of(D)?[var_name]
		for(var/field in fields)
			if(!(field in R.vars))
				stack_trace("profile(fields =) of [D.type] names [field], which [path] doesn't have")
				continue
			var/value = fields[field]
			if(islist(value))
				var/list/L = value
				value = L.Copy()
			R.vars[field] = value // ALLOW(api): a type's declared starting values of its profile record, before anyone reads it
		lifecycle_decl_adopt_child(D, var_name, R, FALSE)

/// TRACKED_DATA(T, field) published `field` of record R: the key is published on the record and on its holder.
/proc/record_changed(datum/record/R, field)
	tracked_changed(R, field)
	var/datum/holder = owner_of(R)
	if(holder)
		tracked_changed(holder, field)

/// The data fields of a record type, in declaration order (cached per type).
/proc/record_fields(datum/record/R)
	var/static/list/by_type = list()
	var/list/fields = by_type[R.type]
	if(fields)
		return fields
	var/static/list/base_names
	if(!base_names)
		base_names = list()
		var/static/datum/record/base = new // kept: one plain record whose vars are the ones every record has
		for(var/name in base.vars)
			base_names[name] = TRUE
	fields = list()
	for(var/name in R.vars)
		if(!base_names[name])
			fields += name
	by_type[R.type] = fields
	return fields

/// Copies every field of `from` into `into` (a record of the same type): through the field's setter when it is TRACKED_DATA
/// (so the holder of `into` redraws), else written. A list field is copied, never shared between two holders.
/proc/record_copy(datum/record/into, datum/record/from)
	if(!into || !from)
		return
	if(into.type != from.type)
		stack_trace("record_copy(): [into.type] from [from.type]")
		return
	for(var/field in record_fields(from))
		var/value = from.vars[field]
		if(islist(value))
			var/list/L = value
			value = L.Copy()
		if(hascall(into, "set_[field]"))
			call(into, "set_[field]")(value)
		else
			into.vars[field] = value // ALLOW(api): record_copy writes a plain data field of a record by name

/// Writes each field of R into the var of the same name on `into` (a save format such as /datum/vore_preferences); a field
/// `into` lacks is skipped. A list is copied.
/proc/record_export(datum/record/R, datum/into)
	for(var/field in record_fields(R))
		if(!(field in into.vars))
			continue
		var/value = R.vars[field]
		if(islist(value))
			var/list/L = value
			value = L.Copy()
		into.vars[field] = value // ALLOW(api): record_export writes a save format's field of the record's name

/// Reads each field of R from the var of the same name on `from` (record_export()'s inverse), through the field's setter.
/proc/record_import(datum/record/R, datum/from)
	for(var/field in record_fields(R))
		if(!(field in from.vars))
			continue
		var/value = from.vars[field]
		if(islist(value))
			var/list/L = value
			value = L.Copy()
		if(hascall(R, "set_[field]"))
			call(R, "set_[field]")(value)
		else
			R.vars[field] = value // ALLOW(api): record_import writes a plain data field of a record by name

/// TRUE when two records of one type hold equal fields (lists compared by content).
/proc/record_equal(datum/record/a, datum/record/b)
	if(!a || !b || a.type != b.type)
		return FALSE
	for(var/field in record_fields(a))
		var/x = a.vars[field]
		var/y = b.vars[field]
		if(islist(x) && islist(y))
			var/list/lx = x
			var/list/ly = y
			if(lx.len != ly.len)
				return FALSE
			for(var/i in 1 to lx.len)
				if(lx[i] != ly[i])
					return FALSE
				if(!isnum(lx[i]) && lx[lx[i]] != ly[ly[i]])
					return FALSE
			continue
		if(x != y)
			return FALSE
	return TRUE

/// The field names of `from` that differ from `into` (tests and the copy log).
/proc/record_diff(datum/record/a, datum/record/b)
	. = list()
	for(var/field in record_fields(a))
		if("[a.vars[field]]" != "[b.vars[field]]")
			. += field
