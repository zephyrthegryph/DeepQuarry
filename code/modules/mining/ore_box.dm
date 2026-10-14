
/**********************Ore box**************************/
/obj/structure/ore_box
	icon = 'icons/obj/mining.dmi'
	icon_state = "orebox0"
	name = "ore box"
	desc = "A heavy box used for storing ore."
	density = TRUE
	var/last_update = 0
	var/list/stored_ore = list( // ALLOW(instance_list): d: edited in place per instance (13 writers)
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

CAPABILITIES(/obj/structure/ore_box)
	climb()
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attackby.
/obj/structure/ore_box/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/ore))
		var/obj/item/ore/ore = W
		var/ore_material = ore.material
		if(!consume(ore, user))
			return OP_PASS
		stored_ore[ore_material]++
		return OP_PASS

	if(istype(W, /obj/item/dogborg/sleeper/compactor/supply))
		var/obj/item/dogborg/sleeper/compactor/supply/borg_sleeper = W
		W = borg_sleeper.ore_bag

	if(istype(W, /obj/item/ore_bag))
		var/obj/item/ore_bag/S = W
		for(var/ore_id in S.stored_ore)
			if(S.stored_ore[ore_id] > 0)
				var/ore_amount = S.stored_ore[ore_id]	// How many ores does the satchel have?
				stored_ore[ore_id] += ore_amount 		// Add the ore to the machine.
				S.stored_ore[ore_id] = 0 				// Set the value of the ore in the satchel to 0.
				S.set_current_capacity(0)				// Set the amount of ore in the satchel  to 0.
		to_chat(user, span_notice("You empty the satchel into the box."))
		return OP_PASS

	return OP_PASS

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

