// Micro Holders - Extends /obj/item/holder

/obj/item/holder/micro
	name = "micro"
	desc = "Another crewmember, small enough to fit in your hand."
	icon_state = "micro"
	icon_override = 'icons/inventory/head/mob.dmi'
	slot_flags = SLOT_FEET | SLOT_HEAD | SLOT_ID | SLOT_HOLSTER | SLOT_BACK
	w_class = ITEMSIZE_SMALL
	item_icons = null // No in-hand sprites (for now, anyway, we could totally add some)
	pixel_y = 0		  // Override value from parent.

/obj/item/holder/micro/Initialize(mapload, mob/held)
	. = ..()
	var/mob/living/carbon/human/H = held_mob
	if(istype(H) && H.species.is_micro_carry(H))
		item_icons = list(
					slot_l_hand_str = 'icons/mob/items/lefthand_toys.dmi',
					slot_r_hand_str = 'icons/mob/items/righthand_toys.dmi',
					slot_back_str = 'icons/mob/toy_worn.dmi',
					slot_head_str = 'icons/mob/toy_worn.dmi')

		// Leaving the following two set makes the sprite not visible
		icon_override = null
		sprite_sheets = null
		icon_state = "teshariplushie_white"
		item_state = "teshariplushie_white"

/obj/item/holder/micro/make_worn_icon(body_type,slot_name,inhands,default_icon,default_layer,icon/clip_mask = null)
	var/mob/living/carbon/human/H = held_mob
	// Only proceed if dealing with a tesh (or something shaped like a tesh)
	if(istype(H) && H.species.is_micro_carry(H))
		var/colortemp = color //save original color var to a temp var
		//convert numerical RGB to Hex #000000 format - is this necessary?
		//then 'inject' changed color (from skin color) into original proc call
		color = addtext("#", num2hex(H.r_skin, 2), num2hex(H.g_skin, 2), num2hex(H.b_skin, 2))
		. = ..()
		color = colortemp //reset color var to it's old value after original proc call before proceeding - otherwise we change hand-slot icon color too!
	else
		. = ..()

/obj/item/holder/examine(mob/user)
	SHOULD_CALL_PARENT(FALSE)
	. = list()
	FOR_REAL_CONTENTS(var/mob/living/M, src)
		. += M.examine(user)

CAPABILITIES(/obj/item/holder)
	drag_onto(PROC_REF(drop_input))
	op("holder_pick_up", hand(), priority(OP_PRIORITY_DEFAULT), label("Pick up"), then(PROC_REF(holder_pick_up)))
	op("holder_use", item(/obj/item), label("Use on"), passes(), then(PROC_REF(holder_item_used)))
	param(nameof(held_at_make), pos = 1, apply = PROC_REF(take_held), keep = FALSE)

/// The native drop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm). Dropped onto its dragger, the held mob
/// moves into their hands; the native drop goes on either way.
/obj/item/holder/proc/drop_input(datum/act/input/A)
	holder_inventory_drop(A.over, A.actor)
	return INPUT_FALLTHROUGH

/obj/item/holder/proc/holder_inventory_drop(mob/M, mob/user)
	if(M != user) return
	if(user == src) return
	if(!Adjacent(user)) return
	if(isAI(M)) return
	for(var/mob/living/carbon/human/O in contents)
		O.show_inventory_panel(user, state = GLOB.tgui_deep_inventory_state)

CAPABILITIES(/obj/item/holder/micro)
	op("micro_holder_pet_self", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Pet"), then(PROC_REF(micro_holder_pet_self)))

/// Old attack_self: reworked so it works w/ nonhumans.
/obj/item/holder/micro/proc/micro_holder_pet_self(datum/act/op/A)
	var/mob/living/carbon/user = A.actor
	user.setClickCooldown(user.get_attack_speed())
	for(var/L in contents)
		if(ishuman(L))
			var/mob/living/carbon/human/H = L
			H.help_shake_act(user)
		if(isanimal(L))
			var/mob/living/simple_mob/S = L
			act_message(user, S, others = span_notice("%U% [S.response_help] %T%."))
	return OP_OK

//Egg features. (The egged-mob check lives in /obj/item/holder/proc/holder_pick_up(), holder.dm.)
/obj/item/holder/container_resist(mob/living/held)
	if(!istype(src.loc, /obj/item/storage/vore_egg))
		..()
	else
		var/obj/item/storage/vore_egg/E = src.loc
		if(isbelly(E.loc))
			var/obj/belly/B = E.loc
			B.relay_resist(held, E)
			return
		E.hatch(held)
		return
