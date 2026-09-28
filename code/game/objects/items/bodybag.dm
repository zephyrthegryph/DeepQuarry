//Also contains /obj/structure/closet/body_bag because I doubt anyone would think to look for bodybags in /object/structures

/obj/item/bodybag
	name = "body bag"
	desc = "A folded bag designed for the storage and transportation of cadavers."
	icon = 'icons/obj/closets/bodybag.dmi'
	icon_state = "bodybag_folded"
	w_class = ITEMSIZE_SMALL

	//Used for cryogenic bodybags
	var/obj/item/reagent_containers/syringe/syringe
	var/cryogenic = FALSE
	var/robotic = FALSE
	var/mass_grave = FALSE

/obj/item/bodybag/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	if(mass_grave) // TODO, upport this.
		return FALSE // TODO, upport this.

	if(cryogenic)
		var/obj/structure/closet/body_bag/cryobag/R = new /obj/structure/closet/body_bag/cryobag(user.loc)
		R.add_fingerprint(user)
		if(syringe)
			R.syringe = syringe
			syringe = null
		consume(src, user)
		return
	if(robotic)
		var/obj/structure/closet/body_bag/cryobag/robobag/R = new /obj/structure/closet/body_bag/cryobag/robobag(user.loc)
		R.add_fingerprint(user)
		if(syringe)
			R.syringe = syringe
			syringe = null
		consume(src, user)
		return
	var/obj/structure/closet/body_bag/R = new /obj/structure/closet/body_bag(user.loc)
	R.add_fingerprint(user)
	consume(src, user)
	return

/obj/item/storage/box/bodybags
	name = "body bags"
	desc = "This box contains body bags."
	icon_state = "bodybags"
	starts_with = list(/obj/item/bodybag = 7)

/obj/structure/closet/body_bag
	name = "body bag"
	desc = "A plastic bag designed for the storage and transportation of cadavers."
	icon = 'icons/obj/closets/bodybag.dmi'
	closet_appearance = null
	open_sound = 'sound/items/zip.ogg'
	close_sound = 'sound/items/zip.ogg'
	var/item_path = /obj/item/bodybag
	density = FALSE
	storage_capacity = (MOB_MEDIUM * 2) - 1
	var/contains_body = FALSE
	var/has_label = FALSE

/obj/item/bodybag/large
	name = "mass grave body bag"
	desc = "A large folded bag designed for the storage and transportation of cadavers."
	icon = 'icons/obj/closets/bodybag_large.dmi'
	w_class = ITEMSIZE_LARGE
	mass_grave = TRUE

/obj/item/bodybag/large/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	var/obj/structure/closet/body_bag/large/R = new /obj/structure/closet/body_bag/large(user.loc)
	R.add_fingerprint(user)
	consume(src, user)

/obj/structure/closet/body_bag/large
	name = "mass grave body bag"
	desc = "A massive body bag that holds as much as it does due to bluespace lining on its zipper. Shockingly compact for its storage."
	icon = 'icons/obj/closets/bodybag_large.dmi'
	storage_capacity = (MOB_MEDIUM * 12) - 1 //Holds 12 bodys
	item_path = /obj/item/bodybag/large

/// Labelling a body bag with a pen (the subject, still in hand). Re-checked on the answer: the bag is still in reach.
/datum/om/prompt/text/body_bag_label
	message = "What would you like the label to be?"
	max_length = MAX_NAME_LEN
	requires = PROMPT_IN_HAND
	var/obj/structure/closet/body_bag/bag

/datum/om/prompt/text/body_bag_label/valid()
	return (in_range(bag, answerer) || bag.loc == answerer) ? null : "too far away"

/obj/structure/closet/body_bag/proc/label_entered(datum/om/prompt/text/body_bag_label/ask)
	var/t = sanitizeSafe(ask.text, MAX_NAME_LEN)
	if (t)
		src.name = "body bag - "
		src.name += t
		has_label = TRUE
		add_overlay("bodybag_label")
	else
		src.name = "body bag"

EXTEND_INTERACTIONS(/obj/structure/closet/body_bag, INTERACT_ITEM(null, PROC_REF(body_bag_interaction_item)))

/// Old attackby: label it with a pen. Nothing else reaches the closet's item handling
/// (a body bag can't be welded or have things stuffed in by hand).
/obj/structure/closet/body_bag/proc/body_bag_interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if (istype(W, /obj/item/pen))
		om_ask(user, /datum/om/prompt/text/body_bag_label, PROC_REF(label_entered), subject = W, bag = src, title = "[src.name]")
	return INTERACTION_HANDLED_PASS

/obj/structure/closet/body_bag/store_mobs()
	contains_body = ..()
	return contains_body

/obj/structure/closet/body_bag/close()
	if(..())
		density = FALSE
		return 1
	return 0

/obj/structure/closet/body_bag/MouseDrop(over_object, src_location, over_location)
	..()
	if((over_object == usr && (in_range(src, usr) || usr.contents.Find(src))))
		if(!ishuman(usr))	return 0
		if(opened)	return 0
		if(contents.len || has_latent())	return 0 // ALLOW(latent): latent entries checked
		visible_message("[usr] folds up the [src.name]")
		var/folded = new item_path(get_turf(src))
		om_qdel_after(src, 0)
		return folded

/obj/structure/closet/body_bag/relaymove(mob/user,direction)
	if(src.loc != get_turf(src))
		src.loc.relaymove(user,direction)
	else
		..()

/obj/structure/closet/body_bag/proc/get_occupants()
	var/list/occupants = list()
	for(var/mob/living/carbon/human/H in contents) // ALLOW(latent): mobs are never latent
		occupants += H
	return occupants

/obj/structure/closet/body_bag/proc/update(broadcast=0)
	if(istype(loc, /obj/structure/morgue))
		var/obj/structure/morgue/M = loc
		M.update(broadcast)

/obj/structure/closet/body_bag/update_icon()
	if(opened)
		icon_state = "open"
	else
		icon_state = "base"

	cut_overlays()
	if(has_label)
		add_overlay("bodybag_label")

/obj/item/bodybag/cryobag
	name = "stasis bag"
	desc = "A non-reusable plastic bag designed to slow down bodily functions such as circulation and breathing, \
	especially useful if short on time or in a hostile environment."		// CHOMPEDIT : purdev (spelling fix)
	icon = 'icons/obj/closets/cryobag.dmi'
	icon_state = "bodybag_folded"
	item_state = "bodybag_cryo_folded"
	cryogenic = TRUE

/obj/structure/closet/body_bag/cryobag
	name = "stasis bag"
	desc = "A non-reusable plastic bag designed to slow down bodily functions such as circulation and breathing, \
	especially useful if short on time or in a hostile enviroment."
	icon = 'icons/obj/closets/cryobag.dmi'
	item_path = /obj/item/bodybag/cryobag
	store_misc = 0
	store_items = 0
	var/used = 0
	var/obj/item/tank/tank = null
	var/tank_type = /obj/item/tank/stasis/oxygen
	/// Stasis modifier (/datum/body_effect/stasis/*) applied to whoever lies inside.
	var/stasis_level = /datum/body_effect/stasis/deep
	var/obj/item/reagent_containers/syringe/syringe

/obj/structure/closet/body_bag/cryobag/Initialize(mapload)
	tank = new tank_type(null) //It's in nullspace to prevent ejection when the bag is opened.
	..()

REF_OWNED(/obj/structure/closet/body_bag/cryobag, list("syringe", "tank"))

EXTEND_INTERACTIONS(/obj/structure/closet/body_bag/cryobag, \
	INTERACT_HAND(null, PROC_REF(cryobag_interaction_hand)), \
	INTERACT_ITEM(null, PROC_REF(cryobag_interaction_item)), \
)

/// Old attack_hand.
/obj/structure/closet/body_bag/cryobag/proc/cryobag_interaction_hand(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(used)
		om_ask(user, /datum/om/prompt/confirm, PROC_REF(open_confirmed), message = "Are you sure you want to open \the [src]? \The [src] will expire upon opening it.", title = "Confirm Opening", no_first = TRUE, requires = PROMPT_ADJACENT)
	else
		return FALSE
	return TRUE

/obj/structure/closet/body_bag/cryobag/proc/open_confirmed(datum/om/prompt/confirm/ask)
	add_fingerprint(ask.answerer)
	toggle(ask.answerer) // What the parent attack_hand does: opens the bag.

/obj/structure/closet/body_bag/cryobag/open()
	. = ..()
	if(used)
		replace_with(src, /obj/item/usedcryobag)

/obj/structure/closet/body_bag/cryobag/update_icon()
	..()
	cut_overlays()
	var/image/I = image(icon, "indicator[opened]")
	I.appearance_flags = RESET_COLOR
	I.color = COLOR_LIME
	add_overlay(I)

/obj/structure/closet/body_bag/cryobag/MouseDrop(over_object, src_location, over_location)
	. = ..()
	if(. && syringe)
		var/obj/item/bodybag/cryobag/folded = .
		folded.syringe = syringe
		syringe = null

/obj/structure/closet/body_bag/cryobag/Entered(atom/movable/AM)
	if(isliving(AM))
		var/mob/living/L = AM
		L.set_stasis(stasis_level, src)
	if(ishuman(AM))
		var/mob/living/carbon/human/H = AM
		src.used = 1
		inject_occupant(H)

	if(istype(AM, /obj/item/organ))
		var/obj/item/organ/O = AM
		O.preserved = 1
		for(var/obj/item/organ/organ in O)
			organ.preserved = 1
	..()

/obj/structure/closet/body_bag/cryobag/Exited(atom/movable/AM)
	if(isliving(AM))
		var/mob/living/L = AM
		L.set_stasis(null, src)

	if(istype(AM, /obj/item/organ))
		var/obj/item/organ/O = AM
		O.preserved = 0
		for(var/obj/item/organ/organ in O)
			organ.preserved = 0
	..()

/obj/structure/closet/body_bag/cryobag/return_air() //Used to make stasis bags protect from vacuum.
	if(tank)
		return tank.air_contents
	..()

/obj/structure/closet/body_bag/cryobag/proc/inject_occupant(mob/living/carbon/human/H)
	if(!syringe)
		return

	if(H.reagents)
		syringe.reagents.trans_to_mob(H, 30, CHEM_BLOOD)

/obj/structure/closet/body_bag/cryobag/examine(mob/user)
	. = ..()
	if(Adjacent(user)) //The bag's rather thick and opaque from a distance.
		. += span_info("You peer into \the [src].")
		if(syringe)
			. += span_info("It has a syringe added to it.")
		for(var/mob/living/L in contents) // ALLOW(latent): mobs are never latent
			. += L.examine(user)

/// Old attackby: while closed, scan the occupant or load an injector.
/obj/structure/closet/body_bag/cryobag/proc/cryobag_interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(opened)
		return FALSE
	else //Allows the bag to respond to a health analyzer by analyzing the mob inside without needing to open it.
		if(istype(W,/obj/item/healthanalyzer))
			var/obj/item/healthanalyzer/analyzer = W
			for(var/mob/living/L in contents) // ALLOW(latent): mobs are never latent
				analyzer.attack(L,user)

		else if(istype(W,/obj/item/reagent_containers/syringe))
			if(syringe)
				to_chat(user,span_warning("\The [src] already has an injector! Remove it first."))
			else
				var/obj/item/reagent_containers/syringe/syringe = W
				to_chat(user,span_info("You insert \the [syringe] into \the [src], and it locks into place."))
				user.unEquip(syringe)
				src.syringe = syringe
				syringe.moveToNullspace()
				for(var/mob/living/carbon/human/H in contents) // ALLOW(latent): mobs are never latent
					inject_occupant(H)
					break

		else
			return FALSE
	return INTERACTION_HANDLED_PASS

/obj/structure/closet/body_bag/wirecutter_act(mob/user, obj/item/W)
	to_chat(user, "You cut the tag off the bodybag")
	src.name = "body bag"
	has_label = FALSE
	cut_overlays()
	return ITEM_INTERACT_SUCCESS

/obj/structure/closet/body_bag/cryobag/screwdriver_act(mob/user, obj/item/W)
	if(opened)
		return NONE
	if(syringe)
		if(used)
			to_chat(user,span_warning("The injector cannot be removed now that the stasis bag has been used!"))
		else
			syringe.forceMove(src.loc)
			to_chat(user,span_info("You pry \the [syringe] out of \the [src]."))
			syringe = null
	return ITEM_INTERACT_SUCCESS

/obj/item/usedcryobag
	name = "used stasis bag"
	desc = "Pretty useless now.."
	icon_state = "bodybag_used"
	icon = 'icons/obj/closets/cryobag.dmi'

REF_HELD(/obj/item/bodybag, list("syringe"))
