// How an item works as a tool: the item_tooling() type trait (doc/rewrite/proposals/base_vars.md). speed, pry and climbing are per-type
// data in CAPABILITIES (configure(item_tooling(speed = 0.5))), read with tooling_of(I).speed; set_toolspeed() writes the item's own copy.

STATIC_ENTRY(item_tooling)

/proc/item_tooling(speed = null, pry = null, climbing = null, climbing_delay = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_ITEM_TOOLING, null, list("speed" = speed, "pry" = pry, "climbing" = climbing, "climbing_delay" = climbing_delay))

/datum/type_trait/item_tooling
	var/speed = 1	// multiplier on tool work time: 0.5 works twice as fast
	var/pry = 0	// can pry doors open
	/// Dimensionless multiplier of the five-second climb, not a decisecond duration.
	var/climbing_delay = 1
	var/climbing = FALSE	// lets its holder climb cliffs and walls

/datum/type_trait/item_tooling/copy_values(datum/type_trait/item_tooling/into)
	into.speed = speed
	into.pry = pry
	into.climbing = climbing
	into.climbing_delay = climbing_delay

/datum/entry_engine/type_trait/item_tooling
	kind = ENTRY_ITEM_TOOLING
	trait_type = /datum/type_trait/item_tooling
	publish_key = ITEM_TOOLING_KEY
	base_type = /obj/item
	var_names = list("toolspeed" = "speed", "pry" = "pry", "rock_climbing" = "climbing", "climbing_delay" = "climbing_delay")

/// The holder's item_tooling values (its own once one was set at run time). Read only.
READS_AS(/proc/tooling_of, ITEM_TOOLING_KEY)
/proc/tooling_of(obj/item/holder) as /datum/type_trait/item_tooling
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_ITEM_TOOLING)

/// What a type declares (no instance): the old initial().
/proc/tooling_of_type(type) as /datum/type_trait/item_tooling
	READS_FROM() // declared per type: constant
	return type_trait_of_type(type, ENTRY_ITEM_TOOLING)

/obj/item/proc/set_toolspeed(value)
	return set_trait(src, ENTRY_ITEM_TOOLING, "speed", value)

/obj/item/proc/set_pry(value)
	return set_trait(src, ENTRY_ITEM_TOOLING, "pry", value)

/obj/item/proc/set_rock_climbing(value)
	return set_trait(src, ENTRY_ITEM_TOOLING, "climbing", value)

/obj/item/proc/set_climbing_delay(value)
	return set_trait(src, ENTRY_ITEM_TOOLING, "climbing_delay", value)
