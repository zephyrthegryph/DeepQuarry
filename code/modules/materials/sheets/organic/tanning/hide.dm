/obj/item/stack/animalhide/get_mechanics_info(list/additional_information)
	return ..(list("Scrape the hairs/feathers/etc off with something " + span_bold(span_red("sharp")) + " to prepare it for tanning.") + additional_information)

/obj/item/stack/animalhide
	name = "hide"
	desc = "The hide of some creature."
	icon_state = "sheet-hide"
	drop_sound = SFX_ITEMS_DROP_CLOTH
	pickup_sound = SFX_ITEMS_PICKUP_CLOTH
	amount = 1
	max_amount = 20
	stacktype = "hide"
	no_variants = TRUE

//Step one - dehairing.
CAPABILITIES(/obj/item/stack/animalhide)
	op("animalhide_interaction_item", item(/obj/item), then(PROC_REF(animalhide_interaction_item)))

/// Old attackby.
/obj/item/stack/animalhide/proc/animalhide_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(has_edge(W) || is_sharp(W))
		//visible message on mobs is defined as visible_message(var/message, var/self_message, var/blind_message)
		act_message(user, src, MSG_SELF(span_notice("You start cutting the hair off %T%")), \
			MSG_OTHERS(span_infoplain(span_bold("%U%") + " starts cutting hair off %T%")), \
			MSG_BLIND("You hear the sound of a knife rubbing against flesh"))
		if(amount > 0)
			task_start(/datum/task/timed/scrape_hides, user, null, duration = 2.5 SECONDS)
	else
		return OP_DECLINE
	return OP_PASS

/// Scraping the stack one hide every 2.5 seconds until it is used up or the user stops.
/datum/task/timed/scrape_hides
	steps = list(/obj/item/stack/animalhide/proc/scrape_one = 2.5 SECONDS)
	complete_proc = /obj/item/stack/animalhide/proc/scrape_report
	cancel_proc = /obj/item/stack/animalhide/proc/scrape_report
	var/scraped = 0

/obj/item/stack/animalhide/proc/scrape_report(datum/task/timed/scrape_hides/task)
	if(task.scraped && task.actor)
		to_chat(task.actor, span_notice("You scrape the hair off [task.scraped] hide\s."))
	task.scraped = 0

/obj/item/stack/animalhide/proc/scrape_one(datum/task/timed/scrape_hides/task)
	var/mob/user = task.actor
	//Try locating an exisitng stack on the tile and add to there if possible
	var/obj/item/stack/hairlesshide/H = null
	for(var/obj/item/stack/hairlesshide/HS in user.loc) // Could be scraping something inside a locker, hence the .loc, not get_turf
		if(HS.get_amount() < HS.max_amount)
			H = HS
			break

	// Either we found a valid stack, in which case increment amount,
	// Or we need to make a new stack
	if(istype(H))
		H.add(1)
	else
		H = new /obj/item/stack/hairlesshide(user.loc)

	// Increment the amount
	task.scraped++
	if(amount <= 1)
		scrape_report(task) // before the last one goes, and the stack with it
		src.use(1)
		return STEP_DONE
	src.use(1)
	return STEP_REPEAT(2.5 SECONDS)

/obj/item/stack/animalhide/human
	name = "skin"
	desc = "The by-product of sapient farming."
	singular_name = "skin piece"
	icon_state = "sheet-hide"
	no_variants = FALSE
	drop_sound = SFX_ITEMS_DROP_LEATHER
	pickup_sound = SFX_ITEMS_PICKUP_LEATHER
	stacktype = "hide-human"

/obj/item/stack/animalhide/corgi
	name = "corgi hide"
	desc = "The by-product of corgi farming."
	singular_name = "corgi hide piece"
	icon_state = "sheet-corgi"
	stacktype = "hide-corgi"

/obj/item/stack/animalhide/cat
	name = "cat hide"
	desc = "The by-product of cat farming."
	singular_name = "cat hide piece"
	icon_state = "sheet-cat"
	stacktype = "hide-cat"

/obj/item/stack/animalhide/monkey
	name = "monkey hide"
	desc = "The by-product of monkey farming."
	singular_name = "monkey hide piece"
	icon_state = "sheet-monkey"
	stacktype = "hide-monkey"

/obj/item/stack/animalhide/lizard
	name = "lizard skin"
	desc = "Sssssss..."
	singular_name = "lizard skin piece"
	icon_state = "sheet-lizard"
	stacktype = "hide-lizard"

/obj/item/stack/animalhide/xeno
	name = "alien hide"
	desc = "The skin of a terrible creature."
	singular_name = "alien hide piece"
	icon_state = "sheet-xeno"
	stacktype = "hide-xeno"
