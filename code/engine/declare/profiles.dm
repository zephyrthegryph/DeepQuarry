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

/// profile(nameof(var), /datum/record/T): the holder owns one T in var, built before the holder's init and deleted with it.
/proc/profile(var_name, type)
	return owns_one(var_name, type, starts = type)

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
		lifecycle_decl_adopt_child(D, var_name, new path, FALSE)

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
		var/datum/record/base = new
		for(var/name in base.vars)
			base_names[name] = TRUE
		qdel(base)
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
		if(hascall(into, "__setter_[field]"))
			call(into, "set_[field]")(value)
		else
			into.vars[field] = value // ALLOW(api): record_copy writes a plain data field of a record by name

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
