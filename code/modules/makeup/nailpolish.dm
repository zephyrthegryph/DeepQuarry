/obj/item/organ/external/var/datum/nail_polish/nail_polish

// The limb's CAPABILITIES block (organ_external.dm) owns its nail polish.

/obj/item/nailpolish
	name = "nail polish"
	desc = "to paint your nails with. Or someone else's!"
	icon = 'icons/obj/nailpolish_vr.dmi'
	icon_state = "nailpolish"
	w_class = ITEMSIZE_SMALL
	var/colour = "#FFFFFF"
	var/open = FALSE
	drop_sound = SFX_ITEMS_DROP_GLASS
	pickup_sound = SFX_ITEMS_PICKUP_GLASS

// ALLOW(init/INSTANCE_STATE): its description and sprite show the colour it was given
/obj/item/nailpolish/Initialize(mapload)
	. = ..()
	desc = "<font color='[colour]'>Nail polish,</font> " + initial(desc)

SETTER(/obj/item/nailpolish, colour)
/obj/item/nailpolish/proc/set_colour(_colour)
	if(TRACKED_UNCHANGED(colour, _colour))
		return FALSE
	colour = _colour
	desc = "<font color='[colour]'>Nail polish,</font> " + initial(desc)
	tracked_changed(src, nameof(colour))
	return TRUE

TRACKED(/obj/item/nailpolish, open)

CAPABILITIES(/obj/item/nailpolish)
	op("self", in_hand(), then(PROC_REF(interaction_self)))
	op("nail_paint", at_target(/mob/living), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), label("Paint nails"),
		needs(req(PROC_REF(polish_is_open), silent = TRUE)), starts(PROC_REF(paint_started)), wait(PROC_REF(paint_time)), on_interrupt(PROC_REF(paint_failed)), then(PROC_REF(paint_done)))

/// Old attack_self.
/obj/item/nailpolish/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	set_open(!open)
	to_chat(user, span_notice("You [open ? "open" : "close"] \the [src]."))
	return TRUE

/// The look: the cap state, and the colour and top layers beneath it.
/obj/item/nailpolish/draw(datum/look/look)
	..()
	var/suffix = open ? "-open" : ""
	look.state("[initial(icon_state)][suffix]")
	look.underlay(look_overlay_image(icon = icon, icon_state = "color[suffix]", color = colour))
	look.underlay(look_overlay_image(icon, "top[suffix]"))

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

MSG_DEF_SELF(nailpolish/missing_limb, "%T% is missing that limb!")
MSG_DEF_SELF(nailpolish/already_polished, "%T% already has nail polish on that limb!")
MSG_DEF_SELF(nailpolish/no_nails, "You can't find any nails on that limb to paint.")

/obj/item/nailpolish/proc/polish_is_open(datum/act/op/A)
	return open

/// The limb aimed at must be there, bare and have nails to paint; it and the polish are fixed now.
/obj/item/nailpolish/proc/paint_started(datum/act/op/A)
	var/mob/living/user = A.actor
	var/mob/living/target = A.target
	var/obj/item/organ/external/body_part = target.get_organ(user.zone_sel.selecting)
	if(!body_part)
		return MSG(nailpolish/missing_limb)
	if(body_part.nail_polish)
		return MSG(nailpolish/already_polished)
	var/datum/nail_polish/polish = body_part.get_polish(colour)
	if(!polish)
		return MSG(nailpolish/no_nails)
	LAZYSET(A.args, "limb", body_part)
	LAZYSET(A.args, "polish", polish)

/// Painting yourself is at once; painting someone else takes two seconds.
/obj/item/nailpolish/proc/paint_time(datum/act/op/A)
	return A.actor == A.target ? 0 : 2 SECONDS

/obj/item/nailpolish/proc/paint_failed(datum/act/op/A)
	to_chat(A.actor, span_notice("Both you and [A.target] must stay still!"))

/obj/item/nailpolish/proc/paint_done(datum/act/op/A)
	var/mob/living/user = A.actor
	var/mob/living/target = A.target
	var/obj/item/organ/external/body_part = A.arg("limb")
	var/datum/nail_polish/polish = A.arg("polish")
	if(QDELETED(body_part) || body_part.nail_polish)
		return
	if(user == target)
		act_message(user, src, MSG_SELF(span_infoplain("You paint your nails with %T%.")), \
			MSG_OTHERS(span_infoplain(span_bold("%U%") + " paints their nails with %T%.")))
	else
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

TRACKED(/obj/item/nailpolish_remover, open)

CAPABILITIES(/obj/item/nailpolish_remover)
	op("self", in_hand(), then(PROC_REF(interaction_self)))
	op("nail_remove", at_target(/mob/living), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), label("Remove nail polish"),
		needs(req(PROC_REF(remover_is_open), silent = TRUE)), starts(PROC_REF(remove_started)), wait(PROC_REF(remove_time)), on_interrupt(PROC_REF(remove_failed)), then(PROC_REF(remove_done)))

/// Old attack_self.
/obj/item/nailpolish_remover/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	set_open(!open)
	to_chat(user, span_notice("You [open ? "open" : "close"] \the [src]."))
	return TRUE

/// The look (the draw sweep: from its template).
/obj/item/nailpolish_remover/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][open ? "-open" : ""]")

MSG_DEF_SELF(nailpolish/remover_missing_limb, "%T% is missing that limb!")
MSG_DEF_SELF(nailpolish/nothing_to_remove, "%T% has no nail polish to remove on that limb!")

/obj/item/nailpolish_remover/proc/remover_is_open(datum/act/op/A)
	return open

/// The limb aimed at must be there and carry polish; it is fixed now.
/obj/item/nailpolish_remover/proc/remove_started(datum/act/op/A)
	var/mob/living/user = A.actor
	var/mob/living/target = A.target
	var/obj/item/organ/external/body_part = target.get_organ(user.zone_sel.selecting)
	if(!body_part)
		return MSG(nailpolish/remover_missing_limb)
	if(!body_part.nail_polish)
		return MSG(nailpolish/nothing_to_remove)
	LAZYSET(A.args, "limb", body_part)

/// Removing your own is at once; someone else's takes two seconds.
/obj/item/nailpolish_remover/proc/remove_time(datum/act/op/A)
	return A.actor == A.target ? 0 : 2 SECONDS

/obj/item/nailpolish_remover/proc/remove_failed(datum/act/op/A)
	to_chat(A.actor, span_notice("Both you and [A.target] must stay still!"))

/obj/item/nailpolish_remover/proc/remove_done(datum/act/op/A)
	var/mob/living/user = A.actor
	var/mob/living/target = A.target
	var/obj/item/organ/external/body_part = A.arg("limb")
	if(QDELETED(body_part))
		return
	if(user == target)
		act_message(user, src, MSG_SELF(span_infoplain("You remove your nail polish with %T%.")), \
			MSG_OTHERS(span_infoplain(span_bold("%U%") + " removes their nail polish with %T%.")))
	else
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

