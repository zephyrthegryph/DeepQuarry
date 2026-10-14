/**********************
* Category Collection *
**********************/
/datum/category_collection
	var/category_group_type                          // Type of categories to initialize
	var/list/categories                              // List of initialized categories (owned; untyped: the lint reads a registry-typed list as SHARED)
	var/list/datum/category_group/categories_by_name // Associative list of initialized categories, keyed by name

CAPABILITIES(/datum/category_collection)
	owns_many(nameof(categories))

/datum/category_collection/New()
	..()
	// categories owns each group (built at boot, before the DEF freeze); categories_by_name is a plain index.
	categories_by_name = list()
	var/list/built = list()
	for(var/category_type in typesof(category_group_type))
		var/datum/category_group/category = category_type
		if(initial(category.name))
			category = new category(src)
			built += category
			categories_by_name[category.name] = category
	for(var/datum/category_group/sorted as anything in dd_sortedObjectList(built))
		rel_add(src, nameof(categories), sorted)


/******************
* Category Groups *
******************/
/datum/category_group
	var/name = ""
	var/category_item_type                      // Type of items to initialize
	var/list/items                              // List of initialized items (owned; untyped: the lint reads a registry-typed list as SHARED)
	var/list/datum/category_item/items_by_name  // Associative list of initialized items, by name
	var/datum/category_collection/collection_static	// The collection this group belongs to

CAPABILITIES(/datum/category_group)
	owns_many(nameof(items))

/datum/category_group/New(datum/category_collection/cc)
	..()
	collection_static = cc
	// items owns each item (built at boot, before the DEF freeze); items_by_name is a plain index.
	items_by_name = list()
	var/list/built = list()

	for(var/item_type in typesof(category_item_type))
		var/datum/category_item/item = item_type
		if(initial(item.name))
			item = new item(src)
			built += item
			items_by_name[item.name] = item

	// For whatever reason dd_insertObjectList(items, item) doesn't insert in the correct order
	// If you change this, confirm that character setup doesn't become completely unordered.
	for(var/datum/category_item/sorted as anything in dd_sortedObjectList(built))
		rel_add(src, nameof(items), sorted)


/datum/category_group/dd_SortValue()
	return name

/*****************
* Category Items *
*****************/
/datum/category_item
	var/name = ""
	var/datum/category_group/category_static	// The group this item belongs to

/datum/category_item/New(datum/category_group/cg)
	..()
	category_static = cg

/datum/category_item/dd_SortValue()
	return name

/// A shared definition/flyweight (implicitly shared), never cleared.
/datum/category_group/proc/collection() as /datum/category_collection
	return collection_static

/// A shared definition/flyweight (implicitly shared), never cleared.
/datum/category_item/proc/category() as /datum/category_group
	return category_static


