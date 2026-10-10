// -----------------------------
//        Mining Satchel
// -----------------------------
/*
 * Mechoid - Orebags are the most common quick-gathering thing, and also have tons of lag associated with it.
 * Their checks are going to be hyper-simplified due to this, and their INCREDIBLY singular target contents.
 */
/obj/item/ore_bag
	name = "mining satchel"
	desc = "This little bugger can be used to store and transport ores."
	icon = 'icons/obj/mining.dmi'
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_storage.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_storage.dmi',
		)
	icon_state = "satchel"
	slot_flags = SLOT_BELT | SLOT_POCKET
	w_class = ITEMSIZE_NORMAL
	var/current_capacity = 0
	var/max_storage_space = 100
	var/max_pickup = 100 //How much ore can be picked up in one go. There to prevent someone from walking on a turf with 10000 ore and making the server cry.
	var/list/stored_ore = list( // ALLOW(instance_list): d: edited in place per instance (14 writers)
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
	var/last_update = 0
	drop_sound = SFX_ITEMS_DROP_BACKPACK
	pickup_sound = SFX_ITEMS_PICKUP_BACKPACK
	item_flags = FLAMMABLE

/obj/item/ore_bag/holding
	name = "mining satchel of holding"
	desc = "Like a mining satchel, but when you put your hand in, you're pretty sure you can feel time itself."
	icon_state = "satchel_bspace"
	max_storage_space = ITEMSIZE_COST_NORMAL * 15000 // This should never, ever, ever be reached.
	item_flags = FIRE_PROOF

/obj/item/ore_bag/sleeper
	name = "processing chamber"
	desc = "A mining satchel built into a sleeper. VORE!!!"
	icon_state = "satchel_bspace"
	max_storage_space = 500
	item_flags = INDESTRUCTIBLE | ABSTRACT

TRACKED(/obj/item/ore_bag, current_capacity)
TRACKED(/obj/item/ore_bag, max_storage_space)

CAPABILITIES(/obj/item/ore_bag)
	op("bag_item", item(/obj/item), needs(req(PROC_REF(can_take_more))), then(PROC_REF(interaction_item)))

/// Requirement: a full bag takes nothing more.
/obj/item/ore_bag/proc/can_take_more(datum/act/op/A)
	return (current_capacity < max_storage_space) ? null : MSG(ore_bag/full)

MSG_DEF_SELF(ore_bag/full, "It's too full to possibly fit anything else inside of it.")

/// Old attackby: an ore goes in (the click goes on).
/obj/item/ore_bag/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if (istype(W, /obj/item/ore) && !istype(W, /obj/item/ore/slag) && !istype(W, /obj/item/ore/archeology_debris))
		var/obj/item/ore/ore = W
		stored_ore[ore.material]++
		set_current_capacity(current_capacity + 1)
		user.remove_from_mob(W)
		consume(ore, user)
	return OP_PASS

/obj/item/ore_bag/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	//If we attack a turf, we try to scoop up all the ore from the turf first.
	if(isturf(target) && user.Adjacent(target))
		gather_all(target, user)
		return

	//If we attack an ore, see if it's on a turf. If so, scoop up everything on the turf. If not, scoop up just that ore.
	else if(istype(target, /obj/item/ore) && user.Adjacent(target))
		var/turf_check = isturf(target.loc) //get_turf intentionally not used here due to clicking ore in a backpack or other weirdness.
		if(turf_check)
			gather_all(target.loc, user)
			return

/obj/item/ore_bag/proc/remove_from_storage(obj/item/W, atom/new_location)
	if(!istype(W)) return 0

	if(new_location)
		if(ismob(loc))
			W.dropped(usr)
		if(ismob(new_location))
			W.hud_layerise()
		else
			W.reset_plane_and_layer()
		W.forceMove(new_location)
	else
		W.forceMove(get_turf(src))

	W.on_exit_storage(src)
	return 1

/obj/item/ore_bag/proc/gather_all(turf/T, mob/user, silent = 0)
	var/success = 0
	var/failure = 0
	var/current_pickup = 0
	var/max_pickup_reached = 0
	for(var/obj/item/ore/O in turf_contents_of_type(T, /obj/item/ore)) //Only ever grabs ores. Doesn't do any extraneous checks, as all ore is the same size. Tons of checks means it causes hanging for up to three seconds.
		if(current_capacity >= max_storage_space)
			failure = 1
			break
		if(current_pickup >= max_pickup)
			max_pickup_reached = 1
			break
		if(istype(O, /obj/item/ore/slag) || istype(O, /obj/item/ore/archeology_debris))
			continue
		var/obj/item/ore/ore = O
		stored_ore[ore.material]++
		set_current_capacity(current_capacity + 1)
		current_pickup++
		consume(ore)
		success = 1
	if(!silent) //Let's do a single check and then do more instead of a bunch at once.
		if(success && !failure && !max_pickup_reached) //Picked stuff up, did not reach capacity, did not reach max_pickup.
			to_chat(user, span_notice("You put everything in [src]."))
		else if(success && failure) //Picked stuff up to capacity.
			to_chat(user, span_notice("You fill the [src]."))
		else if(success && max_pickup_reached) //Picked stuff up to the max_pickup
			to_chat(user, span_notice("You fill the [src] with as much as you can grab in one go."))
		else //Failed. The bag is full.
			to_chat(user, span_notice("You fail to pick anything up with \the [src]."))
	if(istype(user?.pulling_target(), /obj/structure/ore_box)) //Bit of a crappy way to do this, as it doubles spam for the user, but it works. //Then let me fix it. ~CL.
		var/obj/structure/ore_box/OB = user?.pulling_target()
		for(var/ore_material in stored_ore)
			if(stored_ore[ore_material] > 0)
				var/ore_amount = stored_ore[ore_material]	// How many ores does the satchel have?
				OB.stored_ore[ore_material] += ore_amount	// Add the ore to the box
				stored_ore[ore_material] = 0 				// Set the value of the ore in the satchel to 0.
				set_current_capacity(0)				// Set the amount of ore in the satchel to 0.
	current_pickup = 0
	return success

/obj/item/ore_bag/equipped(mob/user)
	..()
	dq_add_recursive_move(user)
	observe(user, /datum/notice/movable_attempted_move, src, then(PROC_REF(autoload)))

/obj/item/ore_bag/dropped(mob/user, equipping, slot)
	..()
	unobserve(user, /datum/notice/movable_attempted_move, src)

/obj/item/ore_bag/proc/autoload(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/user = A.target
	var/obj/item/ore/O = locate_on(get_turf(user), /obj/item/ore)
	if(O)
		gather_all(get_turf(user), user)

/obj/item/ore_bag/proc/rangedload(atom/A, mob/user)
	var/obj/item/ore/O = locate_on(get_turf(A), /obj/item/ore)
	if(O)
		gather_all(get_turf(A), user)

/obj/item/ore_bag/examine(mob/user)
	. = ..()

	if(!Adjacent(user)) //Can only check the contents of ore bags if you can physically reach them.
		return .

	if(isliving(user))
		add_fingerprint(user)

	. += span_notice("It holds:")
	var/has_ore = 0
	for(var/ore in stored_ore)
		if(stored_ore[ore] > 0)
			. += span_notice("- [stored_ore[ore]] [ore]")
			has_ore = 1
	if(!has_ore)
		. += "Nothing."
