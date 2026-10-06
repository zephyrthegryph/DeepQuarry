/mob/living/carbon/human
	var/datum/unarmed_attack/default_attack

/mob/living/carbon/human/proc/get_unarmed_attack(mob/living/carbon/human/target, hit_zone)
	if(nif && nif.flag_check(NIF_C_HARDCLAWS,NIF_FLAGS_COMBAT))
		return GLOB.unarmed_hardclaws
	if(src.default_attack && src.default_attack.is_usable(src, target, hit_zone))
		if(has_trait(src, TRAIT_NONLETHAL_BLOWS))
			var/datum/unarmed_attack/soft_type = src.default_attack.get_sparring_variant()
			if(soft_type)
				return soft_type
		return src.default_attack
	if(get_equipped_item(SLOT_ID_GLOVES))
		var/obj/item/clothing/gloves/G = get_equipped_item(SLOT_ID_GLOVES)
		if(istype(G) && G.special_attack && G.special_attack.is_usable(src, target, hit_zone))
			if(has_trait(src, TRAIT_NONLETHAL_BLOWS))
				var/datum/unarmed_attack/soft_type = G.special_attack.get_sparring_variant()
				if(soft_type)
					return soft_type
			return G.special_attack
	if(src.default_attack && src.default_attack.is_usable(src, target, hit_zone))
		if(has_trait(src, TRAIT_NONLETHAL_BLOWS))
			var/datum/unarmed_attack/soft_type = src.default_attack.get_sparring_variant()
			if(soft_type)
				return soft_type
		return src.default_attack
	for(var/datum/unarmed_attack/u_attack in species.unarmed_attacks)
		if(u_attack.is_usable(src, target, hit_zone))
			if(has_trait(src, TRAIT_NONLETHAL_BLOWS))
				var/datum/unarmed_attack/soft_variant = u_attack.get_sparring_variant()
				if(soft_variant)
					return soft_variant
			return u_attack
	return null

/mob/living/carbon/human/unarmed_touch(mob/living/M, stance = I_HELP)
	var/mob/living/carbon/human/H = M

	if(is_incorporeal())
		return

	var/has_hands = TRUE
	if(istype(H))
		var/obj/item/organ/external/temp = H.organs_by_name[BP_R_HAND]
		if(H.hand)
			temp = H.organs_by_name[BP_L_HAND]
		if(!temp || !temp.is_usable())
			has_hands = FALSE
		for(var/thing in get_spreadable_contagions()) //This is intentionally not having a has_hands check. If you are clicking on someone next to them, you're close enough to sneeze/cough on them!
			var/datum/affliction/contagion/D = thing
			if(D.IsSpreadByTouch())
				H.expose_contagion(D)

		for(var/thing in H.get_spreadable_contagions())
			var/datum/affliction/contagion/D = thing
			if(D.IsSpreadByTouch())
				expose_contagion(D)

	M.break_cloak()

	..()

	// Should this all be in Touch()?
	if(istype(H) && has_hands)
		if(H.get_accuracy_penalty() && H != src)	//Should only trigger if they're not aiming well
			var/hit_zone = get_zone_with_miss_chance(H.zone_sel.selecting, src, H.get_accuracy_penalty(), attacker = H)
			if(!hit_zone)
				H.do_attack_animation(src)
				play_sfx(src, SFX_WEAPONS_PUNCHMISS)
				act_message(src, H, others = span_filter_combat("[span_red(span_bold("%T% reaches for %U%, but misses!"))]"))
				return FALSE

		if(H != src && check_shields(0, null, H, H.zone_sel.selecting, H.name))
			H.do_attack_animation(src)
			return FALSE

	if(istype(M,/mob/living/carbon) && has_hands)
		for(var/datum/affliction/contagion/D in M.get_spreadable_contagions())
			if(D.spread_flags & DISEASE_SPREAD_CONTACT)
				expose_contagion(D)

	switch(stance)
		//VARS:  (Placed here for your convenience, because it's confusing)
		// H = THE PERSON DOING THE ATTACK, BUT DEFINED AS A HUMAN. (This is for human specific interactions, such as CPR.)
		// M = THE PERSON DOING THE ATTACK, AGAIN, DEFINED AS A MOB
		// src = THE PERSON BEING ATTACKED
		// has_hands = Local variable. If the attacker has hands or not.
		if(I_HELP)
			attack_hand_help_intent(H, M, has_hands)

		if(I_GRAB)
			attack_hand_grab_intent(H, M, has_hands)

		if(I_HURT)
			attack_hand_harm_intent(H, M, has_hands)

		if(I_DISARM)
			attack_hand_disarm_intent(H, M, has_hands)
	return


/// THE VARIOUS INTENTS.
/// Theses used to be included in the above proc into a MEGA PROC that was over 300 lines long.
/// This condenses them and makes it less of a cluster.

///Help Intent
/mob/living/carbon/human/proc/cpr_done(mob/living/carbon/human/H)
	act_message(H, src, others = span_danger("%U% performs CPR on %T%!"))
	to_chat(H, span_warning("Repeat at least every 7 seconds."))
	perform_cpr(H)

/mob/living/carbon/human/proc/attack_hand_help_intent(mob/living/carbon/human/H, mob/living/M, has_hands)
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(M.restrained()) //If we're restrained, we can't help them. If you want to add snowflake stuff that you can do while restrained, add it here.
		return FALSE
	if(!has_hands) //This is here so if you WANT to do special code for 'if we don't have hands, do stuff' it can be done here!
		return FALSE
	if(istype(M) && attempt_to_scoop(M, H) && !on_fire)
		return FALSE;

	// Abdominal thrusts on a choking patient (aim at the chest).
	if(istype(H) && H != src && !on_fire && H.zone_sel?.selecting == BP_TORSO && stat != DEAD)
		var/datum/affliction/airway_obstruction/choke = body?.find_affliction(/datum/affliction/airway_obstruction)
		if(choke)
			perform_heimlich(H, choke)
			return TRUE

	//todo: make this whole CPR check into it's own individual proc instead of hogging up attack_hand_help_intent
	if((istype(H) && has_trait(src, TRAIT_CRITICAL_CONDITION) || stat == DEAD) && !on_fire && H != src) //Only humans can do CPR.
		if(!H.check_has_mouth())
			to_chat(H, span_danger("You don't have a mouth, you cannot perform CPR!"))
			return FALSE
		if(!check_has_mouth())
			to_chat(H, span_danger("They don't have a mouth, you cannot perform CPR!"))
			return FALSE
		if((H.get_equipped_item(SLOT_ID_HEAD) && (H.get_equipped_item(SLOT_ID_HEAD).body_parts_covered & FACE)) || (H.get_equipped_item(SLOT_ID_MASK) && (H.get_equipped_item(SLOT_ID_MASK).body_parts_covered & FACE)))
			to_chat(H, span_notice("Remove your mask!"))
			return FALSE
		if((get_equipped_item(SLOT_ID_HEAD) && (get_equipped_item(SLOT_ID_HEAD).body_parts_covered & FACE)) || (get_equipped_item(SLOT_ID_MASK) && (get_equipped_item(SLOT_ID_MASK).body_parts_covered & FACE)))
			to_chat(H, span_notice("Remove [src]'s mask!"))
			return FALSE

		if (!COOLDOWN_FINISHED(src, cpr_time))
			return FALSE

		COOLDOWN_START(src, cpr_time, 3 SECONDS)

		act_message(H, src, others = span_danger("%U% is trying to perform CPR on %T%!"))

		task_timed(H, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(cpr_done), done_args = list(H))

	else if(!(M == src && apply_pressure(M, M.zone_sel.selecting)))
		help_shake_act(M)
	return TRUE

//Disarm Intent
/mob/living/carbon/human/proc/attack_hand_disarm_intent(mob/living/carbon/human/H, mob/living/M as mob, has_hands)
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(M.restrained()) //If we're restrained, we can't disarm them. If you want to add snowflake stuff that you can do while restrained, add it here.
		return
	if(!has_hands)  //This is here so if you WANT to do special code for 'if we don't have hands, do stuff' it can be done here!
		return

	M.do_attack_animation(src)

	if(get_equipped_item(SLOT_ID_UNIFORM))
		get_equipped_item(SLOT_ID_UNIFORM).add_fingerprint(M)

	if(M.lying && (M.loc == src.loc)) //If we are on the ground and they're on top of us, we don't have enough space to push them! Also antispam.
		if(!COOLDOWN_FINISHED(src, push_lying_cooldown))
			return
		act_message(M, src, others = span_warning("%U% struggles under %T%!"))
		COOLDOWN_START(src, push_lying_cooldown, 6 SECONDS)
		COOLDOWN_START(src, disarm_cooldown, 3 SECONDS)
		return

	add_attack_logs(H,src,"Disarmed")

	var/obj/item/organ/external/affecting = get_organ(ran_zone(M.zone_sel.selecting))

	var/list/holding = list(get_active_hand() = 40, get_inactive_hand() = 20)

	//See if they have any guns that might go off
	for(var/obj/item/gun/W in holding)
		if(W && prob(holding[W]))
			var/list/turfs = list()
			for(var/turf/T in view())
				turfs += T
			if(turfs.len)
				var/turf/target = pick(turfs)
				act_message(src, null, others = span_danger("%U%'s [W] goes off during the struggle!"))
				return W.afterattack(target,src)

	if(COOLDOWN_TIMELEFT(src, disarm_cooldown)) //The fact that we're repeatedly doing it doesn't lessen the severity of the action! Send it full blast!
		if(M.lying)
			act_message(src, M, others = span_filter_combat("[span_red(span_bold("%T% attempted to sweep %U% to the floor!"))]"))
		else
			act_message(src, M, others = span_filter_combat("[span_red(span_bold("%T% attempted to disarm %U%!"))]"))
		return

	var/randn = rand(1, 100)
	COOLDOWN_START(src, push_lying_cooldown, 6 SECONDS)
	COOLDOWN_START(src, disarm_cooldown, 3 SECONDS)
	// We ARE wearing shoes OR
	// We as a species CAN be slipped when barefoot
	// And also 1 in 4 because rngesus
	if((get_equipped_item(SLOT_ID_SHOES) || !(species.flags & NO_SLIP)) && randn <= 25)
		var/armor_check = armor_against(INJURY_BLUNT, affecting)
		apply_effect(3, WEAKEN, armor_check)
		play_sfx(src, SFX_WEAPONS_THUDSWOOSH)
		if(armor_check < 60)
			drop_both_hands()
			if(M.lying)
				act_message(M, src, others = span_danger("%U% swept %T% down onto the floor!"))
			else
				act_message(M, src, others = span_danger("%U% has pushed %T%!"))
			break_all_grabs(M)
		else
			act_message(M, src, others = span_warning("%U% attempted to push %T%!"))
		return

	if(randn <= 60)
		//See about breaking grips or pulls
		if(break_all_grabs(M))
			play_sfx(src, SFX_WEAPONS_THUDSWOOSH)
			return

		//Actually disarm them
		for(var/obj/item/I in holding)
			if(I)
				drop_from_inventory(I)
				act_message(M, src, others = span_danger("%U% has disarmed %T%!"))
				play_sfx(src, SFX_WEAPONS_THUDSWOOSH)
				return

	play_sfx(src, SFX_WEAPONS_PUNCHMISS)
	if(M.lying)
		act_message(src, M, others = span_filter_combat("[span_red(span_bold("%T% attempted to sweep %U% to the floor!"))]"))
	else
		act_message(src, M, others = span_filter_combat("[span_red(span_bold("%T% attempted to disarm %U%!"))]"))
//Grab Intent
/mob/living/carbon/human/proc/attack_hand_grab_intent(mob/living/carbon/human/H, mob/living/M as mob, has_hands)
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(M.restrained()) //If we're restrained, we can't grab them. If you want to add snowflake stuff that you can do while restrained, add it here.
		return
	if(!has_hands)  //This is here so if you WANT to do special code for 'if we don't have hands, do stuff' it can be done here!
		return
	if(M == src || anchored)
		return
	for(var/obj/item/grab/G in src?.grabbed_by_list())
		if(G?.grab_assailant() == M)
			to_chat(M, span_notice("You already grabbed [src]."))
			return
	if(get_equipped_item(SLOT_ID_UNIFORM))
		get_equipped_item(SLOT_ID_UNIFORM).add_fingerprint(M)

	if(src?.buckled_to())
		to_chat(M, span_notice("You cannot grab [src], [M.p_theyre()] src?.buckled_to() in!"))
		return
	var/obj/item/grab/G = new /obj/item/grab(M, src) //If this is put before the src?.buckled_to() check, the user will be perma-slowed due to a grab existing in nullspace.
	if(!G)	//the grab will delete itself in New if affecting is anchored
		return
	M.put_in_active_hand(G)
	G.synch()
	rel_set(src, nameof(LAssailant), M)

	M.do_attack_animation(src)
	play_sfx(src, SFX_WEAPONS_THUDSWOOSH)
	act_message(M, src, others = span_warning("%U% has grabbed %T% [(M.zone_sel.selecting == BP_L_HAND || M.zone_sel.selecting == BP_R_HAND)? "by [(gender==FEMALE)? "her" : ((gender==MALE)? "his": "their")] hands": "passively"]!"))
//Harm Intent
/mob/living/carbon/human/proc/attack_hand_harm_intent(mob/living/carbon/human/H, mob/living/M as mob, has_hands)
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	//As a note: This intentionally doesn't immediately return if has_hands is false. This is because you can attack with kicks/bites!
	if(has_hands && M.zone_sel.selecting == "mouth" && get_equipped_item(SLOT_ID_MASK) && istype(get_equipped_item(SLOT_ID_MASK), /obj/item/grenade))
		var/obj/item/grenade/G = get_equipped_item(SLOT_ID_MASK)
		if(!G.active)
			act_message(M, src, others = span_danger("%U% pulls the pin from %T%'s [G.name]!"))
			G.activate(M)
			update_inv_wear_mask()
		else
			to_chat(M, span_warning("\The [G] is already primed! Run!"))
		return

	if(has_hands && !istype(H))
		generic_hit(src, H, rand(1,3), "punched")
		return

	var/rand_damage = rand(1, 5)
	var/block = 0
	var/accurate = 0
	var/hit_zone = H.zone_sel.selecting
	var/obj/item/organ/external/affecting = get_organ(hit_zone)

	if(!affecting || affecting.is_stump())
		to_chat(M, span_danger("They are missing that limb!"))
		return FALSE

	// Our own posture (state): out of combat mode we didn't see this coming.
	if(!combat_mode)
		// We didn't see this coming, so we get the full blow
		rand_damage = 5
		accurate = 1
	else
		// We're in a fighting stance, there's a chance we block
		if(canmove && src!=H && prob(20))
			block = 1

	if(LAZYLEN(M?.grabbed_by_list()))
		// Someone got a good grip on them, they won't be able to do much damage
		rand_damage = max(1, rand_damage - 2)

	if(LAZYLEN(src?.grabbed_by_list()) || src?.buckled_to() || !src.canmove || src==H)
		accurate = 1 // certain circumstances make it impossible for us to evade punches
		rand_damage = 5

	// Process evasion and blocking
	var/miss_type = 0
	var/attack_message
	if(!accurate)
		/* ~Hubblenaut
			This place is kind of convoluted and will need some explaining.
			ran_zone() will pick out of 11 zones, thus the chance for hitting
			our target where we want to hit them is circa 9.1%.

			Now since we want to statistically hit our target organ a bit more
			often than other organs, we add a base chance of 20% for hitting it.

			This leaves us with the following chances:

			If aiming for chest:
				27.3% chance you hit your target organ
				70.5% chance you hit a random other organ
					2.2% chance you miss

			If aiming for something else:
				23.2% chance you hit your target organ
				56.8% chance you hit a random other organ
				15.0% chance you miss

			Note: We don't use get_zone_with_miss_chance() here since the chances
					were made for projectiles.
			TODO: proc for melee combat miss chances depending on organ?
		*/

		if(!hit_zone)
			attack_message = "[H] attempted to strike [src], but missed!"
			miss_type = 1

		if(prob(80))
			hit_zone = ran_zone(hit_zone, 70) //70% chance to hit what you're aiming at seems fair?
		if(prob(15) && hit_zone != BP_TORSO) // Missed!
			if(!src.lying)
				attack_message = "[H] attempted to strike [src], but missed!"
			else
				attack_message = "[H] attempted to strike [src], but [M.p_they()] rolled out of the way!"
				src.set_dir(pick(GLOB.cardinal))
			miss_type = 1

	if(!miss_type && block)
		attack_message = "[H] went for [src]'s [affecting.name] but was blocked!"
		miss_type = 2

	// See what attack they use
	var/datum/unarmed_attack/attack = H.get_unarmed_attack(src, hit_zone)
	if(!attack)
		return FALSE

	if(attack.unarmed_override(H, src, hit_zone))
		return FALSE

	H.do_attack_animation(src)
	if(!attack_message)
		attack.show_attack(H, src, hit_zone, rand_damage)
	else
		H.visible_message(span_danger("[attack_message]"))

	if(miss_type && miss_type != 1)
		play_sfx(src, SFX_WEAPONS_THUDSWOOSH, volume = 25)
	else
		playsound(src, miss_type ? attack.miss_sound : attack.attack_sound, 25, 1, -1)

	add_attack_logs(H,src,"Melee attacked with fists (miss/block)")

	if(miss_type)
		return FALSE

	var/real_damage = rand_damage
	var/hit_kind = attack.injury_kind
	real_damage += attack.get_unarmed_damage(H)
	if(H.get_equipped_item(SLOT_ID_GLOVES) && attack.is_punch)
		if(istype(H.get_equipped_item(SLOT_ID_GLOVES), /obj/item/clothing/gloves))
			var/obj/item/clothing/gloves/G = H.get_equipped_item(SLOT_ID_GLOVES)
			real_damage += G.punch_force
			hit_kind = G.punch_injury_kind || hit_kind
		else if(istype(H.get_equipped_item(SLOT_ID_GLOVES), /obj/item/clothing/accessory))
			var/obj/item/clothing/accessory/G = H.get_equipped_item(SLOT_ID_GLOVES)
			real_damage += G.punch_force
			hit_kind = G.punch_injury_kind || hit_kind
		if(has_trait(H, TRAIT_NONLETHAL_BLOWS) && !attack.sharp && !attack.edge && !H.get_feralness())	//SO IT IS DECREED: PULLING PUNCHES WILL PREVENT THE ACTUAL DAMAGE FROM RINGS AND KNUCKLES, BUT NOT THE ADDED PAIN, BUT YOU CAN'T "PULL" A KNIFE
			hit_kind = INJURY_PAIN
			// if you're more resistant to physical blows, pulling punches won't make them more likely to down you. This makes species with both brute and pain modifiers double-dip, but I think that's fine
			var/physical_resistance = incoming_injury_factor(INJURY_CATEGORY_PHYSICAL)
			real_damage *= physical_resistance
			rand_damage *= physical_resistance

	real_damage *= damage_multiplier
	rand_damage *= damage_multiplier
	if(H.has_mutation(HULK))
		real_damage *= 2 // Hulks do twice the damage
		rand_damage *= 2
	real_damage = max(1, real_damage)

	var/armour = armor_against(hit_kind, hit_zone)
	// Apply additional unarmed effects.
	attack.apply_effects(H, src, armour, rand_damage, hit_zone)

	// Finally, apply damage to target (armour applies in injure()).
	injure(hit_kind, real_damage, hit_zone, H, flags = INJURE_ARMORED)

/// INTENTS END


/mob/living/carbon/human/proc/afterattack(atom/target as mob|obj|turf|area, mob/living/user as mob|obj, inrange, params)
	return

/mob/living/carbon/human/attack_generic(mob/user, damage, attack_message)
	if(istype(user,/mob/living))
		var/mob/living/L = user
		if(touch_reaction_flags & SPECIES_TRAIT_THORNS)
			if((src != L))
				L.injure(INJURY_PIERCE, 3, L.hand ? BP_L_HAND : BP_R_HAND, src)
				act_message(L, src, MSG_SELF(span_warning("%T% is covered in sharp bits and it hurt when you touched them!")), \
					MSG_OTHERS(span_warning("%U% is hurt by sharp body parts when touching %T%!")))

	if(!damage)
		return

	add_attack_logs(user,src,"Melee attacked with fists (miss/block)",admin_notify = FALSE) //No admin notice since this is usually fighting simple animals
	act_message(user, src, others = span_danger("%U% has [attack_message] %T%!"))
	user.do_attack_animation(src)

	var/dam_zone = pick(organs_by_name)
	var/obj/item/organ/external/affecting = get_organ(ran_zone(dam_zone))
	receive_generic_attack(user, damage, affecting?.organ_tag, armored = TRUE)
	return TRUE

//Used to attack a joint through grabbing
/mob/living/carbon/human/proc/grab_joint(mob/living/user, def_zone)
	var/has_grab = 0
	for(var/obj/item/grab/G in list(user.get_equipped_item(SLOT_ID_HAND_L), user.get_equipped_item(SLOT_ID_HAND_R)))
		if(G?.grab_target() == src && G.state == GRAB_NECK)
			has_grab = 1
			break

	if(!has_grab)
		return FALSE

	if(!def_zone) def_zone = user.zone_sel.selecting
	var/target_zone = check_zone(def_zone)
	if(!target_zone)
		return FALSE
	var/obj/item/organ/external/organ = get_organ(check_zone(target_zone))
	if(!organ || organ.dislocated > 0 || organ.dislocated == -1) //don't use is_dislocated() here, that checks parent
		return FALSE

	act_message(user, src, others = span_warning("%U% begins to dislocate %T%'s [organ.joint]!"))
	task_timed(user, 10 SECONDS, target = src, receiver = src, on_done = PROC_REF(grab_joint_human_done), done_args = list(organ))
	return TRUE

/mob/living/carbon/human/proc/grab_joint_human_done(obj/item/organ/external/organ)
	organ.dislocate(1)
	act_message(src, null, others = span_danger("%U%'s [organ.joint] [pick("gives way","caves in","crumbles","collapses")]!"))
	return TRUE

//Breaks all grips and pulls that the mob currently has.
/mob/living/carbon/human/proc/break_all_grabs(mob/living/carbon/user)
	var/success = FALSE
	var/atom/movable/pulling = src?.pulling_target()
	if(pulling)
		act_message(user, src, others = span_danger("%U% has broken %T%'s grip on [pulling]!"))
		success = TRUE
		stop_pulling()

	if(istype(get_equipped_item(SLOT_ID_HAND_L), /obj/item/grab))
		var/obj/item/grab/lgrab = get_equipped_item(SLOT_ID_HAND_L)
		if(lgrab?.grab_target())
			act_message(user, src, others = span_danger("%U% has broken %T%'s grip on [lgrab?.grab_target()]!"))
			success = TRUE
		drop_from_inventory(lgrab)
	if(istype(get_equipped_item(SLOT_ID_HAND_R), /obj/item/grab))
		var/obj/item/grab/rgrab = get_equipped_item(SLOT_ID_HAND_R)
		if(rgrab?.grab_target())
			act_message(user, src, others = span_danger("%U% has broken %T%'s grip on [rgrab?.grab_target()]!"))
			success = TRUE
		drop_from_inventory(rgrab)
	return success

/*
	We want to ensure that a mob may only apply pressure to one organ of one mob at any given time. Currently this is done mostly implicitly through
	the behaviour of timed actions (om_task_timed) and the fact that applying pressure to someone else requires a grab:
	If you are applying pressure to yourself and attempt to grab someone else, you'll change what you are holding in your active hand which will stop do_mob()
	If you are applying pressure to another and attempt to apply pressure to yourself, you'll have to switch to an empty hand which will also stop do_mob()
	Changing targeted zones should also stop do_mob(), preventing you from applying pressure to more than one body part at once.
*/
/mob/living/carbon/human/proc/apply_pressure(mob/living/user, target_zone)
	var/obj/item/organ/external/organ = get_organ(target_zone)
	if(!organ || !(organ.status & ORGAN_BLEEDING) || (organ.is_robotic()))
		return FALSE

	if(organ.applied_pressure)
		var/message = span_warning("Someone is already applying pressure to [user == src ? "your [organ.name]" : "[src]'s [organ.name]"].")
		to_chat(user,message)
		return FALSE

	if(user == src)
		act_message(user, null, MSG_SELF(span_filter_notice("You start applying pressure to your [organ.name]!")), \
			MSG_OTHERS(span_filter_notice("%U% starts applying pressure to %THEIR% [organ.name]!")))
	else
		act_message(user, src, MSG_SELF(span_filter_notice("You start applying pressure to %T%'s [organ.name]!")), 			MSG_OTHERS(span_filter_notice("%U% starts applying pressure to %T%'s [organ.name]!")))
	rel_set(organ, nameof(organ.applied_pressure), user)

	//apply pressure as long as they stay still and keep grabbing
	//This USED to have a 'target_zone' check that never actually worked so whatever.
	//Let it be said that it's a feature you can apply pressure to all sites on you all at once.
	//You're already locking yourself down when you do so.
	task_start(/datum/task/timed/apply_pressure, user, organ, receiver = src)
	return TRUE

/// Pressure on a bleeding organ (the target), held until the user lets go or moves.
/datum/task/timed/apply_pressure
	duration = INFINITY
	hidden = TRUE
	complete_proc = /mob/living/carbon/human/proc/pressure_released
	cancel_proc = /mob/living/carbon/human/proc/pressure_released

/mob/living/carbon/human/proc/pressure_released(datum/task/timed/apply_pressure/task)
	var/mob/living/user = task.actor
	var/obj/item/organ/external/organ = task.target
	if(!organ)
		return
	rel_clear(organ, nameof(organ.applied_pressure))
	if(!user)
		return
	if(user == src)
		act_message(user, null, MSG_SELF(span_filter_notice("You stop applying pressure to your [organ]!")), \
			MSG_OTHERS(span_filter_notice("%U% stops applying pressure to %THEIR% [organ.name]!")))
	else
		act_message(user, src, MSG_SELF(span_filter_notice("You stop applying pressure to %T%'s [organ.name]!")), \
			MSG_OTHERS(span_filter_notice("%U% stops applying pressure to %T%'s [organ.name]!")))

// check_attacks verb body relocated to code/modules/mob/living/carbon/human/attacks_panel.dm (structured TGUI).


/mob/living/carbon/human/proc/set_default_attack(datum/unarmed_attack/u_attack)
	rel_set(src, nameof(default_attack), u_attack) // an attack the species owns

/mob/living/carbon/human/proc/perform_cpr(mob/living/carbon/human/reviver)
	// Check for sanity
	if(!istype(reviver,/mob/living/carbon/human))
		return
	if(HAS_SYNTHETIC_BIOLOGY(src))
		to_chat(reviver, span_danger("You push on [src]'s chest and realize you're shoving down on metal! This isn't going to work!"))
		return //Lets you know IMMEDIATELY that this is a robot. Do not pass go. Don't do damage or pump blood.

	//The below is what actually allows metabolism.
	apply_body_effect(/datum/body_effect/bloodpump_corpse/cpr, 2 SECONDS)
	// Compressions: a floor under cardiac output for a stopped heart (and,
	// with a vasopressor aboard, a chance to coarsen asystole into VF).
	body?.add_support(reviver, BF_PUMP, SUPPORT_CPR_PUMP, CPR_COMPRESSION_WINDOW)
	mend(TREAT_CHEST_COMPRESSION, 1)

	// Toggle for 'realistic' CPR. Use this if you want a more grim CPR approach that mimicks the damage that CPR can do to someone. This means more extensive internal damage, almost guaranteed rib breakage, etc.
	// DEFAULT: FALSE
	var/realistic_cpr = FALSE

	// brute damage
	if(prob(3))
		injure(INJURY_BLUNT, 1, BP_TORSO, reviver)
		if(prob(25) || (realistic_cpr)) //This being a 25% chance on top of the 3% chance means you have a 0.75% chance every compression to break ribs (and do minor internal damage). Realism mode means it's a 100% chance every time that 3% procs.
			var/obj/item/organ/external/chest = get_organ(BP_TORSO)
			if(chest)
				chest.fracture()

	// standard CPR ahead: restart a body whose injuries are survivable, or oxygenate a living one
	// A fibrillating or flatlined heart doesn't restart from compressions alone.
	if(stat == DEAD && !body?.is_lethal() && has_cardiac_output() && vitality() > 0.5 && prob(10))
		if(species.flags & NO_DEFIB) //TODO: Changee the NO_DEFIB species flag into a has_trait() sometime.
			to_chat(reviver, span_danger("You get the feeling [src] can't be revived by CPR alone."))
			return // Handle no-defib species flag.
		if(get_xenochimera_state())
			act_message(src, null, others = span_danger("%U%'s body twitches and gurgles a bit."))
			to_chat(reviver, span_danger("You get the feeling [src] can't be revived by CPR alone."))
			return // Handle xenochim, can't cpr them back to life
		if(has_mutation(HUSK))
			act_message(src, null, others = span_danger("%U%'s body crunches and snaps."))
			to_chat(reviver, span_danger("You get the feeling [src] is going to need surgical intervention to be revived."))
			return // Handle husked, cure it before you can revive
		if(!can_defib)
			act_message(src, null, others = span_danger("%U%'s neck shifts and cracks!"))
			to_chat(reviver, span_danger("You get the feeling [src] is going to need surgical intervention to be revived."))
			return // Handle broken neck/no attached brain
		var/bad_vital_organ = check_vital_organs()
		if(bad_vital_organ)
			act_message(src, null, others = span_danger("%U%'s body lays completely limp and lifeless!"))
			to_chat(reviver, span_danger("You get the feeling [src] is missing something vital."))
			return // Handle vital organs being missing.

		// allow revive chance
		var/mob/observer/dead/ghost = get_ghost()
		if(ghost)
			ghost.notify_revive("Someone is trying to resuscitate you. Re-enter your body if you want to be revived!", 'sound/effects/genetics.ogg', source = src)
		act_message(src, null, others = span_warning("%U%'s body convulses a bit."))

		// REVIVE TIME. Life() can bring them back to consciousness if it needs to.
		if(return_from_death("CPR", reviver, REVIVE_UNCONSCIOUS) != TRUE)
			return

		var/obj/item/organ/internal/lungs/lungs = organ_in(O_LUNGS)
		if(lungs)
			emote("gasp")
		status_at_least(STAT_WEAKENED, rand(10,25))
		//SShaunting.influence(HAUNTING_RESLEEVE) // Used for the Haunting module downstream. Not implemented upstream.

		// Same defib-window brain damage as a defibrillator (brain.revival_brain_damage()).
		var/obj/item/organ/internal/brain/brain = organ_in(O_BRAIN)
		if(should_have_organ(O_BRAIN) && istype(brain))
			var/brain_damage = brain.revival_brain_damage(injury_load(INJURY_CATEGORY_NEURAL))
			if(brain_damage > 0)
				injure(INJURY_NEURAL, brain_damage, null, null, 0, null, INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	else if(stat != DEAD)
		if(airway_obstructed())
			// Compressions may still shift what's stuck; the breaths won't go in.
			var/datum/affliction/airway_obstruction/choke = body?.find_affliction(/datum/affliction/airway_obstruction)
			choke?.receive_tagged_treatment(TREAT_AIRWAY, 10)
			to_chat(reviver, span_warning("Your rescue breaths won't go in - [src]'s airway is blocked!"))
			return
		// Rescue breaths: a floor under an apneic patient's breathing drive.
		body?.add_support(reviver, BF_RESP_DRIVE, SUPPORT_RESCUE_BREATH_DRIVE, CPR_RESCUE_BREATH_SECONDS SECONDS)

/// Abdominal thrusts to dislodge an airway obstruction.
/mob/living/carbon/human/proc/perform_heimlich(mob/living/carbon/human/rescuer, datum/affliction/airway_obstruction/choke)
	act_message(rescuer, src, others = span_danger("%U% wraps %THEIR% arms around %T% and thrusts hard under the ribs!"))
	task_timed(rescuer, 2 SECONDS, target = src, receiver = src, on_done = PROC_REF(perform_heimlich_human_done), done_args = list(choke))
	return TRUE

/mob/living/carbon/human/proc/perform_heimlich_human_done(datum/affliction/airway_obstruction/choke)
	if(QDELETED(choke) || choke.body != body)
		return FALSE
	choke.receive_tagged_treatment(TREAT_AIRWAY, rand(20, 45))
	if(QDELETED(choke))
		act_message(src, null, others = span_notice("%U% coughs something up and gasps for air!"))
		emote("gasp")
	else
		emote("cough")
	return TRUE

// One of the species' shared unarmed attacks.
