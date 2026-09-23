
/**********************Ore box**************************/
/obj/structure/ore_box
	icon = 'icons/obj/mining.dmi'
	icon_state = "orebox0"
	name = "ore box"
	desc = "A heavy box used for storing ore."
	density = TRUE
	var/last_update = 0
	var/list/stored_ore = list(
		ORE_SAND = 0,
		ORE_HEMATITE = 0,
		ORE_CARBON = 0,
		ORE_COPPER = 0,
		ORE_TIN = 0,
		ORE_VOPAL = 0,
		ORE_PAINITE = 0,
		ORE_QUARTZ = 0,
		ORE_BAUXITE = 0,
		ORE_PHORON = 0,
		ORE_SILVER = 0,
		ORE_GOLD = 0,
		ORE_MARBLE = 0,
		ORE_URANIUM = 0,
		ORE_DIAMOND = 0,
		ORE_PLATINUM = 0,
		ORE_LEAD = 0,
		ORE_MHYDROGEN = 0,
		ORE_VERDANTIUM = 0,
		ORE_RUTILE = 0)

/obj/structure/ore_box/Initialize(mapload)
	. = ..()
	AddElement(/datum/element/climbable)

/obj/structure/ore_box/attackby(obj/item/W, mob/user)
	if(istype(W, /obj/item/ore))
		var/obj/item/ore/ore = W
		stored_ore[ore.material]++
		user.remove_from_mob(W)
		qdel(ore)
		return

	if(istype(W, /obj/item/dogborg/sleeper/compactor/supply))
		var/obj/item/dogborg/sleeper/compactor/supply/borg_sleeper = W
		W = borg_sleeper.ore_bag

	if(istype(W, /obj/item/ore_bag))
		var/obj/item/ore_bag/S = W
		for(var/ore in S.stored_ore)
			if(S.stored_ore[ore] > 0)
				var/ore_amount = S.stored_ore[ore]	// How many ores does the satchel have?
				stored_ore[ore] += ore_amount 		// Add the ore to the machine.
				S.stored_ore[ore] = 0 				// Set the value of the ore in the satchel to 0.
				S.current_capacity = 0				// Set the amount of ore in the satchel  to 0.
		to_chat(user, span_notice("You empty the satchel into the box."))
		return

	return

/obj/structure/ore_box/examine(mob/user)
	. = ..()

	if(!Adjacent(user)) //Can only check the contents of ore boxes if you can physically reach them.
		return .

	add_fingerprint(user)

	. += "It holds:"
	var/has_ore = 0
	for(var/ore in stored_ore)
		if(stored_ore[ore] > 0)
			. += "- [stored_ore[ore]] [ore]"
			has_ore = 1
	if(!has_ore)
		. += "Nothing."

