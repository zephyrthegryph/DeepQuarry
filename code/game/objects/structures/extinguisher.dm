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

/obj/structure/extinguisher_cabinet/Initialize(mapload, dir, building = 0)
	. = ..()

	if(building)
		pixel_x = (dir & 3)? 0 : (dir == 4 ? -27 : 27)
		pixel_y = (dir & 3)? (dir ==1 ? -27 : 27) : 0
	else
		has_extinguisher = new/obj/item/extinguisher(src)
		om_hook(has_extinguisher, /datum/om/event/qdeleting, src, PROC_REF(on_extinguisher_deleted))

	update_icon()

/obj/structure/extinguisher_cabinet/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_item/extinguisher_cabinet_item,
		/datum/interaction/entry_hand/extinguisher_cabinet_hand,
	)
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
			user.remove_from_mob(O)
			O.forceMove(src)
			has_extinguisher = O
			om_hook(has_extinguisher, /datum/om/event/qdeleting, src, PROC_REF(on_extinguisher_deleted))
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
	use_tool(user, O, src, delay = 1.5 SECONDS, quality = TOOL_WRENCH, volume = 50, message_self = "You start to unwrench the extinguisher cabinet.", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
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
		om_unhook(has_extinguisher, /datum/om/event/qdeleting, src)
		user.put_in_hands(has_extinguisher)
		to_chat(user, span_notice("You take [has_extinguisher] from [src]."))
		has_extinguisher = null
		opened = 1
	else
		opened = !opened
	update_icon()
	return TRUE

/obj/structure/extinguisher_cabinet/attack_tk(mob/user)
	if(has_extinguisher)
		om_unhook(has_extinguisher, /datum/om/event/qdeleting, src)
		has_extinguisher.forceMove(loc)
		to_chat(user, span_notice("You telekinetically remove [has_extinguisher] from [src]."))
		has_extinguisher = null
		opened = 1
	else
		opened = !opened
	update_icon()

/obj/structure/extinguisher_cabinet/proc/on_extinguisher_deleted(datum/source, datum/om/event/qdeleting/event)
	EVENT_HANDLER
	if(source != has_extinguisher)
		return
	has_extinguisher = null
	opened = TRUE
	update_icon()

/obj/structure/extinguisher_cabinet/update_icon()
	var/suffix = "empty"
	if(has_extinguisher)
		if(istype(has_extinguisher, /obj/item/extinguisher/mini))
			suffix = "mini"
		else if(istype(has_extinguisher, /obj/item/extinguisher/atmo))
			suffix = "advanced"
		else
			suffix = "standard"

	icon_state = "[initial(icon_state)][opened ? "" : "_closed"]_[suffix]"

/obj/structure/extinguisher_cabinet/old
	name = "extinguisher cabinet"
	desc = "A classic small wall mounted cabinet designed to hold a fire extinguisher."
	icon = 'icons/obj/closet.dmi'
	icon_state = "oldextinguisher" // map preview sprite

REF_HELD(/obj/structure/extinguisher_cabinet, list("has_extinguisher"))
