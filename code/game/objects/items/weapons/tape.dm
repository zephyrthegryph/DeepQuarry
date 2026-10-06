/obj/item/tape_roll
	name = "tape roll"
	desc = "A roll of sticky tape. Possibly for taping ducks... or was that ducts?"
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "taperoll"
	w_class = ITEMSIZE_TINY
	drop_sound = SFX_ITEMS_DROP_CARDBOARDBOX
	pickup_sound = SFX_ITEMS_PICKUP_CARDBOARDBOX

	toolspeed = 2 //It is now used in surgery as a not awful, but probably dangerous option, due to speed.

/obj/item/tape_roll/proc/can_place(mob/living/carbon/human/H, mob/user)
	if(isrobot(user) || user == H)
		return TRUE

	for (var/obj/item/grab/G in H?.grabbed_by_list())
		if (G.loc == user && G.state >= GRAB_AGGRESSIVE)
			return TRUE

	return FALSE

/obj/item/tape_roll/proc/tape_eyes_done(mob/living/carbon/human/H, mob/living/user)
	if(!can_place(H, user))
		return
	if(!H.organs_by_name[BP_HEAD] || !H.has_eyes() || H.get_equipped_item(SLOT_ID_EYES) || (H.get_equipped_item(SLOT_ID_HEAD) && (H.get_equipped_item(SLOT_ID_HEAD).body_parts_covered & FACE)))
		return
	act_message(user, H, others = span_danger("%U% has taped up %T%'s eyes!"))
	H.equip_to_slot_or_del(new /obj/item/clothing/glasses/sunglasses/blindfold/tape(H), SLOT_ID_EYES, ignore_obstructions = FALSE)
	H.update_inv_glasses()
	play_sfx(src, SFX_EFFECTS_TAPE)

/obj/item/tape_roll/proc/tape_mouth_done(mob/living/carbon/human/H, mob/living/user)
	if(!can_place(H, user))
		return
	if(!H.organs_by_name[BP_HEAD] || !H.check_has_mouth() || (H.get_equipped_item(SLOT_ID_HEAD) && (H.get_equipped_item(SLOT_ID_HEAD).body_parts_covered & FACE)))
		return
	act_message(user, H, others = span_danger("%U% has taped up %T%'s mouth!"))
	H.equip_to_slot_or_del(new /obj/item/clothing/mask/muzzle/tape(H), SLOT_ID_MASK, ignore_obstructions = FALSE)
	H.update_inv_wear_mask()
	play_sfx(src, SFX_EFFECTS_TAPE)

/obj/item/tape_roll/attack(mob/living/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(stance == I_HELP)
			return ITEM_INTERACT_FAILURE
		if(!can_place(H, user))
			to_chat(user, span_danger("You need to have a firm grip on [H] before you can use \the [src]!"))
			return ITEM_INTERACT_FAILURE
		else
			if(user.zone_sel.selecting == O_EYES)

				if(!H.organs_by_name[BP_HEAD])
					to_chat(user, span_warning("\The [H] doesn't have a head."))
					return ITEM_INTERACT_FAILURE
				if(!H.has_eyes())
					to_chat(user, span_warning("\The [H] doesn't have any eyes."))
					return ITEM_INTERACT_FAILURE
				if(H.get_equipped_item(SLOT_ID_EYES))
					to_chat(user, span_warning("\The [H] is already wearing something on their eyes."))
					return ITEM_INTERACT_FAILURE
				if(H.get_equipped_item(SLOT_ID_HEAD) && (H.get_equipped_item(SLOT_ID_HEAD).body_parts_covered & FACE))
					to_chat(user, span_warning("Remove their [H.get_equipped_item(SLOT_ID_HEAD)] first."))
					return ITEM_INTERACT_FAILURE
				act_message(user, null, others = span_danger("%U% begins taping over \the [H]'s eyes!"))

				om_task_timed(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(tape_eyes_done), done_args = list(H, user))

			else if(user.zone_sel.selecting == O_MOUTH || user.zone_sel.selecting == BP_HEAD)
				if(!H.organs_by_name[BP_HEAD])
					to_chat(user, span_warning("\The [H] doesn't have a head."))
					return ITEM_INTERACT_FAILURE
				if(!H.check_has_mouth())
					to_chat(user, span_warning("\The [H] doesn't have a mouth."))
					return ITEM_INTERACT_FAILURE
				if(H.get_equipped_item(SLOT_ID_MASK))
					to_chat(user, span_warning("\The [H] is already wearing a mask."))
					return ITEM_INTERACT_FAILURE
				if(H.get_equipped_item(SLOT_ID_HEAD) && (H.get_equipped_item(SLOT_ID_HEAD).body_parts_covered & FACE))
					to_chat(user, span_warning("Remove their [H.get_equipped_item(SLOT_ID_HEAD)] first."))
					return ITEM_INTERACT_FAILURE
				act_message(user, null, others = span_danger("%U% begins taping up \the [H]'s mouth!"))

				om_task_timed(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(tape_mouth_done), done_args = list(H, user))

			else if(user.zone_sel.selecting == BP_R_HAND || user.zone_sel.selecting == BP_L_HAND)
				if(!can_place(H, user))
					return ITEM_INTERACT_FAILURE

				var/obj/item/handcuffs/cable/tape/T = new(user)
				play_sfx(src, SFX_EFFECTS_TAPE)

				if(!T.attempt_to_cuff(H, user))
					consume(T, user)
			else
				return ..()
			return ITEM_INTERACT_SUCCESS

/obj/item/tape_roll/proc/stick(obj/item/W, mob/user)
	if(!istype(W, /obj/item/paper) || istype(W, /obj/item/paper/sticky) || !user.unEquip(W))
		return
	user.drop_from_inventory(W)
	var/obj/item/ducttape/tape = new(get_turf(src))
	tape.attach(W)
	user.put_in_hands(tape)
	play_sfx(src, SFX_EFFECTS_TAPE)

/obj/item/ducttape
	name = "tape"
	desc = "A piece of sticky tape."
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "tape"
	w_class = ITEMSIZE_TINY
	plane = MOB_PLANE
	anchored = FALSE
	drop_sound = null
	flags = NOBLUDGEON

	var/obj/item/stuck = null

/obj/item/ducttape/examine(mob/user)
	SHOULD_CALL_PARENT(FALSE)
	return stuck.examine(user)

/obj/item/ducttape/proc/attach(obj/item/W)
	own_move(W, src, nameof(src.stuck)) // CONTAINED: the move takes it in
	icon_state = W.icon_state + "_taped"
	name = W.name + " (taped)"
	overlays = W.overlays

/// Old attack_self.
/obj/item/ducttape/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!stuck)
		return TRUE

	to_chat(user, "You remove \the [initial(name)] from [stuck].")

	user.drop_from_inventory(src)
	stuck.forceMove(get_turf(src))
	user.put_in_hands(stuck)
	rel_take(src, nameof(stuck))
	overlays = null
	consume(src, user)
	return TRUE

/// Old attackby.
/obj/item/ducttape/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(!(istype(src, /obj/item/handcuffs/cable/tape) || istype(src, /obj/item/clothing/mask/muzzle/tape)))
		return OP_DECLINE
	else
		user.drop_from_inventory(I)
		I.forceMove(src)
		consume(I, user)
		to_chat(user, span_notice("You place \the [I] back into \the [src]."))
	return OP_PASS

CAPABILITIES(/obj/item/ducttape)
	op("hand", hand(), label("Use"), then(PROC_REF(interaction_hand)))
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// Old attack_hand.
/obj/item/ducttape/proc/interaction_hand(datum/act/op/A)
	set_anchored(FALSE)
	return OP_DECLINE // Pick it up now that it's unanchored.

/obj/item/ducttape/afterattack(A, mob/user, flag, params)

	if(!in_range(user, A) || istype(A, /obj/machinery/door) || !stuck)
		return

	var/turf/target_turf = get_turf(A)
	var/turf/source_turf = get_turf(user)

	var/dir_offset = 0
	if(target_turf != source_turf)
		dir_offset = get_dir(source_turf, target_turf)
		if(!(dir_offset in GLOB.cardinal))
			to_chat(user, "You cannot reach that from here.")		// can only place stuck papers in GLOB.cardinal directions, to
			return											// reduce papers around corners issue.

	user.drop_from_inventory(src)
	play_sfx(src, SFX_EFFECTS_TAPE)
	forceMove(source_turf)
	set_anchored(TRUE)

	if(params)
		var/list/mouse_control = params2list(params)
		if(mouse_control["icon-x"])
			pixel_x = text2num(mouse_control["icon-x"]) - 16
			if(dir_offset & EAST)
				pixel_x += 32
			else if(dir_offset & WEST)
				pixel_x -= 32
		if(mouse_control["icon-y"])
			pixel_y = text2num(mouse_control["icon-y"]) - 16
			if(dir_offset & NORTH)
				pixel_y += 32
			else if(dir_offset & SOUTH)
				pixel_y -= 32

/obj/item/ducttape/ownership()
	. = ..()
	. += owns(nameof(stuck), policy = OWN_CONTAINED)
