/obj/item/handcuffs
	name = "handcuffs"
	desc = "Use this to keep prisoners in line."
	gender = PLURAL
	icon = 'icons/obj/items.dmi'
	icon_state = "handcuff"
	slot_flags = SLOT_BELT
	throwforce = 5
	w_class = ITEMSIZE_SMALL
	throw_speed = 2
	throw_range = 5
	MATERIAL_BULK(MAT_STEEL, 500)
	drop_sound = SFX_ITEMS_DROP_ACCESSORY
	pickup_sound = SFX_ITEMS_PICKUP_ACCESSORY
	var/elastic
	var/dispenser = 0
	var/breakouttime = 1200 //Deciseconds = 120s = 2 minutes
	var/cuff_sound = SFX_WEAPONS_HANDCUFFS
	var/cuff_type = "handcuffs"
	var/use_time = 30
	sprite_sheets = list(SPECIES_TESHARI = 'icons/mob/species/teshari/handcuffs.dmi')

/obj/item/handcuffs/get_worn_icon_state(slot_name)
	if(slot_name == slot_handcuffed_str)
		return "handcuff1" //Simple

	return ..()

/obj/item/handcuffs/attack(mob/living/carbon/C, mob/living/user, target_zone, attack_modifier)
	if(!istype(C))
		return ITEM_INTERACT_FAILURE

	if(!user.IsAdvancedToolUser())
		return ITEM_INTERACT_FAILURE

	if (CLUMSY_FAIL_CHANCE(user))
		to_chat(user, span_warning("Uh ... how do those things work?!"))
		attempt_to_cuff(user, user)
		return ITEM_INTERACT_SUCCESS

	if(!C.get_equipped_item(SLOT_ID_HANDCUFFED))
		if (C == user)
			attempt_to_cuff(user, user)
			return ITEM_INTERACT_SUCCESS

		//check for an aggressive grab (or robutts)
		if(can_place(C, user))
			attempt_to_cuff(C, user)
			return ITEM_INTERACT_SUCCESS
		else
			to_chat(user, span_danger("You need to have a firm grip on [C] before you can put \the [src] on!"))
			return ITEM_INTERACT_FAILURE

/obj/item/handcuffs/proc/can_place(mob/target, mob/user)
	if(user == target)
		return 1
	if(isrobot(user))
		if(user.Adjacent(target))
			return 1
	else
		for(var/obj/item/grab/G in target?.grabbed_by_list())
			if(G.loc == user && G.state >= GRAB_AGGRESSIVE)
				return 1
	return 0

/// Putting them on takes `use_time`; the cuffs have to stay in hand and the wearer-to-be in the grip.
CAPABILITIES(/obj/item/handcuffs)
	op("cuff", ai(), takes("victim"), wait(PROC_REF(cuff_time), keeps = HELD | TARGET_PRESENT | ALIVE | STAY), then(PROC_REF(attempt_to_cuff_timed_done)))

/obj/item/handcuffs/proc/cuff_time(datum/act/op/A)
	return use_time

/obj/item/handcuffs/proc/attempt_to_cuff(mob/living/carbon/victim, mob/user)
	playsound(src, cuff_sound, 30, 1, -2)

	var/mob/living/carbon/human/human_victim = victim
	if(!istype(human_victim))
		return 0

	if (!human_victim.body_slot_usable(SLOT_ID_HANDCUFFED))
		to_chat(user, span_danger("\The [victim] needs at least two wrists before you can cuff them together!"))
		return 0

	if(istype(human_victim.get_equipped_item(SLOT_ID_GLOVES),/obj/item/clothing/gloves/gauntlets/rig) && !elastic) // Can't cuff someone who's in a deployed hardsuit.
		to_chat(user, span_danger("\The [src] won't fit around \the [human_victim.get_equipped_item(SLOT_ID_GLOVES)]!"))
		return 0

	act_message(user, victim, others = span_danger("%U% is attempting to put [cuff_type] on %T%!"))

	perform_op(user, src, "cuff", src, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("victim" = victim))
	return TRUE

/obj/item/handcuffs/proc/attempt_to_cuff_timed_done(datum/act/op/A)
	var/mob/living/carbon/victim = A.arg("victim")
	var/mob/user = A.actor
	if(QDELETED(victim) || !can_place(victim, user)) //victim may have resisted out of the grab in the meantime
		return OP_FAILED

	add_attack_logs(user,victim,"Handcuffed (attempt)")
	feedback_add_details("handcuffs","victim")

	user.setClickCooldown(user.get_attack_speed(src))
	user.do_attack_animation(victim)

	act_message(user, victim, others = span_danger("%U% has put [cuff_type] on %T%!"))

	// Apply cuffs.
	var/obj/item/handcuffs/cuffs = src
	if(dispenser)
		cuffs = new(get_turf(user))
	else
		user.drop_from_inventory(cuffs)
	victim.equip_to_slot(cuffs, SLOT_ID_HANDCUFFED)
	victim.drop_r_hand()
	victim.drop_l_hand()
	victim.stop_pulling()
	return OP_OK

/obj/item/handcuffs/equipped(mob/living/user,slot)
	. = ..()
	if(slot == SLOT_ID_HANDCUFFED)
		user.drop_r_hand()
		user.drop_l_hand()
		user.stop_pulling()

/mob/living/carbon/human/RestrainedClickOn(atom/A, stance = I_HURT)
	if (A != src) return ..()
	if (!COOLDOWN_FINISHED(src, chew_cooldown)) return

	var/mob/living/carbon/human/H = A
	if (!H.get_equipped_item(SLOT_ID_HANDCUFFED)) return
	if (stance != I_HURT) return
	if (H.zone_sel.selecting != O_MOUTH) return
	if (H.get_equipped_item(SLOT_ID_MASK)) return
	if (istype(H.get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/straight_jacket)) return
	if (istype(H.get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/shibari))
		var/obj/item/clothing/suit/shibari/s = get_equipped_item(SLOT_ID_SUIT)
		if(s.rope_mode == "Arms" || s.rope_mode == "Arms and Legs")
			return

	var/obj/item/organ/external/O = H.organs_by_name[(H.hand ? BP_L_HAND : BP_R_HAND)]
	if (!O) return

	var/s = span_warning("[H.name] chews on [H.p_their()] [O.name]!")
	act_message(H, null, MSG_SELF(span_warning("You chew on your [O.name]!")), MSG_OTHERS(s))
	add_attack_logs(H,H,"chewed own [O.name]")

	H.injure(INJURY_CUT, 3, O, src)

	COOLDOWN_START(src, chew_cooldown, 2.6 SECONDS)

/obj/item/handcuffs/fuzzy
	name = "fuzzy cuffs"
	icon_state = "fuzzycuff"
	breakouttime = 100 //VOREstation edit
	desc = "Use this to keep... 'prisoners' in line."

/obj/item/handcuffs/cable
	name = "cable restraints"
	desc = "Looks like some cables tied together. Could be used to tie something up."
	icon_state = "cuff_white"
	breakouttime = 300 //Deciseconds = 30s
	cuff_sound = SFX_WEAPONS_CABLECUFF
	cuff_type = "cable restraints"
	elastic = 1

/obj/item/handcuffs/cable/red
	color = "#DD0000"

/obj/item/handcuffs/cable/yellow
	color = "#DDDD00"

/obj/item/handcuffs/cable/blue
	color = "#0000DD"

/obj/item/handcuffs/cable/green
	color = "#00DD00"

/obj/item/handcuffs/cable/pink
	color = "#DD00DD"

/obj/item/handcuffs/cable/orange
	color = "#DD8800"

/obj/item/handcuffs/cable/cyan
	color = "#00DDDD"

/obj/item/handcuffs/cable/white
	color = "#FFFFFF"

/obj/item/handcuffs/cyborg
	dispenser = 1

/obj/item/handcuffs/cable/tape
	name = "tape restraints"
	desc = "DIY!"
	icon_state = "tape_cross"
	item_state = null
	icon = 'icons/obj/bureaucracy.dmi'
	breakouttime = 200
	cuff_type = "duct tape"

/obj/item/handcuffs/cable/tape/cyborg
	dispenser = TRUE

//Legcuffs. Not /really/ handcuffs, but its close enough.
/obj/item/handcuffs/legcuffs
	name = "legcuffs"
	desc = "Use this to keep prisoners in line."
	gender = PLURAL
	icon = 'icons/obj/items.dmi'
	icon_state = "legcuff"
	breakouttime = 300	//Deciseconds = 30s = 0.5 minute
	cuff_type = "legcuffs"
	sprite_sheets = list(SPECIES_TESHARI = 'icons/mob/species/teshari/handcuffs.dmi')
	elastic = 0
	cuff_sound = SFX_WEAPONS_HANDCUFFS //This shold work for now.

/obj/item/handcuffs/legcuffs/get_worn_icon_state(slot_name)
	if(slot_name == slot_legcuffed_str)
		return "legcuff1"

	return ..()

/obj/item/handcuffs/legcuffs/attack(mob/living/carbon/C, mob/living/user, target_zone, attack_modifier)
	if(!istype(C))
		return ITEM_INTERACT_FAILURE

	if(!user.IsAdvancedToolUser())
		return ITEM_INTERACT_FAILURE

	if (CLUMSY_FAIL_CHANCE(user))
		to_chat(user, span_warning("Uh ... how do those things work?!"))
		place_legcuffs(user, user)
		return ITEM_INTERACT_SUCCESS

	if(!C.get_equipped_item(SLOT_ID_LEGCUFFED))
		if (C == user)
			place_legcuffs(user, user)
			return ITEM_INTERACT_SUCCESS

		//check for an aggressive grab (or robutts)
		if(can_place(C, user))
			place_legcuffs(C, user)
			return ITEM_INTERACT_SUCCESS
		else
			to_chat(user, span_danger("You need to have a firm grip on [C] before you can put \the [src] on!"))
			return ITEM_INTERACT_FAILURE

/obj/item/handcuffs/legcuffs/proc/place_legcuffs(mob/living/carbon/target, mob/user)
	playsound(src, cuff_sound, 30, 1, -2)

	var/mob/living/carbon/human/H = target
	if(!istype(H))
		return 0

	if (!H.body_slot_usable(SLOT_ID_LEGCUFFED))
		to_chat(user, span_danger("\The [H] needs at least two ankles before you can cuff them together!"))
		return 0

	if(istype(H.get_equipped_item(SLOT_ID_SHOES),/obj/item/clothing/shoes/magboots/rig) && !elastic) // Can't cuff someone who's in a deployed hardsuit.
		to_chat(user, span_danger("\The [src] won't fit around \the [H.get_equipped_item(SLOT_ID_SHOES)]!"))
		return 0

	act_message(user, null, others = span_danger("%U% is attempting to put [cuff_type] on \the [H]!"))

	perform_op(user, src, "legcuff", src, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("victim" = target))
	return TRUE

/// Putting them on takes `use_time`; the legcuffs have to stay in hand.
CAPABILITIES(/obj/item/handcuffs/legcuffs)
	op("legcuff", ai(), takes("victim"), wait(PROC_REF(cuff_time), keeps = HELD | TARGET_PRESENT | ALIVE | STAY), then(PROC_REF(place_legcuffs_timed_done)))

/obj/item/handcuffs/legcuffs/proc/place_legcuffs_timed_done(datum/act/op/A)
	var/mob/living/carbon/target = A.arg("victim")
	var/mob/user = A.actor
	var/mob/living/carbon/human/H = target

	if(QDELETED(target) || !can_place(target, user)) //victim may have resisted out of the grab in the meantime
		return OP_FAILED

	add_attack_logs(user,H,"Legcuffed (attempt)")
	feedback_add_details("legcuffs","H")

	user.setClickCooldown(user.get_attack_speed(src))
	user.do_attack_animation(H)

	act_message(user, null, others = span_danger("%U% has put [cuff_type] on \the [H]!"))

	// Apply cuffs.
	var/obj/item/handcuffs/legcuffs/lcuffs = src
	if(dispenser)
		lcuffs = new(get_turf(user))
	else
		user.drop_from_inventory(lcuffs)
	target.equip_to_slot(lcuffs, SLOT_ID_LEGCUFFED)
	if(target.m_intent != I_WALK)
		target.m_intent = I_WALK
		if(target.hud_used && target.hud_used.move_intent)
			target.hud_used.move_intent.icon_state = "walking"
	return OP_OK

/obj/item/handcuffs/legcuffs/equipped(mob/living/user,slot)
	. = ..()
	if(slot == SLOT_ID_LEGCUFFED)
		if(user.m_intent != I_WALK)
			user.m_intent = I_WALK
			if(user.hud_used && user.hud_used.move_intent)
				user.hud_used.move_intent.icon_state = "walking"


/obj/item/handcuffs/legcuffs/bola
	name = "bola"
	desc = "Keeps prey in line."
	elastic = 1
	use_time = 0
	breakouttime = 30
	cuff_sound = SFX_WEAPONS_TOWELWIPE //Is there anything this sound can't do?
	item_flags = DROPDEL

/obj/item/handcuffs/legcuffs/bola/can_place(mob/target, mob/user)
	if(user) //A ranged legcuff, until proper implementation as items it remains a projectile-only thing.
		return 1

/obj/item/handcuffs/legcuffs/bola/dropped(mob/user, equipping, slot)
	if(equipping)
		return ..()
	..()
	visible_message(span_infoplain(span_bold("\The [src]") + " falls apart!"))

/obj/item/handcuffs/legcuffs/bola/place_legcuffs(mob/living/carbon/target, mob/user)
	playsound(src, cuff_sound, 30, 1, -2)

	var/mob/living/carbon/human/H = target
	if(!istype(H))
		src.dropped(user)
		return 0

	if(!H.body_slot_usable(SLOT_ID_LEGCUFFED))
		act_message(H, src, others = span_infoplain(span_bold("%T%") + " slams into %U%, but slides off!"))
		src.dropped(user)
		return 0

	act_message(H, src, others = span_danger("%U% has been snared by %T%!"))

	// Apply cuffs.
	var/obj/item/handcuffs/legcuffs/lcuffs = src
	target.equip_to_slot(lcuffs, SLOT_ID_LEGCUFFED)
	if(target.m_intent != I_WALK)
		target.m_intent = I_WALK
		if(target.hud_used && target.hud_used.move_intent)
			target.hud_used.move_intent.icon_state = "walking"
	return 1

/obj/item/handcuffs/cable/plantfiber
	name = "rope bindings"
	desc = "A length of rope fashioned to hold someone's hands together."
	color = "#7e6442"


/obj/item/handcuffs/legcuffs/fuzzy
	name = "fuzzy legcuffs"
	desc = "Use this to keep... 'prisoners' in line."
	icon = 'icons/obj/items.dmi'
	icon_state = "fuzzylegcuff"
