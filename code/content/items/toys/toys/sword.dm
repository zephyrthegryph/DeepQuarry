/*
 * Toy swords
 */
/obj/item/toy/sword
	name = "toy sword"
	desc = "A cheap, plastic replica of an energy sword. Realistic sounds! Ages 8 and up."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "esword"
	var/lcolor
	var/rainbow = FALSE
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_melee.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_melee.dmi',
		)
	var/active = 0
	w_class = ITEMSIZE_SMALL

CAPABILITIES(/obj/item/toy/sword)
	configure(item_combat(attack_verbs = list("attacked", "struck", "hit")))
	configure(item_sounds(drop = SFX_ITEMS_DROP_GUN))
	op("toggle", in_hand(), then(PROC_REF(interaction_self)))
	op("item", item(/obj/item), then(PROC_REF(interaction_item)))
	// the old click_alt: recolour the blade after a yes
	op("recolor", hand(), ungated(), gesture(GESTURE_ALT), label("Recolor"),
		asks(/datum/prompt/yes_no, fields = list("title" = "Confirm Recolor", "question" = "Are you sure you want to recolor your blade?", "timeout" = 0), step = "sure"),
		asks(/datum/prompt/color/blade_recolor, fields = list("title" = "Choose Energy Color", "default" = "lcolor"), step = "colour", when = PROC_REF(recolor_confirmed)),
		then(PROC_REF(blade_recolored)))

/// Old attack_self: extend or retract the plastic blade.
/obj/item/toy/sword/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	set_active(!active)
	if(active)
		to_chat(user, span_notice("You extend the plastic blade with a quick flick of your wrist."))
		play_sfx(src, SFX_WEAPONS_SABERON)
		set_w_class(ITEMSIZE_LARGE)
	else
		to_chat(user, span_notice("You push the plastic blade back down into the handle."))
		play_sfx(src, SFX_WEAPONS_SABEROFF)
		set_w_class(ITEMSIZE_SMALL)
	add_fingerprint(user)
	return OP_OK

/// The look: the plastic blade over the hilt, in the blade's colour.
/obj/item/toy/sword/draw(datum/look/look)
	..()
	var/base = look.state_so_far(src)
	look.overlay(look_appearance(icon, "[base]_blade", color = lcolor), active)
	look.held_state(active ? "[base]_blade" : base)

/// The recolour was confirmed: the colour picker is next.
/obj/item/toy/sword/proc/recolor_confirmed(datum/act/op/A)
	var/datum/prompt/R = A.step_answers?["sure"]
	return !!R?.value

/// Old click_alt: the blade takes the picked colour.
/obj/item/toy/sword/proc/blade_recolored(datum/act/op/A)
	var/datum/prompt/R = A.step_answers?["colour"]
	if(!R)
		return OP_OK
	if(R.value)
		set_lcolor(sanitize_hexcolor(R.value))
	return OP_OK

/obj/item/toy/sword/examine(mob/user)
	. = ..()
	. += span_notice("Alt-click to recolor it.")

/// Old attackby: a multitool switches the rainbow blade while it is retracted (the click goes on).
/obj/item/toy/sword/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(W.has_tool_quality(TOOL_MULTITOOL) && !active)
		if(!rainbow)
			rainbow = TRUE
		else
			rainbow = FALSE
		to_chat(user, span_notice("You manipulate the color controller in [src]."))
	return OP_PASS
