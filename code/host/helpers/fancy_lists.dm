GLOBAL_TABLE(get_fancy_list_of_atom_types, GLOBAL_PROC_REF(build_get_fancy_list_of_atom_types))

GLOBAL_TABLE(get_fancy_list_of_datum_types, GLOBAL_PROC_REF(build_get_fancy_list_of_datum_types))

/proc/filter_fancy_list(list/L, filter as text)
	var/list/matches = list()
	for(var/key in L)
		var/value = L[key]
		if(findtext("[key]", filter) || findtext("[value]", filter))
			matches[key] = value
	return matches
