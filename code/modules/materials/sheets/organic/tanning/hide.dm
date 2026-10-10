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
	// One hide every 2.5 seconds until the stack is used up or the user stops.
	op("animalhide_interaction_item", item(/obj/item), when(req(PROC_REF(held_cuts))), begins(MSG(animalhide/cutting), blind = "You hear the sound of a knife rubbing against flesh"),
		wait(2.5 SECONDS, repeats = PROC_REF(scrape_more), after_step = PROC_REF(scrape_one)), on_interrupt(PROC_REF(scrape_report)), then(PROC_REF(scrape_finished)))

MSG_DEF(animalhide/cutting, span_notice("You start cutting the hair off %T%"), span_infoplain(span_bold("%U%") + " starts cutting hair off %T%"))

/obj/item/stack/animalhide/proc/held_cuts(datum/act/op/A)
	return has_edge(A.held) || is_sharp(A.held)

/// Another hide follows while the stack has any left.
/obj/item/stack/animalhide/proc/scrape_more(datum/act/op/A)
	return amount > 0

/obj/item/stack/animalhide/proc/scrape_report(datum/act/op/A)
	var/scraped = A.laps()
	if(scraped && A.actor)
		to_chat(A.actor, span_notice("You scrape the hair off [scraped] hide\s."))

/// The series ended on its own: say how many and clean up the stack when the last hide went.
/obj/item/stack/animalhide/proc/scrape_finished(datum/act/op/A)
	scrape_report(A)
	if(amount <= 0)
		spent(src)

/// One hide scraped.
/obj/item/stack/animalhide/proc/scrape_one(datum/act/op/A)
	var/mob/user = A.actor
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

	set_amount(amount - 1, TRUE)

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
