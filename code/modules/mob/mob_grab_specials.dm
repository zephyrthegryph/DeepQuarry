/obj/item/grab/proc/inspect_organ(mob/living/carbon/human/H, mob/user, target_zone)

	var/obj/item/organ/external/E = H.get_organ(target_zone)

	if(!E || E.is_stump())
		to_chat(user, span_notice("[H] is missing that bodypart."))
		return

	act_message(user, null, others = span_notice("%U% starts inspecting [src?.grab_target()]'s [E.name] carefully."))
	om_task_start(/datum/om/task/timed/grab_inspect_organ_grab, user, H, target_zone_arg = target_zone, E = E)
	return TRUE

/obj/item/grab/proc/inspect_organ_grab_failed(datum/om/task/timed/grab_inspect_organ_grab/task)
	var/mob/living/carbon/human/H = task.target
	var/mob/user = task.actor
	var/target_zone = task.target_zone_arg
	var/obj/item/organ/external/E = task.E
	to_chat(user, span_notice("You must stand still to inspect [E] for wounds."))
	inspect_bones(H, user, target_zone, E)

/datum/om/task/timed/grab_inspect_organ_grab
	duration = 1 SECOND
	complete_proc = /obj/item/grab/proc/inspect_organ_grab_done
	cancel_proc = /obj/item/grab/proc/inspect_organ_grab_failed
	var/target_zone_arg
	var/obj/item/organ/external/E

/obj/item/grab/proc/inspect_organ_grab_done(datum/om/task/timed/grab_inspect_organ_grab/task)
	var/mob/living/carbon/human/H = task.target
	var/mob/user = task.actor
	var/target_zone = task.target_zone_arg
	var/obj/item/organ/external/E = task.E
	if(length(E.get_wounds()))
		to_chat(user, span_warning("You find [E.get_wounds_desc()]"))
	else
		to_chat(user, span_notice("You find no visible wounds."))
	inspect_bones(H, user, target_zone, E)

/obj/item/grab/proc/inspect_bones(mob/living/carbon/human/H, mob/user, target_zone, obj/item/organ/external/E)
	to_chat(user, span_notice("Checking bones now..."))
	om_task_start(/datum/om/task/timed/grab_inspect_bones, user, H, target_zone_arg = target_zone, E = E)

/datum/om/task/timed/grab_inspect_bones
	duration = 2 SECONDS
	complete_proc = /obj/item/grab/proc/inspect_bones_done
	cancel_proc = /obj/item/grab/proc/inspect_bones_failed
	var/target_zone_arg
	var/obj/item/organ/external/E

/obj/item/grab/proc/inspect_bones_failed(datum/om/task/timed/grab_inspect_bones/task)
	to_chat(task.actor, span_notice("You must stand still to feel [task.E] for fractures."))
	inspect_bones_done(task)

/obj/item/grab/proc/inspect_bones_done(datum/om/task/timed/grab_inspect_bones/task)
	var/mob/living/carbon/human/H = task.target
	var/mob/user = task.actor
	var/target_zone = task.target_zone_arg
	var/obj/item/organ/external/E = task.E
	if(E.nonsolid && E.cannot_break) //boneless!
		to_chat(user, span_warning("You are unable to feel any bones in the [E.name]!"))
	else if(E.is_fractured())
		to_chat(user, span_warning("The [E.encased ? E.encased : "bone in the [E.name]"] moves slightly when you poke it!"))
		H.custom_pain("Your [E.name] hurts where it's poked.", 40)
	else
		to_chat(user, span_notice("The [E.encased ? E.encased : "bones in the [E.name]"] seem to be fine."))

	to_chat(user, span_notice("Checking skin now..."))
	om_task_start(/datum/om/task/timed/grab_inspect_skin, user, H, target_zone_arg = target_zone, E = E)

/obj/item/grab/proc/inspect_internal_failed(datum/om/task/timed/grab_inspect_internal/task)
	var/mob/living/carbon/human/H = task.target
	var/mob/user = task.actor
	var/obj/item/organ/external/E = task.E
	to_chat(user, span_notice("You must stand still to check [H]'s [E.name] for internal injury."))

/datum/om/task/timed/grab_inspect_internal
	duration = 5 SECONDS
	complete_proc = /obj/item/grab/proc/inspect_internal_done
	cancel_proc = /obj/item/grab/proc/inspect_internal_failed
	var/body_part
	var/obj/item/organ/external/E

/obj/item/grab/proc/inspect_internal_done(datum/om/task/timed/grab_inspect_internal/task)
	var/mob/living/carbon/human/H = task.target
	var/mob/user = task.actor
	var/body_part = task.body_part
	var/obj/item/organ/external/E = task.E

	///If we have a bad organ down here. Very non-specific. Doctor should ask how badly it hurt.
	var/bad_organs = 0
	///If we have appendicitis or not.
	var/appendicitis = FALSE
	switch(body_part)

		if(BP_GROIN)
			var/obj/item/organ/internal/intestine/intestine = H.organ_in(O_INTESTINE)
			var/obj/item/organ/internal/stomach/stomach = H.organ_in(O_STOMACH)
			var/obj/item/organ/internal/kidneys/kidneys = H.organ_in(O_KIDNEYS)
			var/obj/item/organ/internal/liver/liver = H.organ_in(O_LIVER)
			var/obj/item/organ/internal/spleen/spleen = H.organ_in(O_SPLEEN)
			var/obj/item/organ/internal/appendix/appendix = H.organ_in(O_APPENDIX)
			if(intestine && intestine.is_bruised())
				bad_organs++
			if(stomach && stomach.is_bruised())
				bad_organs++
			if(kidneys && kidneys.is_bruised())
				bad_organs++
			if(liver && liver.is_bruised())
				bad_organs++
			if(spleen && spleen.is_bruised())
				bad_organs++
			if(appendix && (appendix.is_bruised() || appendix.inflamed))
				bad_organs++
				appendicitis = TRUE

		if(BP_TORSO)
			var/obj/item/organ/internal/lungs/lungs = H.organ_in(O_LUNGS)
			var/obj/item/organ/internal/heart/heart = H.organ_in(O_HEART)
			if(lungs && lungs.is_bruised())
				bad_organs++
			if(heart && heart.is_bruised())
				bad_organs++

		if(BP_HEAD)
			var/obj/item/organ/internal/voicebox/voicebox = H.organ_in(O_VOICE)
			if(voicebox && voicebox.is_bruised())
				bad_organs++

	if(bad_organs)
		to_chat(user, span_warning("[H]'s [E.name] appears to be tender when you press on it, indicating an internal injury."))
		H.custom_pain("Your [E.name] hurts where it's poked.", bad_organs*20)

	if(appendicitis)
		var/pain_check = (H.stat && (H.can_feel_pain() || H.synth_cosmetic_pain) && H.factor(BF_ANALGESIA) < 60)
		if(pain_check) //They can feel pain.
			to_chat(user, span_danger("[H] jolts when you let go of their [E.name], indicating appendicitis!"))
			H.custom_pain("You feel pure agony as [src] pushes down on your [E.name]!", 200)

/obj/item/grab/proc/inspect_skin_failed(datum/om/task/timed/grab_inspect_skin/task)
	var/mob/living/carbon/human/H = task.target
	var/mob/user = task.actor
	var/target_zone = task.target_zone_arg
	var/obj/item/organ/external/E = task.E
	to_chat(user, span_notice("You must stand still to check [H]'s skin for abnormalities."))
	inspect_internal(H, user, target_zone, E)

/datum/om/task/timed/grab_inspect_skin
	duration = 1 SECOND
	complete_proc = /obj/item/grab/proc/inspect_skin_done
	cancel_proc = /obj/item/grab/proc/inspect_skin_failed
	var/target_zone_arg
	var/obj/item/organ/external/E

/obj/item/grab/proc/inspect_skin_done(datum/om/task/timed/grab_inspect_skin/task)
	var/mob/living/carbon/human/H = task.target
	var/mob/user = task.actor
	var/target_zone = task.target_zone_arg
	var/obj/item/organ/external/E = task.E
	var/bad = 0
	// Palpation: the signs a hands-on examination picks up.
	var/datum/diagnosis/D = H.diagnose(/datum/diagnostic_profile/palpation)
	for(var/datum/diagnosis_finding/F as anything in D?.findings_of(DIAG_FINDING_SIGN))
		to_chat(user, span_warning(F.name))
		bad = 1
	spent(D)
	var/saturation = H.body?.oxygenation()
	if(!isnull(saturation) && saturation < 90)
		to_chat(user, span_warning("[H]'s skin is unusually pale."))
		bad = 1
	if(E.status & ORGAN_DEAD)
		to_chat(user, span_warning("[E] is decaying!"))
		bad = 1
	if(E.status & ORGAN_DEAD) //this is also infection level 3
		to_chat(user, span_bolddanger("[H]'s [E.name] is gangreous and completely dead!"))
		bad = 1
	else if(E.germ_level > INFECTION_LEVEL_ONE)
		if(E.germ_level > INFECTION_LEVEL_TWO)
			to_chat(user, span_danger("[H]'s [E.name] shows signs of a severe infection!"))
			bad = 1
		else
			to_chat(user, span_warning("[H] shows signs of infection in the [E.name]."))
			bad = 1
	for(var/datum/affliction/wound/W as anything in E.get_wounds())
		if(W.internal)
			to_chat(user, span_danger("You find a large, swelling hematoma in the skin")) //INTERNAL BLEEDING, BE VERY AFRAID.
			break
	if(!bad)
		to_chat(user, span_notice("[H]'s skin is normal."))
	inspect_internal(H, user, target_zone, E)

/obj/item/grab/proc/inspect_internal(mob/living/carbon/human/H, mob/user, target_zone, obj/item/organ/external/E)

	var/body_part = parse_zone(target_zone)
	if(body_part == BP_GROIN || body_part == BP_TORSO || body_part == BP_HEAD)
		to_chat(user, span_notice("Checking for internal injury now..."))
		om_task_start(/datum/om/task/timed/grab_inspect_internal, user, H, body_part = body_part, E = E)


/obj/item/grab/proc/jointlock(mob/living/carbon/human/target, mob/attacker, target_zone)
	if(state < GRAB_AGGRESSIVE)
		to_chat(attacker, span_warning("You require a better grab to do this."))
		return

	var/obj/item/organ/external/organ = target.get_organ(check_zone(target_zone))
	if(!organ || organ.dislocated == -1)
		return

	act_message(attacker, target, others = span_danger("%U% [pick("bent", "twisted")] %T%'s [organ.name] into a jointlock!"))

	if(!target.can_feel_pain(organ))
		return

	var/armor = target.armor_against(INJURY_PAIN)
	if(armor < 60)
		to_chat(target, span_danger("You feel extreme pain!"))

		var/max_pain = round(target.get_endurance() * 0.8) //up to 80% of passing out
		target.injure(INJURY_PAIN, CLAMP(max_pain - target.current_pain(), 0, 30), organ.organ_tag, attacker)

/obj/item/grab/proc/attack_eye(mob/living/carbon/human/target, mob/living/carbon/human/attacker)
	if(!istype(attacker))
		return

	var/datum/unarmed_attack/attack = attacker.get_unarmed_attack(target, O_EYES)

	if(!attack)
		return
	if(state < GRAB_NECK)
		to_chat(attacker, span_warning("You require a better grab to do this."))
		return
	for(var/obj/item/protection in list(target.get_equipped_item(SLOT_ID_HEAD), target.get_equipped_item(SLOT_ID_MASK), target.get_equipped_item(SLOT_ID_EYES)))
		if(protection && (protection.body_parts_covered & EYES))
			to_chat(attacker, span_danger("You're going to need to remove the eye covering first."))
			return
	if(!target.has_eyes())
		to_chat(attacker, span_danger("You cannot locate any eyes on [target]!"))
		return

	add_attack_logs(attacker,target,"Eye gouge using grab")

	attack.handle_eye_attack(attacker, target)

/obj/item/grab/proc/headbutt(mob/living/carbon/human/target, mob/living/carbon/human/attacker)
	if(!istype(attacker))
		return
	if(target.lying)
		return
	act_message(attacker, target, others = span_danger("%U% thrusts %THEIR% head into %T%'s skull!"))

	var/damage = 20
	var/obj/item/clothing/hat = attacker.get_equipped_item(SLOT_ID_HEAD)
	if(istype(hat))
		damage += hat.force * 3

	var/armor = target.armor_against(INJURY_BLUNT, BP_HEAD)
	target.injure(INJURY_BLUNT, damage, BP_HEAD, attacker, flags = INJURE_ARMORED)
	attacker.injure(INJURY_BLUNT, 10, BP_HEAD, target, flags = INJURE_ARMORED)

	if(!armor && target.headcheck(BP_HEAD) && prob(damage))
		target.apply_effect(20, PARALYZE)
		act_message(target, null, others = span_danger("%U% [target.species.get_knockout_message(target)]"))

	play_sfx(attacker, SFX_SWING_HIT)
	add_attack_logs(attacker,target,"Headbutted using grab")

	attacker.drop_from_inventory(src)
	src.moveToNullspace()
	spent(src, attacker)
	return

/obj/item/grab/proc/dislocate(mob/living/carbon/human/target, mob/living/attacker, target_zone)
	if(state < GRAB_NECK)
		to_chat(attacker, span_warning("You require a better grab to do this."))
		return
	if(target.grab_joint(attacker, target_zone))
		play_sfx(src, SFX_WEAPONS_THUDSWOOSH)
		return

/obj/item/grab/proc/pin_down(mob/target, mob/attacker)
	var/mob/living/carbon/human/assailant = src?.grab_assailant()
	if(state < GRAB_AGGRESSIVE)
		to_chat(attacker, span_warning("You require a better grab to do this."))
		return
	if(force_down)
		to_chat(attacker, span_warning("You are already pinning [target] to the ground."))
		return
	if(size_difference(src?.grab_target(), assailant) > 0)
		to_chat(attacker, span_warning("You are too small to do that!"))
		return

	act_message(attacker, target, others = span_danger("%U% starts forcing %T% to the ground!"))
	om_task_timed(attacker, 2 SECONDS, target = target, receiver = src, on_done = PROC_REF(pin_down_grab_done), done_args = list(target, attacker))

/obj/item/grab/proc/pin_down_grab_done(mob/target, mob/attacker)
	if(!(target))
		return
	note_action()
	act_message(attacker, target, others = span_danger("%U% forces %T% to the ground!"))
	apply_pinning(target, attacker)

/obj/item/grab/proc/apply_pinning(mob/target, mob/attacker)
	force_down = 1
	target.status_at_least(STAT_WEAKENED, 3)
	target.lying = 1
	step_to(attacker, target)
	attacker.set_dir(EAST) //face the victim
	target.set_dir(SOUTH) //face up
