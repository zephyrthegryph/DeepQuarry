//
// Comparators for use with /datum/sortInstance (or wherever you want)
// They should return negative, zero, or positive numbers for a < b, a == b, and a > b respectively.
//

// Sorts numeric ascending
/proc/cmp_numeric_asc(a,b)
	return a - b

// Sorts qdel statistics recorsd by time and count
/proc/cmp_qdel_item_time(datum/qdel_item/A, datum/qdel_item/B)
	. = B.hard_delete_time - A.hard_delete_time
	if (!.)
		. = B.destroy_time - A.destroy_time
	if (!.)
		. = B.failures - A.failures
	if (!.)
		. = B.qdels - A.qdels

// Sorts entries in a performance stats list.
/proc/cmp_generic_stat_item_time(list/A, list/B)
	. = B[STAT_ENTRY_TIME] - A[STAT_ENTRY_TIME]
	if (!.)
		. = B[STAT_ENTRY_COUNT] - A[STAT_ENTRY_COUNT]

/proc/cmp_typepaths_asc(A, B)
	return sorttext("[B]","[A]")

/**
 * Sorts crafting recipe requirements when crafting_recipes() makes the recipe
 *
 * Prioritises [/datum/reagent] to ensure reagent requirements are always processed first when crafting.
 * This prevents any reagent_containers from being consumed before the reagents they contain, which can
 * lead to runtimes and item duplication when it happens.
 */

/proc/cmp_text_asc(a,b)
	return sorttext(b,a)

///Filters have a numerical priority.
/proc/cmp_filter_data_priority(list/A, list/B)
	return A["priority"] - B["priority"]

/proc/cmp_name_asc(atom/a, atom/b)
	return sorttext(b.name, a.name)

/proc/cmp_name_dsc(atom/a, atom/b)
	return sorttext(a.name, b.name)

