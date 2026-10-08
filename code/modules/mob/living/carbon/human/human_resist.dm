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

	perform_op(src, src, "jacket_escape", null, ORIGIN_SYSTEM, AUTH_PHYSICAL)

/// How the wearer works at the jacket: RESIST_ATTACK_DEFAULT, or the claws / sharp teeth their species has (a rig gauntlet counts as none).
/mob/living/carbon/human/proc/jacket_attack_type()
	var/mob/living/carbon/human/H = src
	if(H.get_equipped_item(SLOT_ID_GLOVES) && istype(H.get_equipped_item(SLOT_ID_GLOVES),/obj/item/clothing/gloves/gauntlets/rig))
		return RESIST_ATTACK_DEFAULT
	if(H.species.unarmed_types)
		for(var/datum/unarmed_attack/U in H.species.unarmed_types)
			if(istype(U, /datum/unarmed_attack/claws))
				return RESIST_ATTACK_CLAWS
			else if(istype(U, /datum/unarmed_attack/bite/sharp))
				return RESIST_ATTACK_BITE
	return RESIST_ATTACK_DEFAULT

/// Deciseconds the jacket (or shibari) takes to slip.
/mob/living/carbon/human/proc/jacket_breakout_time(datum/act/op/A)
	var/breakouttime
	if(istype(get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/straight_jacket))
		var/obj/item/clothing/suit/straight_jacket/S = get_equipped_item(SLOT_ID_SUIT)
		breakouttime = S.resist_time
	if(istype(get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/shibari))
		var/obj/item/clothing/suit/shibari/S = get_equipped_item(SLOT_ID_SUIT)
		breakouttime = S.resist_time

	var/mob/living/carbon/human/H = src
	if(H.get_equipped_item(SLOT_ID_GLOVES) && istype(H.get_equipped_item(SLOT_ID_GLOVES),/obj/item/clothing/gloves/gauntlets/rig))
		breakouttime /= 2	// Pneumatic force goes a long way.
	else
		switch(jacket_attack_type())
			if(RESIST_ATTACK_CLAWS)
				breakouttime /= 1.5
			if(RESIST_ATTACK_BITE)
				breakouttime /= 1.25
	return breakouttime

/mob/living/carbon/human/proc/jacket_escape_text(datum/act/op/A)
	var/breakouttime = jacket_breakout_time(A)
	var/obj/item/clothing/suit/SJ = get_equipped_item(SLOT_ID_SUIT)
	switch(jacket_attack_type())
		if(RESIST_ATTACK_CLAWS)
			return msg_text(span_warning("You claw at [SJ]. (This will take around [round(breakouttime / 600)] minutes and you need to stand still.)"), span_danger("%U% starts clawing at [SJ]!"))
		if(RESIST_ATTACK_BITE)
			return msg_text(span_warning("You gnaw on [SJ]. (This will take around [round(breakouttime / 600)] minutes and you need to stand still.)"), span_danger("%U% starts gnawing on [SJ]!"))
	return msg_text(span_warning("You struggle to remove [SJ]. (This will take around [round(breakouttime / 600)] minutes and you need to stand still.)"), span_danger("%U% struggles to remove [SJ]!"))

/mob/living/carbon/human/proc/jacket_escape_done(datum/act/op/A)
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
	perform_op(src, src, "jacket_rip", null, ORIGIN_SYSTEM, AUTH_PHYSICAL)

/mob/living/carbon/human/proc/jacket_rip_text(datum/act/op/A)
	return msg_text(span_warning("You attempt to rip your [get_equipped_item(SLOT_ID_SUIT).name] apart. (This will take around 5 seconds and you need to stand still)"), span_danger("%U% is trying to rip \the [get_equipped_item(SLOT_ID_SUIT)]!"))

/mob/living/carbon/human/proc/jacket_rip_done(datum/act/op/A)
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
