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

/// Makes the thing a VARIANT() reference names, at `loc`: the parent type with its row's key set before it initializes.
/proc/variant_new(list/variant, loc)
	if(!islist(variant) || !ispath(variant[1]))
		return null
	world.preloader_setup(list("variant" = variant[2]), variant[1])
	. = new variant[1](loc)
	GLOB._preloader_path = null
