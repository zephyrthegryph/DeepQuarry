/obj/structure/extinguisher_cabinet
	name = "extinguisher cabinet"
	desc = "A small wall mounted cabinet designed to hold a fire extinguisher."
	icon = 'icons/obj/closet.dmi'
	icon_state = "extinguisher" // map preview sprite
	layer = ABOVE_WINDOW_LAYER
	anchored = TRUE
	density = FALSE
	flags = WALL_ITEM
	var/obj/item/extinguisher/has_extinguisher
	var/opened = 0

CAPABILITIES(/obj/structure/extinguisher_cabinet)
	param(nameof(dir), pos = 1)
	param(nameof(building), pos = 2)

/// A cabinet built on a wall (its constructor param).
/obj/structure/extinguisher_cabinet/var/building = FALSE

// ALLOW(init/INSTANCE_STATE): a built cabinet sits on its wall empty; a mapped one comes with its extinguisher
/obj/structure/extinguisher_cabinet/Initialize(mapload)
	. = ..()

	if(building)
		pixel_x = (dir & 3)? 0 : (dir == 4 ? -27 : 27)
		pixel_y = (dir & 3)? (dir ==1 ? -27 : 27) : 0
	else
		rel_set(src, nameof(has_extinguisher), new/obj/item/extinguisher(src))
		observe(has_extinguisher, /datum/notice/qdeleting, src, then(PROC_REF(on_extinguisher_deleted)))

	update_icon()

/obj/structure/extinguisher_cabinet/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_item/extinguisher_cabinet_item,
		/datum/interaction/entry_hand/extinguisher_cabinet_hand,
	)
	into += dq_interaction_from_spec(type, INTERACT_TK(null, PROC_REF(interaction_tk)))
	..()

/// Old attackby: store the extinguisher, or just toggle the cabinet open.
/datum/interaction/entry_item/extinguisher_cabinet_item
	id = "extinguisher_cabinet_item"
	name = "Use"
	effect = /obj/structure/extinguisher_cabinet/proc/interaction_item

/obj/structure/extinguisher_cabinet/proc/interaction_item(mob/user, obj/item/O, datum/interaction/interaction)
	if(isrobot(user))
		return TRUE
	if(istype(O, /obj/item/extinguisher))
		if(!has_extinguisher && opened)
			if(!move_into(src, nameof(src.has_extinguisher), O, user))
				return TRUE
			observe(has_extinguisher, /datum/notice/qdeleting, src, then(PROC_REF(on_extinguisher_deleted)))
			to_chat(user, span_notice("You place [O] in [src]."))
		else
			opened = !opened
	else
		opened = !opened
	update_icon()
	return TRUE

/obj/structure/extinguisher_cabinet/wrench_act(mob/user, obj/item/O)
	if(isrobot(user))
		return TRUE
	if(has_extinguisher)
		opened = !opened
		update_icon()
		return TRUE
	use_tool(user, O, src, delay = 1.5 SECONDS, quality = TOOL_WRENCH, volume = 50, start_self = "You start to unwrench the extinguisher cabinet.", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
	return TRUE

/obj/structure/extinguisher_cabinet/proc/wrench_act_tool_done(mob/user)
	to_chat(user, span_notice("You unwrench the extinguisher cabinet."))
	replace_with(src, /obj/item/frame/extinguisher_cabinet)

/// Old attack_hand: take the extinguisher, or toggle the cabinet open.
/datum/interaction/entry_hand/extinguisher_cabinet_hand
	id = "extinguisher_cabinet_hand"
	name = "Use"
	effect = /obj/structure/extinguisher_cabinet/proc/interaction_hand

/obj/structure/extinguisher_cabinet/proc/interaction_hand(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(isrobot(user))
		return TRUE
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		var/obj/item/organ/external/temp = H.organs_by_name[BP_R_HAND]
		if (user.hand)
			temp = H.organs_by_name[BP_L_HAND]
		if(temp && !temp.is_usable())
			to_chat(user, span_notice("You try to move your [temp.name], but cannot!"))
			return TRUE
	if(has_extinguisher)
		unobserve(has_extinguisher, /datum/notice/qdeleting, src)
		user.put_in_hands(has_extinguisher)
		to_chat(user, span_notice("You take [has_extinguisher] from [src]."))
		own_take(src, nameof(has_extinguisher))
		opened = 1
	else
		opened = !opened
	update_icon()
	return TRUE

/// Old attack_tk: pull the extinguisher out at range, or toggle the cabinet.
/obj/structure/extinguisher_cabinet/proc/interaction_tk(mob/user, obj/item/held, datum/interaction/interaction)
	if(has_extinguisher)
		unobserve(has_extinguisher, /datum/notice/qdeleting, src)
		has_extinguisher.forceMove(loc)
		to_chat(user, span_notice("You telekinetically remove [has_extinguisher] from [src]."))
		own_take(src, nameof(has_extinguisher))
		opened = 1
	else
		opened = !opened
	update_icon()
	return TRUE

/obj/structure/extinguisher_cabinet/proc/on_extinguisher_deleted(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/source = A.target
	if(source != has_extinguisher)
		return
	own_take(src, nameof(has_extinguisher))
	opened = TRUE
	update_icon()

/obj/structure/extinguisher_cabinet/proc/appearance_suffix()
	if(!has_extinguisher)
		return "empty"
	if(istype(has_extinguisher, /obj/item/extinguisher/mini))
		return "mini"
	if(istype(has_extinguisher, /obj/item/extinguisher/atmo))
		return "advanced"
	return "standard"

APPEARANCE_TEMPLATE(/obj/structure/extinguisher_cabinet, "{initial(icon_state)}{opened?:_closed}_{appearance_suffix}")

/obj/structure/extinguisher_cabinet/old
	name = "extinguisher cabinet"
	desc = "A classic small wall mounted cabinet designed to hold a fire extinguisher."
	icon = 'icons/obj/closet.dmi'
	icon_state = "oldextinguisher" // map preview sprite

/obj/structure/extinguisher_cabinet/ownership()
	. = ..()
	. += owns(nameof(has_extinguisher), policy = OWN_CONTAINED)
