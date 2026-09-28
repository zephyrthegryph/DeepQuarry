/**********************
* Category Collection *
**********************/
/datum/category_collection
	var/category_group_type                          // Type of categories to initialize
	var/list/datum/category_group/categories         // List of initialized categories
	var/list/datum/category_group/categories_by_name // Associative list of initialized categories, keyed by name

/datum/category_collection/New()
	..()
	categories = new()
	categories_by_name = new()
	for(var/category_type in typesof(category_group_type))
		var/datum/category_group/category = category_type
		if(initial(category.name))
			category = new category(src)
			categories += category
			categories_by_name[category.name] = category
	categories = dd_sortedObjectList(categories)

REF_OWNED_LIST(/datum/category_collection, "categories")

/******************
* Category Groups *
******************/
/datum/category_group
	var/name = ""
	var/category_item_type                      // Type of items to initialize
	var/list/datum/category_item/items          // List of initialized items
	var/list/datum/category_item/items_by_name  // Associative list of initialized items, by name
	var/collection_handle	// The collection this group belongs to

/datum/category_group/New(datum/category_collection/cc)
	..()
	collection_handle = om_handle(cc)
	items = new()
	items_by_name = new()

	for(var/item_type in typesof(category_item_type))
		var/datum/category_item/item = item_type
		if(initial(item.name))
			item = new item(src)
			items += item
			items_by_name[item.name] = item

	// For whatever reason dd_insertObjectList(items, item) doesn't insert in the correct order
	// If you change this, confirm that character setup doesn't become completely unordered.
	items = dd_sortedObjectList(items)

REF_OWNED_LIST(/datum/category_group, "items")

/datum/category_group/dd_SortValue()
	return name

/*****************
* Category Items *
*****************/
/datum/category_item
	var/name = ""
	var/category_handle	// The group this item belongs to

/datum/category_item/New(datum/category_group/cg)
	..()
	category_handle = om_handle(cg)

/datum/category_item/dd_SortValue()
	return name

/// LC-refs: the collection this group belongs to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/category_group/proc/collection() as /datum/category_collection
	return om_resolve(collection_handle)

/// LC-refs: the group this item belongs to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/category_item/proc/category() as /datum/category_group
	return om_resolve(category_handle)

REF_OWNED_VALUES(/datum/category_collection, "categories_by_name")

REF_OWNED_VALUES(/datum/category_group, "items_by_name")
