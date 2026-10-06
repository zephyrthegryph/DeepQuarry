/mob/living/carbon/human/resist_restraints()
	if(get_equipped_item(SLOT_ID_SUIT) && (istype(get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/straight_jacket) || istype(get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/shibari)))
		return escape_straight_jacket()
	return ..()

#define RESIST_ATTACK_DEFAULT	0
#define RESIST_ATTACK_CLAWS		1
#define RESIST_ATTACK_BITE		2

/mob/living/carbon/human/proc/escape_straight_jacket()
	setClickCooldown(100)

	if(can_break_straight_jacket())
		break_straight_jacket()
		return

	var/breakouttime
	var/mob/living/carbon/human/H = src
	if(istype(get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/straight_jacket))
		var/obj/item/clothing/suit/straight_jacket/S = H.get_equipped_item(SLOT_ID_SUIT)
		breakouttime = S.resist_time
	if(istype(get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/shibari))
		var/obj/item/clothing/suit/shibari/S = H.get_equipped_item(SLOT_ID_SUIT)
		breakouttime = S.resist_time

	var/obj/item/clothing/suit/SJ = get_equipped_item(SLOT_ID_SUIT)

	var/attack_type = RESIST_ATTACK_DEFAULT

	if(H.get_equipped_item(SLOT_ID_GLOVES) && istype(H.get_equipped_item(SLOT_ID_GLOVES),/obj/item/clothing/gloves/gauntlets/rig))
		breakouttime /= 2	// Pneumatic force goes a long way.
	else if(H.species.unarmed_types)
		for(var/datum/unarmed_attack/U in H.species.unarmed_types)
			if(istype(U, /datum/unarmed_attack/claws))
				breakouttime /= 1.5
				attack_type = RESIST_ATTACK_CLAWS
				break
			else if(istype(U, /datum/unarmed_attack/bite/sharp))
				breakouttime /= 1.25
				attack_type = RESIST_ATTACK_BITE
				break

	switch(attack_type)
		if(RESIST_ATTACK_DEFAULT)
			act_message(src, null, MSG_SELF(span_warning("You struggle to remove %I%. (This will take around [round(breakouttime / 600)] minutes and you need to stand still.)")), \
				MSG_OTHERS(span_danger("%U% struggles to remove %I%!")), \
				item = SJ)
		if(RESIST_ATTACK_CLAWS)
			act_message(src, null, MSG_SELF(span_warning("You claw at %I%. (This will take around [round(breakouttime / 600)] minutes and you need to stand still.)")), \
				MSG_OTHERS(span_danger("%U% starts clawing at %I%!")), \
				item = SJ)
		if(RESIST_ATTACK_BITE)
			act_message(src, null, MSG_SELF(span_warning("You gnaw on %I%. (This will take around [round(breakouttime / 600)] minutes and you need to stand still.)")), \
				MSG_OTHERS(span_danger("%U% starts gnawing on %I%!")), \
				item = SJ)

	task_timed(src, breakouttime, target = src, timed_action_flags = IGNORE_INCAPACITATED, receiver = src, on_done = PROC_REF(escape_straight_jacket_human_done), done_args = list())

/mob/living/carbon/human/proc/escape_straight_jacket_human_done()
	if(!get_equipped_item(SLOT_ID_SUIT))
		return
	act_message(src, null, MSG_SELF(span_notice("You successfully remove \the [get_equipped_item(SLOT_ID_SUIT)].")), \
		MSG_OTHERS(span_danger("%U% manages to remove \the [get_equipped_item(SLOT_ID_SUIT)]!")))
	drop_from_inventory(get_equipped_item(SLOT_ID_SUIT))

#undef RESIST_ATTACK_DEFAULT
#undef RESIST_ATTACK_CLAWS
#undef RESIST_ATTACK_BITE

/mob/living/carbon/human/proc/can_break_straight_jacket()
	if((has_mutation(HULK)) || species.can_shred(src,1))
		return 1

/mob/living/carbon/human/proc/break_straight_jacket()
	act_message(src, null, MSG_SELF(span_warning("You attempt to rip your [get_equipped_item(SLOT_ID_SUIT).name] apart. (This will take around 5 seconds and you need to stand still)")), \
		MSG_OTHERS(span_danger("%U% is trying to rip \the [get_equipped_item(SLOT_ID_SUIT)]!")))

	task_timed(src, 20 SECONDS, target = src, timed_action_flags = IGNORE_INCAPACITATED, receiver = src, on_done = PROC_REF(break_straight_jacket_human_done), done_args = list())

/mob/living/carbon/human/proc/break_straight_jacket_human_done()
	if(!get_equipped_item(SLOT_ID_SUIT) || src?.buckled_to())
		return

	act_message(src, null, MSG_SELF(span_warning("You successfully rip your [get_equipped_item(SLOT_ID_SUIT).name].")), \
		MSG_OTHERS(span_danger("%U% manages to rip \the [get_equipped_item(SLOT_ID_SUIT)]!")))

	if(has_mutation(HULK))
		say(pick(";RAAAAAAAARGH!", ";HNNNNNNNNNGGGGGGH!", ";GWAAAAAAAARRRHHH!", "NNNNNNNNGGGGGGGGHH!", ";AAAAAAARRRGH!", "RAAAAAAAARGH!", "HNNNNNNNNNGGGGGGH!", "GWAAAAAAAARRRHHH!", "AAAAAAARRRGH!" ))

	var/obj/item/ripped = get_equipped_item(SLOT_ID_SUIT)
	consume(ripped, src)
	var/obj/buckled = src?.buckled_to()
	if(buckled && buckled.buckle_require_restraints)
		buckled.unbuckle_mob()

/mob/living/carbon/human/can_break_cuffs()
	if(species.can_shred(src,1))
		return 1
	return ..()
