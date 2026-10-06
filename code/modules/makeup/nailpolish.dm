/obj/item/organ/external/var/datum/nail_polish/nail_polish

// The limb's CAPABILITIES block (organ_external.dm) owns its nail polish.

/obj/item/nailpolish
	name = "nail polish"
	desc = "to paint your nails with. Or someone else's!"
	icon = 'icons/obj/nailpolish_vr.dmi'
	icon_state = "nailpolish"
	w_class = ITEMSIZE_SMALL
	var/colour = "#FFFFFF"
	var/image/top_underlay
	var/image/color_underlay
	var/open = FALSE
	drop_sound = SFX_ITEMS_DROP_GLASS
	pickup_sound = SFX_ITEMS_PICKUP_GLASS

// ALLOW(init/INSTANCE_STATE): its description and sprite show the colour it was given
/obj/item/nailpolish/Initialize(mapload)
	. = ..()
	desc = "<font color='[colour]'>Nail polish,</font> " + initial(desc)
	top_underlay = image(icon, "top")
	color_underlay = image(icon, "color")
	update_icon()

/obj/item/nailpolish/proc/set_colour(_colour)
	colour = _colour
	desc = "<font color='[colour]'>Nail polish,</font> " + initial(desc)
	update_icon()

CAPABILITIES(/obj/item/nailpolish)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/nailpolish/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	open = !open
	to_chat(user, span_notice("You [open ? "open" : "close"] \the [src]."))
	update_icon()
	return TRUE

DECLARE_APPEARANCE_PROC(/obj/item/nailpolish, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/nailpolish/appearance_overlays()
	. = list()
	. += ..()
	icon_state = "[initial(icon_state)][open ? "-open" : ""]"
	top_underlay.icon_state = "top[open ? "-open" : ""]"
	color_underlay.icon_state = "color[open ? "-open" : ""]"
	color_underlay.color = colour
	underlays = list(color_underlay, top_underlay)

/obj/item/organ/external/proc/get_polish(colour)
	var/static/forbidden_parts = BP_ALL - list(BP_L_HAND, BP_R_HAND, BP_L_FOOT, BP_R_FOOT)
	if(organ_tag in forbidden_parts)
		return FALSE
	var/ico
	var/icostate
	if(length(markings))
		for(var/mark_name in markings)
			var/mark_data = markings[mark_name]
			var/datum/sprite_accessory/marking/mark = mark_data["datum"]
			if(mark.body_parts && length(mark.body_parts & forbidden_parts))
				continue
			ico = mark.icon
			icostate = "[mark.icon_state]-[organ_tag]"
			break
	else
		ico = 'icons/obj/nailpolish_vr.dmi'
		icostate = organ_tag
	return new /datum/nail_polish(ico, icostate, colour)

/obj/item/nailpolish/attack(mob/living/target, mob/living/user, target_zone, attack_modifier)
	if(!open)
		return ITEM_INTERACT_FAILURE

	if(!istype(target))
		return ITEM_INTERACT_FAILURE

	var/bp = user.zone_sel.selecting
	var/obj/item/organ/external/body_part = target.get_organ(bp)
	if(!body_part)
		to_chat(user, span_warning("[target] is missing that limb!"))
		return ITEM_INTERACT_FAILURE
	if(body_part.nail_polish)
		to_chat(user, span_notice("[target]'s [body_part.name] already has nail polish on!"))
		return ITEM_INTERACT_FAILURE
	var/datum/nail_polish/polish = body_part.get_polish(colour)
	if(!polish)
		to_chat(user, span_notice("You can't find any nails on [body_part] to paint."))
		return ITEM_INTERACT_FAILURE
	if(user == target)
		act_message(user, src, MSG_SELF(span_infoplain("You paint your nails with %T%.")), \
			MSG_OTHERS(span_infoplain(span_bold("%U%") + " paints their nails with %T%.")))
	else
		om_task_start(/datum/om/task/timed/nailpolish_paint, user, target, body_part = body_part, polish = polish, fail_message = span_notice("Both you and [target] must stay still!"))
		return ITEM_INTERACT_SUCCESS
	body_part.set_polish(polish)
	return ITEM_INTERACT_SUCCESS

/datum/om/task/timed/nailpolish_paint
	duration = 2 SECONDS
	complete_proc = /obj/item/nailpolish/proc/paint_done
	var/obj/item/organ/external/body_part
	var/datum/nail_polish/polish

/obj/item/nailpolish/proc/paint_done(datum/om/task/timed/nailpolish_paint/task)
	var/mob/living/user = task.actor
	var/mob/living/target = task.target
	var/obj/item/organ/external/body_part = task.body_part
	var/datum/nail_polish/polish = task.polish
	if(body_part.nail_polish)
		return
	act_message(user, target, MSG_SELF(span_infoplain("You paint %T%'s nails with \the [src].")), \
		MSG_OTHERS(span_infoplain(span_bold("%U%") + " paints %T%'s nails with \the [src].")))
	body_part.set_polish(polish)

/obj/item/organ/external/proc/set_polish(datum/nail_polish/polish)
	rel_set(src, nameof(nail_polish), polish)
	owner?.update_icons_body()

/obj/item/nailpolish_remover
	name = "nail polish remover"
	desc = "Paint thinner, acetone, nail polish remover; whatever you call it, it gets the job done."
	drop_sound = SFX_ITEMS_DROP_HELM
	pickup_sound = SFX_ITEMS_PICKUP_HELM
	icon = 'icons/obj/nailpolish_vr.dmi'
	icon_state = "nailpolishremover"
	var/open = FALSE

CAPABILITIES(/obj/item/nailpolish_remover)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/nailpolish_remover/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	open = !open
	to_chat(user, span_notice("You [open ? "open" : "close"] \the [src]."))
	return TRUE

/// The look (the draw sweep: from its template).
/obj/item/nailpolish_remover/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][open ? "-open" : ""]")

/obj/item/nailpolish_remover/attack(mob/living/target, mob/living/user, target_zone, attack_modifier)
	if(!open)
		return ITEM_INTERACT_FAILURE

	if(!istype(target))
		return ITEM_INTERACT_FAILURE

	var/bp = user.zone_sel.selecting
	var/obj/item/organ/external/body_part = target.get_organ(bp)
	if(!body_part)
		to_chat(user, span_warning("[target] is missing that limb!"))
		return ITEM_INTERACT_FAILURE
	if(!body_part.nail_polish)
		to_chat(user, span_notice("[target]'s [body_part.name] has no nail polish to remove!"))
		return ITEM_INTERACT_FAILURE
	if(user == target)
		act_message(user, src, MSG_SELF(span_infoplain("You remove your nail polish with %T%.")), \
			MSG_OTHERS(span_infoplain(span_bold("%U%") + " removes their nail polish with %T%.")))
	else
		om_task_start(/datum/om/task/timed/nailpolish_remover_remove, user, target, body_part = body_part, fail_message = span_notice("Both you and [target] must stay still!"))
		return ITEM_INTERACT_SUCCESS
	body_part.set_polish(null)
	return ITEM_INTERACT_SUCCESS

/datum/om/task/timed/nailpolish_remover_remove
	duration = 2 SECONDS
	complete_proc = /obj/item/nailpolish_remover/proc/remove_done
	var/obj/item/organ/external/body_part

/obj/item/nailpolish_remover/proc/remove_done(datum/om/task/timed/nailpolish_remover_remove/task)
	var/mob/living/user = task.actor
	var/mob/living/target = task.target
	var/obj/item/organ/external/body_part = task.body_part
	act_message(user, target, MSG_SELF(span_infoplain("You remove %T%'s nail polish with \the [src].")), \
		MSG_OTHERS(span_infoplain(span_bold("%U%") + " removes %T%'s nail polish with \the [src].")))
	body_part.set_polish(null)

/datum/nail_polish
	var/icon = 'icons/obj/nailpolish_vr.dmi'
	var/icon_state
	var/color

/datum/nail_polish/New(_icon, _icon_state, _color)
	icon = _icon
	icon_state = _icon_state
	color = _color

