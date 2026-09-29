/datum/decl/hierarchy
	var/name = "Hierarchy"
	var/hierarchy_type
	var/datum/decl/hierarchy/parent_static
	/// Owned child nodes, sorted (untyped: the lint reads a registry-typed list as SHARED; the
	/// FALSE-init nodes are private to this tree, not registered decls).
	var/list/children

/datum/decl/hierarchy/New(full_init = TRUE)
	if(!full_init)
		return

	var/list/all_subtypes = list()
	all_subtypes[type] = src
	for(var/subtype in subtypesof(type))
		all_subtypes[subtype] = new subtype(FALSE)

	// Sort each parent's children in a plain working list, then adopt them in order.
	var/list/sorted_children = list()
	for(var/subtype in (all_subtypes - type))
		var/datum/decl/hierarchy/subtype_instance = all_subtypes[subtype]
		var/datum/decl/hierarchy/subtype_parent = all_subtypes[subtype_instance.parent_type]
		subtype_instance.parent_static = subtype_parent
		var/list/siblings = sorted_children[subtype_parent]
		if(!siblings)
			siblings = list()
			sorted_children[subtype_parent] = siblings
		dd_insertObjectList(siblings, subtype_instance)
	for(var/datum/decl/hierarchy/node as anything in sorted_children)
		for(var/datum/decl/hierarchy/child as anything in sorted_children[node])
			own_add(node, "children", child)

/datum/decl/hierarchy/proc/is_category()
	return hierarchy_type == type || length(children)

/datum/decl/hierarchy/proc/is_hidden_category()
	return hierarchy_type == type

/datum/decl/hierarchy/dd_SortValue()
	return name

/// A shared definition/flyweight (implicitly shared), never cleared.
/datum/decl/hierarchy/proc/parent() as /datum/decl/hierarchy
	return parent_static

