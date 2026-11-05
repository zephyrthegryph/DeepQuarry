// Old type paths of collapsed variant families (code/content/variants/README.md).
//
// A family that was one type per row is one parent type and a table; each old type's path was the parent's path plus the row's key. Maps
// (.dmm files, templates, expedition sites) and saved data (persistence tokens) still name those paths. The loaders ask
// variant_alias_of() for a path text text2path() could not resolve, and make the parent with the row's vars instead. This is the only place
// an old path is mapped; the table is the one record of what each path meant.

/// The reference an old path text stands for, list(parent type, key) as VARIANT() builds it, or null when the text names no collapsed type.
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
	var/key = copytext(path_text, slash + 1)
	var/list/table = GLOB.vars[glob_name]
	if(!islist(table) || !islist(table[key]))
		return null
	return VARIANT(parent, key)

/// The row of `variant` (a VARIANT() reference) as var edits for the map and save loaders: the row's vars, copied, without the values a row skips.
/proc/variant_edits_of(list/variant)
	var/list/row = dq_variant_vars(variant[1], variant[2])
	var/list/edits = list()
	for(var/var_name in row)
		if(row[var_name])
			edits[var_name] = row[var_name]
	return edits

/// Makes the thing `type` names, at `loc`, with the constructor arguments after it: `type` is a path, or a VARIANT() reference (the parent
/// type with its row's key set before it initializes).
/proc/variant_new(type, loc, ...)
	var/path = islist(type) ? type[1] : type
	if(!ispath(path))
		return null
	if(islist(type))
		world.preloader_setup(list("variant" = type[2]), path)
	var/list/rest = length(args) > 2 ? args.Copy(3) : null
	. = length(rest) ? new path(arglist(list(loc) + rest)) : new path(loc)
	GLOB._preloader_path = null

// Types in saved data (code/content/persistence/, data files): a save names a type by the text of its path, and a collapsed type's old path
// is the parent's path plus the row's key.

/// The type a saved value names: a path, or the VARIANT() reference of a collapsed type's old path; null when it names neither. A path or a
/// reference passes through.
/proc/saved_type(value)
	if(islist(value) || ispath(value))
		return value
	if(!istext(value))
		return null
	var/path = text2path(value)
	if(path)
		return path
	return variant_alias_of(value)

/// The path of a saved_type(): the type itself, or a reference's parent.
/proc/saved_type_path(type)
	return islist(type) ? type[1] : type

/// What to save for `A`: its type's path text, followed by its variant's key when it has one, so the save reads back through saved_type().
/proc/saved_type_text(atom/A)
	var/key = ("variant" in A.vars) ? A.vars["variant"] : null
	return key ? "[A.type]/[key]" : "[A.type]"

