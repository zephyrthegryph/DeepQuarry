//Cooking containers are used in ovens and fryers, to hold multiple ingredients for a recipe.
//They work fairly similar to the microwave - acting as a container for objects and reagents,
//which can be checked against recipe requirements in order to cook recipes that require several things

/obj/item/reagent_containers/cooking_container
	icon = 'icons/obj/cooking_machines.dmi'
	var/shortname
	var/max_space = 20//Maximum sum of w-classes of foods in this container at once
	var/max_reagents = 80//Maximum units of reagents
	var/food_items = 0 // Used for icon updates
	flags = OPENCONTAINER | NOREACT
	var/list/insertable = list( // ALLOW(instance_list): d: edited in place per instance (2 writers)
		/obj/item/reagent_containers/food/snacks,
		/obj/item/holder,
		/obj/item/paper,
		/obj/item/clothing/head/wizard,
		/obj/item/clothing/head/cakehat,
		/obj/item/clothing/mask/gas/clown_hat,
		/obj/item/clothing/head/beret
	)
TRACKED(/obj/item/reagent_containers/cooking_container, food_items)


// A cooking container is a dish, basket or rack that holds the solid things on its list (up to the sum of their sizes) and, open to reagents, whatever is
// poured in. A held thing on the list is put in, and an alt-click or the menu takes every solid thing out onto the floor. What it holds is listed in its
// examine text, and a load of things is drawn on it.
CAPABILITIES(/obj/item/reagent_containers/cooking_container)
	configure(reagents(volume = nameof(max_reagents)))
	op("insert", item(/obj/item), priority(OP_PRIORITY_PART), when(req_bool(PROC_REF(takes_item))), label("Put in"),
		needs(req_bool(PROC_REF(has_room), because = MSG(cooking_container/full))), then(PROC_REF(item_inserted)))
	op("empty", inputs(hand(), menu()), answers(INTENT_TOGGLE), label("Empty container"),
		needs(req_bool(PROC_REF(holds_solids), because = MSG(cooking_container/nothing_in_it))), then(PROC_REF(emptied)))
	examine_line(PROC_REF(solids_line))
	examine_line(PROC_REF(liquid_line))

MSG_DEF_SELF(cooking_container/full, "There's no more space in it for that!")
MSG_DEF_SELF(cooking_container/nothing_in_it, "There's nothing in it you can remove!")

/// The thing a click would put in: the held thing, or what a gripper holds.
/obj/item/reagent_containers/cooking_container/proc/held_thing(datum/act/op/A)
	var/obj/item/held = A.held
	if(istype(held, /obj/item/gripper))
		var/obj/item/gripper/gripper = held
		return gripper.get_wrapped_item()
	return held

/// The held thing is one of the kinds this container holds.
/obj/item/reagent_containers/cooking_container/proc/takes_item(datum/act/op/A)
	var/obj/item/thing = held_thing(A)
	if(isnull(thing))
		return FALSE
	for(var/possible_type in insertable)
		if(istype(thing, possible_type))
			return TRUE
	return FALSE

/// There is room for the held thing.
/obj/item/reagent_containers/cooking_container/proc/has_room(datum/act/op/A)
	var/obj/item/thing = held_thing(A)
	return !isnull(thing) && !!can_fit(thing)

/// The held thing goes in.
/obj/item/reagent_containers/cooking_container/proc/item_inserted(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/thing = held_thing(A)
	if(!user.unEquip(thing) && !isturf(thing.loc))
		return OP_REFUSED
	thing.forceMove(src)
	to_chat(user, span_notice("You put the [thing] into the [src]."))
	set_food_items(food_items + (1))
	return OP_OK

/// There is a solid thing in it to take out.
/obj/item/reagent_containers/cooking_container/proc/holds_solids(datum/act/op/A)
	return length(contents) > 0 // ALLOW(spatial,reads): a count of what is inside, read when it is emptied; the click asks again

/// Everything solid comes out.
/obj/item/reagent_containers/cooking_container/proc/emptied(datum/act/op/A)
	do_empty(A.actor)
	return OP_OK

/// What is inside, one to a line.
/obj/item/reagent_containers/cooking_container/proc/solids_line(datum/act/op/A)
	if(!contents_count(src))
		return null
	var/string = "It contains....</br>"
	FOR_REAL_CONTENTS(var/atom/movable/thing, src)
		string += "[thing.name] </br>"
	return span_notice("[string]")

/// How much liquid is in it.
/obj/item/reagent_containers/cooking_container/proc/liquid_line(datum/act/op/A)
	if(!reagents.total_volume)
		return null
	return span_notice("It contains [reagents.total_volume]u of reagents.")

/obj/item/reagent_containers/cooking_container/proc/do_empty(mob/user)
	if (!isliving(user))
		//Here we only check for ghosts. Animals are intentionally allowed to remove things from oven trays so they can eat it
		return

	if (user.stat || user.restrained())
		to_chat(user, span_notice("You are in no fit state to do this."))
		return

	if (!Adjacent(user))
		to_chat(user, span_filter_notice("You can't reach [src] from here."))
		return

	if (!contents_count(src))
		to_chat(user, span_warning("There's nothing in the [src] you can remove!"))
		return

	for (var/atom/movable/A in contents)
		A.forceMove(get_turf(src))

	set_food_items(0)
	to_chat(user, span_notice("You remove all the solid items from the [src]."))

/obj/item/reagent_containers/cooking_container/proc/check_contents()
	if (contents_count(src) == 0)
		if (!reagents || reagents.total_volume == 0)
			return 0//Completely empty
	else if (contents_count(src) == 1)
		if (!reagents || reagents.total_volume == 0)
			return 1//Contains only a single object which can be extracted alone
	return 2//Contains multiple objects and/or reagents

//Deletes contents of container.
//Used when food is burned, before replacing it with a burned mess
/obj/item/reagent_containers/cooking_container/proc/clear()
	slot_clear()

	if (reagents)
		reagents.clear_reagents()

/obj/item/reagent_containers/cooking_container/proc/label(number, CT = null)
	//This returns something like "Fryer basket 1 - empty"
	//The latter part is a brief reminder of contents
	//This is used in the removal menu
	. = shortname
	if (!isnull(number))
		.+= " [number]"
	.+= " - "
	if (CT)
		.+=CT
	else if (contents_count(src))
		for (var/obj/O in contents)
			.+=O.name//Just append the name of the first object
			return
	else if (reagents && reagents.total_volume > 0)
		var/datum/reagent/R = reagents.get_master_reagent()
		.+=R.name//Append name of most voluminous reagent
		return
	else
		. += "empty"


/obj/item/reagent_containers/cooking_container/proc/can_fit(obj/item/I)
	var/total = 0
	for (var/obj/item/J in contents) // ALLOW(reads): the sizes of what is inside are read when a thing is put in; the click asks again
		total += J.w_class // ALLOW(reads): the sizes of what is inside are read when a thing is put in; the click asks again

	if((max_space - total) >= I.w_class) // ALLOW(reads): the room is read when a thing is put in; the click asks again
		return 1


//Takes a reagent holder as input and distributes its contents among the items in the container
//Distribution is weighted based on the volume already present in each item
/obj/item/reagent_containers/cooking_container/proc/soak_reagent(datum/reagents/holder)
	var/total = 0
	var/list/weights = list()
	for (var/obj/item/I in contents)
		if (I.reagents && I.reagents.total_volume)
			total += I.reagents.total_volume
			weights[I] = I.reagents.total_volume

	if (total > 0)
		for (var/obj/item/I in contents)
			if (weights[I])
				holder.trans_to_obj(I, weights[I] / total)

/// The load drawn on it, by how much of its room the things in it fill.
/obj/item/reagent_containers/cooking_container/draw(datum/look/look)
	. = ..()
	if(!food_items)
		return
	var/percent = round((food_items / max_space) * 100)
	switch(percent)
		if(0 to 2)
			look.overlay("[icon_state]")
		if(3 to 24)
			look.overlay("[icon_state]1")
		if(25 to 49)
			look.overlay("[icon_state]2")
		if(50 to 74)
			look.overlay("[icon_state]3")
		if(75 to 79)
			look.overlay("[icon_state]4")
		if(80 to INFINITY)
			look.overlay("[icon_state]5")

/obj/item/reagent_containers/cooking_container/oven
	name = "oven dish"
	shortname = "shelf"
	desc = "Put ingredients in this; designed for use with an oven. Warranty void if used incorrectly. Alt click to remove contents."
	icon_state = "ovendish"
	max_space = 30
	max_reagents = 120

/obj/item/reagent_containers/cooking_container/oven/Initialize(mapload)
	. = ..()

	// We add to the insertable list specifically for the oven trays, to allow specialty cakes.
	insertable += list(
		/obj/item/organ/internal/brain // As before, needed for braincake
	)

/obj/item/reagent_containers/cooking_container/fryer
	name = "fryer basket"
	shortname = "basket"
	desc = "Put ingredients in this; designed for use with a deep fryer. Warranty void if used incorrectly. Alt click to remove contents."
	icon_state = "basket"

/obj/item/reagent_containers/cooking_container/grill
	name = "grill rack"
	shortname = "rack"
	desc = "Put ingredients 'in'/on this; designed for use with a grill. Warranty void if used incorrectly. Alt click to remove contents."
	icon_state = "grillrack"

/obj/item/reagent_containers/cooking_container/grill/Initialize(mapload)
	. = ..()

	// Needed for the special recipes of the grill
	insertable += list(
		/obj/item/organ/internal/brain,
		/obj/item/robot_parts/head,
		/obj/item/ectoplasm,
		/obj/item/holder/mouse,
		/obj/item/stack/rods
	)
