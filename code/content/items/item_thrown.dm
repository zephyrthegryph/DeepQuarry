// How an item flies: the item_thrown() type trait (doc/rewrite/proposals/base_vars.md). force (the hit when thrown) and catchable are
// per-type data in CAPABILITIES (configure(item_thrown(force = 10))), read with thrown_of(I).force; set_throwforce() writes the item's own copy.

STATIC_ENTRY(item_thrown)

/proc/item_thrown(force = null, catchable = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_ITEM_THROWN, null, list("force" = force, "catchable" = catchable))

/datum/type_trait/item_thrown
	var/force = 0	// damage when it hits after a throw
	var/catchable = TRUE	// a thrown one can be caught

/datum/type_trait/item_thrown/copy_values(datum/type_trait/item_thrown/into)
	into.force = force
	into.catchable = catchable

/datum/entry_engine/type_trait/item_thrown
	kind = ENTRY_ITEM_THROWN
	trait_type = /datum/type_trait/item_thrown
	publish_key = ITEM_THROWN_KEY
	base_type = /obj/item
	var_names = list("throwforce" = "force", "catchable" = "catchable")

/// The holder's item_thrown values (its own once one was set at run time). Read only.
READS_AS(/proc/thrown_of, ITEM_THROWN_KEY)
/proc/thrown_of(obj/item/holder) as /datum/type_trait/item_thrown
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_ITEM_THROWN)

/// What a type declares (no instance): the old initial().
/proc/thrown_of_type(type) as /datum/type_trait/item_thrown
	READS_FROM() // declared per type: constant
	return type_trait_of_type(type, ENTRY_ITEM_THROWN)

/obj/item/proc/set_throwforce(value)
	return set_trait(src, ENTRY_ITEM_THROWN, "force", value)

/obj/item/proc/set_catchable(value)
	return set_trait(src, ENTRY_ITEM_THROWN, "catchable", value)
