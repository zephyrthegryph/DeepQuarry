
/obj/item/bodybag/cryobag/robobag
	name = "synthmorph bag"
	desc = "A reusable polymer bag designed to slow down synthetic functions such as data corruption and coolant flow, \
	especially useful if short on time or in a hostile enviroment."
	icon = 'icons/obj/robobag.dmi'
	icon_state = "bodybag_folded"
	item_state = "bodybag_cryo_folded"
	robotic = TRUE
	cryogenic = FALSE

/obj/structure/closet/body_bag/cryobag/robobag
	name = "synthmorph bag"
	desc = "A reusable polymer bag designed to slow down synthetic functions such as data corruption and coolant flow, \
	especially useful if short on time or in a hostile enviroment."
	icon = 'icons/obj/robobag.dmi'
	item_path = /obj/item/bodybag/cryobag/robobag
	tank_type = /obj/item/tank/stasis/nitro_cryo
	stasis_level = /datum/body_effect/stasis/light	// Lower than the normal cryobag, because it's not made for meat that dies. It's made for robots and is freezing.
	var/obj/item/clothing/accessory/badge/corptag	// The tag on the bag.

/obj/structure/closet/body_bag/cryobag/robobag/examine(mob/user)
	. = ..()
	if(corptag && Adjacent(user))
		. += span_notice("[src] has a [corptag] attached to it.")

DECLARE_APPEARANCE_PROC(/obj/structure/closet/body_bag/cryobag/robobag, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/structure/closet/body_bag/cryobag/robobag/appearance_overlays()
	. = list()
	. += ..()
	if(corptag)
		var/corptag_icon_state = "tag_blank"
		if(istype(corptag,/obj/item/clothing/accessory/badge/holo/detective) || istype(corptag, /obj/item/clothing/accessory/badge/holo/hos) || istype(corptag, /obj/item/clothing/accessory/badge/old) || istype(corptag, /obj/item/clothing/accessory/badge/sheriff))
			corptag_icon_state = "tag_badge_gold"
		else if(istype(corptag, /obj/item/clothing/accessory/badge/holo/warden))
			corptag_icon_state = "tag_badge_silver"
		else if(istype(corptag, /obj/item/clothing/accessory/badge/holo))
			corptag_icon_state = "tag_badge_blue"
		else if(istype(corptag, /obj/item/clothing/accessory/badge/corporate_tag))
			corptag_icon_state = corptag.icon_state

		. += corptag_icon_state

MSG_DEF(robobag/tag_removed, "You remove %I% from %T%.", "%U% removes the tag from %T%.")

// A synthmorph bag is a stasis bag for machines: a shut one is scanned with a cyborg analyzer, takes a corporate tag (a badge) in exchange for the one it has,
// and gives the tag back to an alt-click.
CAPABILITIES(/obj/structure/closet/body_bag/cryobag/robobag)
	owns_one(nameof(corptag), /obj/item/clothing/accessory/badge)
	op("scan_robot", item(/obj/item/robotanalyzer), label("Scan"), when(cond_not(nameof(opened))), priority(OP_PRIORITY_PART), then(PROC_REF(robot_analyser_used)))
	op("swap_tag", item(/obj/item/clothing/accessory/badge), label("Attach tag"), when(cond_not(nameof(opened))), priority(OP_PRIORITY_PART), then(PROC_REF(tag_swapped)))
	op("remove_tag", hand(), gesture(GESTURE_ALT), label("Remove tag"), when(req_bool(PROC_REF(has_tag))), then(PROC_REF(tag_removed)))

/// There is a tag on the bag.
/obj/structure/closet/body_bag/cryobag/robobag/proc/has_tag(datum/act/op/A)
	return !!corptag

/// The tag comes off onto the floor at the one taking it.
/obj/structure/closet/body_bag/cryobag/robobag/proc/tag_removed(datum/act/op/A)
	var/obj/item/clothing/accessory/badge/old_tag = corptag
	old_tag.forceMove(get_turf(A.actor))
	to_chat(A.actor, span_notice("You remove \the [old_tag] from \the [src]."))
	rel_take(src, nameof(corptag))
	update_icon()
	return OP_OK

// its corpse tag drops to the floor.
// The tag is kept in nullspace, not in contents: owned, so phase 4 deletes it
// unless on_destroy has already dropped it on the bag's turf.

/obj/structure/closet/body_bag/cryobag/robobag/on_destroy(force)
	var/turf/T = get_turf(src)
	if(corptag && T)
		corptag.forceMove(T)
		rel_take(src, nameof(corptag))
	..()

/obj/structure/closet/body_bag/cryobag/robobag/Entered(atom/movable/AM)
	..()
	if(ishuman(AM))
		var/mob/living/carbon/human/H = AM
		if(HAS_SYNTHETIC_BIOLOGY(H))
			if(!H.treatment_demand(/datum/diagnostic_profile/robot_analyzer)?[TREAT_SYSTEM_RESTORE])	// We don't exactly care about the bag being 'used' when containing a synth, unless it's got work.
				set_used(FALSE)
			else
				H.apply_body_effect(/datum/body_effect/fbp_debug/robobag)

/// A cyborg analyzer reads every one inside, through the skin.
/obj/structure/closet/body_bag/cryobag/robobag/proc/robot_analyser_used(datum/act/op/A)
	var/obj/item/robotanalyzer/analyzer = A.held
	for(var/mob/living/L in contents) // ALLOW(latent): mobs are never latent
		analyzer.attack(L, A.actor)
	return OP_OK

/// A badge is attached as the bag's tag; the tag it had falls to the floor.
/obj/structure/closet/body_bag/cryobag/robobag/proc/tag_swapped(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(corptag)
		var/old_tag = corptag
		corptag.forceMove(get_turf(src))
		rel_take(src, nameof(src.corptag))
		if(!user.unEquip(W))
			return OP_REFUSED
		W.moveToNullspace()
		rel_set(src, nameof(src.corptag), W)
		to_chat(user, span_notice("You swap \the [old_tag] for \the [corptag]."))
	else
		if(!user.unEquip(W))
			return OP_REFUSED
		W.moveToNullspace()
		rel_set(src, nameof(src.corptag), W)
		to_chat(user, span_notice("You attach \the [corptag] to \the [src]."))
	update_icon()
	return OP_OK

/datum/body_effect/fbp_debug
	tick_interval = 2 SECONDS
	name = "defragmenting"
	desc = "Your software is being debugged."
	mob_overlay_state = "signal_blue"

	on_created_text = span_notice("You feel something pour over your senses.")
	on_expired_text = span_notice("Your mind is clear once more.")
	stacks = MODIFIER_STACK_FORBID

/datum/body_effect/fbp_debug/on_tick(mob/living/L)
	if(L.treatment_demand(/datum/diagnostic_profile/robot_analyzer)?[TREAT_SYSTEM_RESTORE])
		L.mend(TREAT_SYSTEM_RESTORE, rand(1,5))

/datum/body_effect/fbp_debug/can_apply(mob/living/L)
	if(!HAS_SYNTHETIC_BIOLOGY(L))
		return FALSE
	return TRUE

/datum/body_effect/fbp_debug/on_check(mob/living/L)
	..()
	if(!L.treatment_demand(/datum/diagnostic_profile/robot_analyzer)?[TREAT_SYSTEM_RESTORE])
		L.end_body_effect(type)

/datum/body_effect/fbp_debug/robobag/on_check(mob/living/L)
	..()
	if(!istype(L.loc, /obj/structure/closet/body_bag/cryobag/robobag))
		L.end_body_effect(type)
