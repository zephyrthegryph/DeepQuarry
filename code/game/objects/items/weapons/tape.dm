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

MSG_DEF_SELF(tape/no_grip, span_danger("You need to have a firm grip on %T% before you can use %I%!"))
MSG_DEF_SELF(tape/no_head, span_warning("%T% doesn't have a head."))
MSG_DEF_SELF(tape/no_eyes, span_warning("%T% doesn't have any eyes."))
MSG_DEF_SELF(tape/eyes_covered, span_warning("%T% is already wearing something on their eyes."))
MSG_DEF_SELF(tape/no_mouth, span_warning("%T% doesn't have a mouth."))
MSG_DEF_SELF(tape/mask_worn, span_warning("%T% is already wearing a mask."))
MSG_DEF(tape/eyes_begin, null, span_danger("%U% begins taping over %T%'s eyes!"))
MSG_DEF(tape/mouth_begin, null, span_danger("%U% begins taping up %T%'s mouth!"))

CAPABILITIES(/obj/item/tape_roll)
	op("tape_eyes", at_target(/mob/living/carbon/human), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), stance(I_DISARM, I_GRAB, I_HURT), label("Tape over the eyes"),
		when(req_bool(PROC_REF(aimed_at_eyes))),
		needs(req_adjacent(), req_bool(PROC_REF(firm_grip), because = MSG(tape/no_grip)), req_bool(PROC_REF(has_head), because = MSG(tape/no_head)), req_bool(PROC_REF(has_eyes), because = MSG(tape/no_eyes)),
			req_bool(PROC_REF(eyes_free), because = MSG(tape/eyes_covered)), req_bool(PROC_REF(face_free), because = PROC_REF(face_text))),
		begins(MSG(tape/eyes_begin)), wait(3 SECONDS), then(PROC_REF(tape_eyes_done)))
	op("tape_mouth", at_target(/mob/living/carbon/human), priority(OP_PRIORITY_PART + 1), answers(INTENT_USE, INTENT_ATTACK), stance(I_DISARM, I_GRAB, I_HURT), label("Tape up the mouth"),
		when(req_bool(PROC_REF(aimed_at_mouth))),
		needs(req_adjacent(), req_bool(PROC_REF(firm_grip), because = MSG(tape/no_grip)), req_bool(PROC_REF(has_head), because = MSG(tape/no_head)), req_bool(PROC_REF(has_mouth), because = MSG(tape/no_mouth)),
			req_bool(PROC_REF(mask_free), because = MSG(tape/mask_worn)), req_bool(PROC_REF(face_free), because = PROC_REF(face_text))),
		begins(MSG(tape/mouth_begin)), wait(3 SECONDS), then(PROC_REF(tape_mouth_done)))

/obj/item/tape_roll/proc/aimed_at_eyes(datum/act/op/A)
	return read_once(A.actor.zone_sel?.selecting) == O_EYES

/obj/item/tape_roll/proc/aimed_at_mouth(datum/act/op/A)
	var/zone = read_once(A.actor.zone_sel?.selecting)
	return zone == O_MOUTH || zone == BP_HEAD

/obj/item/tape_roll/proc/firm_grip(datum/act/op/A)
	return read_once(can_place(A.target, A.actor))

/obj/item/tape_roll/proc/has_head(datum/act/op/A)
	var/mob/living/carbon/human/H = A.target
	return !!read_once(H.organs_by_name[BP_HEAD])

/obj/item/tape_roll/proc/has_eyes(datum/act/op/A)
	var/mob/living/carbon/human/H = A.target
	return !!read_once(H.has_eyes())

/obj/item/tape_roll/proc/has_mouth(datum/act/op/A)
	var/mob/living/carbon/human/H = A.target
	return !!read_once(H.check_has_mouth())

/obj/item/tape_roll/proc/eyes_free(datum/act/op/A)
	var/mob/living/carbon/human/H = A.target
	return !H.get_equipped_item(SLOT_ID_EYES)

/obj/item/tape_roll/proc/mask_free(datum/act/op/A)
	var/mob/living/carbon/human/H = A.target
	return !H.get_equipped_item(SLOT_ID_MASK)

/// A helmet or hat that covers the face keeps the tape off.
/obj/item/tape_roll/proc/face_free(datum/act/op/A)
	var/mob/living/carbon/human/H = A.target
	var/obj/item/worn = H.get_equipped_item(SLOT_ID_HEAD)
	return !worn || !(read_once(worn.body_parts_covered) & FACE)

/obj/item/tape_roll/proc/face_text(datum/act/op/A)
	var/mob/living/carbon/human/H = A.target
	return span_warning("Remove their [H.get_equipped_item(SLOT_ID_HEAD)] first.")

/obj/item/tape_roll/proc/tape_eyes_done(datum/act/op/A)
	var/mob/living/carbon/human/H = A.target
	var/mob/living/user = A.actor
	if(!can_place(H, user)) // the grip is checked again where the work ends
		return OP_FAILED
	act_message(user, H, others = span_danger("%U% has taped up %T%'s eyes!"))
	H.equip_to_slot_or_del(new /obj/item/clothing/glasses/sunglasses/blindfold/tape(H), SLOT_ID_EYES, ignore_obstructions = FALSE)
	H.update_inv_glasses()
	play_sfx(src, SFX_EFFECTS_TAPE)
	return OP_OK

/obj/item/tape_roll/proc/tape_mouth_done(datum/act/op/A)
	var/mob/living/carbon/human/H = A.target
	var/mob/living/user = A.actor
	if(!can_place(H, user)) // the grip is checked again where the work ends
		return OP_FAILED
	act_message(user, H, others = span_danger("%U% has taped up %T%'s mouth!"))
	H.equip_to_slot_or_del(new /obj/item/clothing/mask/muzzle/tape(H), SLOT_ID_MASK, ignore_obstructions = FALSE)
	H.update_inv_wear_mask()
	play_sfx(src, SFX_EFFECTS_TAPE)
	return OP_OK

/obj/item/tape_roll/attack(mob/living/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(stance == I_HELP)
			return ITEM_INTERACT_FAILURE
		if(!can_place(H, user))
			to_chat(user, span_danger("You need to have a firm grip on [H] before you can use \the [src]!"))
			return ITEM_INTERACT_FAILURE
		else
			if(user.zone_sel.selecting == BP_R_HAND || user.zone_sel.selecting == BP_L_HAND)
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
