/datum/find
	var/find_type = 0				//random according to the digsite type
	var/excavation_required = 0		//random 10 - 190
	var/view_range = 200			//how close excavation has to come to show an overlay on the turf
	var/prob_delicate = 0			//probability it requires an active suspension field to not insta-crumble. Set to 0 to nullify the need for suspension field.

/datum/find/New(digsite, exc_req)
	excavation_required = exc_req
	find_type = get_random_find_type(digsite)

/obj/item/strangerock
	name = "Strange rock"
	desc = "Seems to have some unusal strata evident throughout it."
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "strange"
	var/datum/geosample/geologic_data
	w_class = ITEMSIZE_SMALL

CAPABILITIES(/obj/item/strangerock)
	owns_one(nameof(geologic_data), /datum/geosample)
	param(nameof(inside_item_type), pos = 1)
	rolls(nameof(pixel_x), range_of(-8, 8))
	rolls(nameof(pixel_y), range_of(-8, 0))

/// The find the rock holds (its constructor param), or 0 for a research sample at most.
/obj/item/strangerock/var/inside_item_type = 0

// ALLOW(init/INSTANCE_STATE): a strange rock holds its find or a research sample, rolled
/obj/item/strangerock/Initialize(mapload)
	. = ..()
	var/d100 = rand(1,100)

	if(inside_item_type)
		switch(d100)
			if(51 to 100) //standard spawn logic 50% of the time
				new /obj/item/archaeological_find(src, inside_item_type)
			if(21 to 50) // 30% chance
				new /obj/item/research_sample/common(src)
			if(6 to 20) // 15% chance
				new /obj/item/research_sample/uncommon(src)
			if(1 to 5) // 5% chance
				new /obj/item/research_sample/rare(src)
			else	//if something went wrong, somehow, generate the usual find
				new /obj/item/archaeological_find(src, inside_item_type)
	else	//if this strange rock isn't set to generate a find for whatever reason, create a sample 75% of the time (this shouldn't happen unless the rock is mapped in or adminspawned)
		switch(d100)
			if(76 to 100)
				return
			if(21 to 75)
				new /obj/item/research_sample/common(src)
			if(6 to 20)
				new /obj/item/research_sample/uncommon(src)
			if(1 to 5)
				new /obj/item/research_sample/rare(src)
			else	//if we somehow glitched
				return	//do nothing

DECLARE_INTERACTIONS(/obj/item/strangerock, INTERACT_ITEM(null, PROC_REF(strangerock_item)))

/// Old attackby: mine it away or sample it; anything else may crumble it (after a bag gathers it, as its ..() did first).
/obj/item/strangerock/proc/strangerock_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(istype(I, /obj/item/pickaxe)) //Whatever, if you use a hand pick it should work just like a brush. No reason for otherwise.
		if(loc?.release_refusal(src, user))
			return INTERACTION_HANDLED_PASS
		var/obj/item/inside = locate_within(src, /obj/item)
		if(inside)
			inside.forceMove(get_turf(src))
			visible_message(span_info("\The [src] is mined away, revealing \the [inside]."))
		else
			visible_message(span_info("\The [src] is mined away into nothing."))
		consume(src, user)
		return INTERACTION_HANDLED_PASS

	if(istype(I, /obj/item/core_sampler))
		var/obj/item/core_sampler/S = I
		S.sample_item(src, user)
		return INTERACTION_HANDLED_PASS

	var/obj/item/storage/bag = I
	var/gathered = istype(bag) && bag.try_collect(src, user)
	if(prob(33))
		src.visible_message(span_warning("[src] crumbles away, leaving some dust and gravel behind."))
		consume(src, user)
	return gathered ? TRUE : INTERACTION_HANDLED_PASS

/obj/item/strangerock/welder_act(mob/user, obj/item/tool)
	var/obj/item/weldingtool/welder = tool.get_welder()
	if(!welder.isOn())
		return ITEM_INTERACT_BLOCKING
	if(welder.get_fuel() < 2)
		visible_message(span_info("A few sparks fly off \the [src], but nothing else happens."))
		welder.remove_fuel(1)
		return ITEM_INTERACT_SUCCESS
	if(loc?.release_refusal(src, user))
		return ITEM_INTERACT_BLOCKING
	var/obj/item/inside = locate_within(src, /obj/item)
	if(inside)
		inside.forceMove(get_turf(src))
		visible_message(span_info("\The [src] burns away revealing \the [inside]."))
	else
		visible_message(span_info("\The [src] burns away into nothing."))
	welder.remove_fuel(2)
	consume(src, user)
	return ITEM_INTERACT_SUCCESS

