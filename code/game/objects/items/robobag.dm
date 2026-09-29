
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

DECLARE_APPEARANCE_PROC(/obj/structure/closet/body_bag/cryobag/robobag, PROC_REF(appearance_overlays), list())
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

EXTEND_INTERACTIONS(/obj/structure/closet/body_bag/cryobag/robobag, \
	INTERACT_ALT(null, PROC_REF(interaction_alt)), \
	INTERACT_ITEM(null, PROC_REF(robobag_interaction_item)), \
)

/// Old click_alt.
/obj/structure/closet/body_bag/cryobag/robobag/proc/interaction_alt(mob/user, obj/item/held, datum/interaction/interaction)
	if(!Adjacent(user))
		return FALSE
	if(corptag)
		corptag.forceMove(get_turf(user))
		to_chat(user, span_notice("You remove \the [corptag] from \the [src]."))
		corptag = null
		update_icon()
		return TRUE
	return FALSE

// its corpse tag drops to the floor.
// The tag is kept in nullspace, not in contents: owned, so phase 4 deletes it
// unless on_destroy has already dropped it on the bag's turf.
DECLARE_REF(/obj/structure/closet/body_bag/cryobag/robobag, "corptag", OWNED, null)

/obj/structure/closet/body_bag/cryobag/robobag/on_destroy(force)
	var/turf/T = get_turf(src)
	if(corptag && T)
		corptag.forceMove(T)
		corptag = null
	..()

/obj/structure/closet/body_bag/cryobag/robobag/Entered(atom/movable/AM)
	..()
	if(ishuman(AM))
		var/mob/living/carbon/human/H = AM
		if(HAS_SYNTHETIC_BIOLOGY(H))
			if(!H.treatment_demand(/datum/diagnostic_profile/robot_analyzer)?[TREAT_SYSTEM_RESTORE])	// We don't exactly care about the bag being 'used' when containing a synth, unless it's got work.
				used = FALSE
			else
				H.apply_body_effect(/datum/body_effect/fbp_debug/robobag)

/// Old attackby: while closed, scan the occupant or swap its corporate tag.
/obj/structure/closet/body_bag/cryobag/robobag/proc/robobag_interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(opened)
		return FALSE
	else //Allows the bag to respond to a cyborg analyzer and tag.
		if(istype(W,/obj/item/robotanalyzer))
			var/obj/item/robotanalyzer/analyzer = W
			for(var/mob/living/L in contents) // ALLOW(latent): mobs are never latent
				analyzer.attack(L,user)

		else if(istype(W, /obj/item/clothing/accessory/badge))
			if(corptag)
				var/old_tag = corptag
				corptag.forceMove(get_turf(src))
				corptag = W
				user.unEquip(corptag)
				corptag.moveToNullspace()
				to_chat(user, span_notice("You swap \the [old_tag] for \the [corptag]."))
			else
				corptag = W
				user.unEquip(corptag)
				corptag.moveToNullspace()
				to_chat(user, span_notice("You attach \the [corptag] to \the [src]."))
			update_icon()

		else
			return FALSE
	return INTERACTION_HANDLED_PASS

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
