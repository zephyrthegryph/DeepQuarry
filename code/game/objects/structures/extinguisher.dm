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

MSG_DEF_SELF(extinguisher_cabinet/unwrenching, "You start to unwrench the extinguisher cabinet.")
MSG_DEF_SELF(extinguisher_cabinet/unwrenched, "You unwrench the extinguisher cabinet.")

CAPABILITIES(/obj/structure/extinguisher_cabinet)
	param(nameof(dir), pos = 1)
	param(nameof(building), pos = 2)
	// a cyborg's module and gripper do nothing here
	op("item", item(/obj/item), label("Use"), when(req_actor_kind(/mob/living/silicon/robot, not = TRUE)), then(PROC_REF(interaction_item)))
	op("hand", hand(), label("Use"), when(req_actor_kind(/mob/living/silicon/robot, not = TRUE)), then(PROC_REF(interaction_hand)))
	op("tk", tk(), label("Interaction tk"), then(PROC_REF(interaction_tk)))
	// the wrench opens or shuts a cabinet that holds an extinguisher, and takes an empty one off the wall
	op("wrench_toggle", tool(TOOL_WRENCH), label("Use"), wait(0), when(req_actor_kind(/mob/living/silicon/robot, not = TRUE)), when(nameof(has_extinguisher)), then(PROC_REF(toggled)))
	op("unwrench", tool(TOOL_WRENCH), label("Unwrench"), wait(1.5 SECONDS), when(req_actor_kind(/mob/living/silicon/robot, not = TRUE)), when(cond_not(nameof(has_extinguisher))),
		begins(MSG(extinguisher_cabinet/unwrenching)), says(MSG(extinguisher_cabinet/unwrenched)), then(PROC_REF(unwrenched)))
	rolls(ROLL_PIXEL, WALL_OFFSET(27, 27), when = nameof(building))
	owns_one(nameof(has_extinguisher), starts = when(cond_not(nameof(building)), /obj/item/extinguisher), on_lost = PROC_REF(extinguisher_lost), on_destroy = ON_DESTROY_CONTAINED)

/// A cabinet built on a wall (its constructor param).
/obj/structure/extinguisher_cabinet/var/building = FALSE


/// Anything held: an extinguisher goes into an open empty cabinet; anything else opens or shuts it.
/obj/structure/extinguisher_cabinet/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(istype(O, /obj/item/extinguisher))
		if(!has_extinguisher && opened)
			if(!move_into(src, nameof(src.has_extinguisher), O, user))
				return OP_OK
			to_chat(user, span_notice("You place [O] in [src]."))
		else
			set_opened(!opened)
	else
		set_opened(!opened)
	return OP_OK

/// The wrench on a full cabinet: it opens or shuts.
/obj/structure/extinguisher_cabinet/proc/toggled(datum/act/op/A)
	set_opened(!opened)
	return OP_OK

/// The wrench's wait ran out on an empty cabinet: it comes off the wall as its frame.
/obj/structure/extinguisher_cabinet/proc/unwrenched(datum/act/op/A)
	replace_with(src, /obj/item/frame/extinguisher_cabinet)
	return OP_OK

/// A hand takes the extinguisher out, or opens or shuts the cabinet.
/obj/structure/extinguisher_cabinet/proc/interaction_hand(datum/act/op/A)
	var/mob/living/user = A.actor
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		var/obj/item/organ/external/temp = H.organs_by_name[BP_R_HAND]
		if (user.hand)
			temp = H.organs_by_name[BP_L_HAND]
		if(temp && !temp.is_usable())
			to_chat(user, span_notice("You try to move your [temp.name], but cannot!"))
			return OP_OK
	if(has_extinguisher)
		user.put_in_hands(has_extinguisher)
		to_chat(user, span_notice("You take [has_extinguisher] from [src]."))
		rel_take(src, nameof(has_extinguisher))
		set_opened(1)
	else
		set_opened(!opened)
	return OP_OK

/// Telekinesis pulls the extinguisher out at range, or opens or shuts the cabinet.
/obj/structure/extinguisher_cabinet/proc/interaction_tk(datum/act/op/A)
	var/mob/user = A.actor
	if(has_extinguisher)
		has_extinguisher.forceMove(loc)
		to_chat(user, span_notice("You telekinetically remove [has_extinguisher] from [src]."))
		rel_take(src, nameof(has_extinguisher))
		set_opened(1)
	else
		set_opened(!opened)
	return OP_OK

/// owns(on_lost =): the extinguisher left the cabinet (taken, or destroyed in it): the cabinet stands open.
/obj/structure/extinguisher_cabinet/proc/extinguisher_lost(obj/item/extinguisher/E)
	set_opened(TRUE)

/obj/structure/extinguisher_cabinet/proc/appearance_suffix()
	if(!has_extinguisher)
		return "empty"
	if(istype(has_extinguisher, /obj/item/extinguisher/mini))
		return "mini"
	if(istype(has_extinguisher, /obj/item/extinguisher/atmo))
		return "advanced"
	return "standard"

/// The look (the draw sweep: from its template).
/obj/structure/extinguisher_cabinet/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][opened ? "" : "_closed"]_[appearance_suffix()]")

/obj/structure/extinguisher_cabinet/old
	name = "extinguisher cabinet"
	desc = "A classic small wall mounted cabinet designed to hold a fire extinguisher."
	icon = 'icons/obj/closet.dmi'
	icon_state = "oldextinguisher" // map preview sprite

