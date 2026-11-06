// Old type paths of collapsed variant families (code/content/variants/README.md).
//
// A family that was one type per row is one parent type and a table; each old type's path was the parent's path plus the row's key. Maps
// (.dmm files, templates, expedition sites) and saved data (persistence tokens) still name those paths. The loaders ask
// variant_alias_of() for a path text text2path() could not resolve, and make the parent with the row's vars instead. This is the only place
// an old path is mapped; the table is the one record of what each path meant.

/// The reference `path_text` is, when it is the old path of a collapsed type (the parent is a family and its table has the row), else null.
/// A reference is that text; there is nothing to convert it to.
/proc/variant_alias_of(path_text)
	if(!istext(path_text))
		return null
	var/slash = findlasttext(path_text, "/")
	if(!slash || slash == 1)
		return null
	var/parent = text2path(copytext(path_text, 1, slash))
	if(!ispath(parent))
		return null
	var/glob_name = GLOB.dq_variant_tables[parent]
	if(!glob_name)
		return null
	var/list/table = GLOB.vars[glob_name]
	if(!islist(table) || !islist(table[copytext(path_text, slash + 1)]))
		return null
	return path_text

/// The row of `variant` (a VARIANT() reference) as var edits for the map and save loaders: the row's vars, copied (a falsey value is an edit like any other, a list a copy).
/proc/variant_edits_of(variant)
	var/list/row = dq_variant_vars(saved_type_path(variant), variant_key(variant))
	var/list/edits = list()
	for(var/var_name in row)
		if(variant_row_makes_datum(row[var_name]))
			edits["variant"] = variant_key(variant) // the instance makes its own at preinit, from the row its key names
			continue
		edits[var_name] = variant_row_value(row[var_name])
	return edits

/// Makes the thing `type` names, at `loc`, with the constructor arguments after it: `type` is a path, or a VARIANT() reference (the parent
/// type with its row's key set before it initializes).
/proc/variant_new(type, loc, ...)
	var/path = saved_type_path(type)
	if(!ispath(path))
		return null
	if(istext(type))
		world.preloader_setup(list("variant" = variant_key(type)), path)
	var/list/rest = length(args) > 2 ? args.Copy(3) : null
	. = length(rest) ? new path(arglist(list(loc) + rest)) : new path(loc)
	GLOB._preloader_path = null

/// Every old path of a collapsed family with the name its row gives that thing: "/obj/item/trash/popcorn" = "popcorn". For pickers that list what can
/// be made (the admin spawn menu and verb); a few hundred rows, built per call.
/proc/variant_alias_names()
	var/list/names = list()
	for(var/parent in GLOB.dq_variant_tables)
		if(!ispath(parent, /atom))
			continue
		var/atom/base = parent
		var/list/table = GLOB.vars[GLOB.dq_variant_tables[parent]]
		for(var/key in table)
			var/list/row = table[key]
			names["[parent]/[key]"] = row["name"] || initial(base.name) || key
	return names

/// The VARIANT() references of every row of `parent` table, except the keys in `except`.
/proc/variant_refs(parent, list/except)
	var/list/refs = list()
	var/list/table = dq_variant_table(parent)
	for(var/key in table)
		if(!(key in except))
			refs += variant_ref(parent, key)
	return refs

// Types in saved data (code/content/persistence/, data files): a save names a type by the text of its path, and a collapsed type's old path
// is the parent's path plus the row's key.

/// The type a saved value names: a path, or the VARIANT() reference of a collapsed type's old path; null when it names neither. A path or a
/// reference passes through.
/proc/saved_type(value)
	if(ispath(value))
		return value
	if(!istext(value))
		return null
	var/path = text2path(value)
	if(path)
		return path
	return variant_alias_of(value) // a reference is its own old path, so a reference text comes back as itself

/// What to save for `A`: its type's path text, followed by its variant's key when it has one, so the save reads back through saved_type().
/proc/saved_type_text(atom/A)
	var/key = ("variant" in A.vars) ? A.vars["variant"] : null
	return key ? "[A.type]/[key]" : "[A.type]"


/// The default of `var_name` for what `type` names: a path's initial(), or for a VARIANT() reference the row's value when it gives one, else the
/// parent type's initial(). For previews that show a thing without making it.
/proc/variant_initial(type, var_name)
	var/path = saved_type_path(type)
	if(!ispath(path))
		return null
	if(istext(type))
		var/list/row = dq_variant_vars(path, variant_key(type))
		if(row && (var_name in row))
			return row[var_name]
	var/atom/A = path
	return initial(A.vars[var_name])

/// The first thing in the world that `type` names (a path, or a VARIANT() reference), as locate(path) finds one; null when there is none.
/proc/variant_locate(type)
	if(!istext(type))
		return locate(type)
	var/path = saved_type_path(type)
	if(!ispath(path))
		return null
	for(var/obj/item/I in world)
		if(variant_is(I, type))
			return I
	return null

// The latent ledger (code/engine/refs/containment/latent.dm) holds a VARIANT() reference as an entry for a holder that asks for it
// (latent_variants_ok()): these answer what only the rows know.
/atom/latent_variant_named(path)
	return variant_alias_of(path) ? TRUE : FALSE

/atom/variant_make_at(path, atom/where)
	return variant_new(path, where)

/atom/latent_variant_value(path, var_name)
	return variant_initial(path, var_name)
