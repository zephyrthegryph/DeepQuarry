/mob/living/carbon/human/resist_restraints()
	if(get_equipped_item(SLOT_ID_WEAR_SUIT) && (istype(get_equipped_item(SLOT_ID_WEAR_SUIT), /obj/item/clothing/suit/straight_jacket) || istype(get_equipped_item(SLOT_ID_WEAR_SUIT), /obj/item/clothing/suit/shibari)))
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
	if(istype(get_equipped_item(SLOT_ID_WEAR_SUIT), /obj/item/clothing/suit/straight_jacket))
		var/obj/item/clothing/suit/straight_jacket/S = H.get_equipped_item(SLOT_ID_WEAR_SUIT)
		breakouttime = S.resist_time
	if(istype(get_equipped_item(SLOT_ID_WEAR_SUIT), /obj/item/clothing/suit/shibari))
		var/obj/item/clothing/suit/shibari/S = H.get_equipped_item(SLOT_ID_WEAR_SUIT)
		breakouttime = S.resist_time

	var/obj/item/clothing/suit/SJ = get_equipped_item(SLOT_ID_WEAR_SUIT)

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
			visible_message(
			span_danger("\The [src] struggles to remove \the [SJ]!"),
			span_warning("You struggle to remove \the [SJ]. (This will take around [round(breakouttime / 600)] minutes and you need to stand still.)")
			)
		if(RESIST_ATTACK_CLAWS)
			visible_message(
			span_danger("\The [src] starts clawing at \the [SJ]!"),
			span_warning("You claw at \the [SJ]. (This will take around [round(breakouttime / 600)] minutes and you need to stand still.)")
			)
		if(RESIST_ATTACK_BITE)
			visible_message(
			span_danger("\The [src] starts gnawing on \the [SJ]!"),
			span_warning("You gnaw on \the [SJ]. (This will take around [round(breakouttime / 600)] minutes and you need to stand still.)")
			)

	if(do_after(src, breakouttime, target = src, timed_action_flags = IGNORE_INCAPACITATED))
		if(!get_equipped_item(SLOT_ID_WEAR_SUIT))
			return
		visible_message(
			span_danger("\The [src] manages to remove \the [get_equipped_item(SLOT_ID_WEAR_SUIT)]!"),
			span_notice("You successfully remove \the [get_equipped_item(SLOT_ID_WEAR_SUIT)].")
			)
		drop_from_inventory(get_equipped_item(SLOT_ID_WEAR_SUIT))

#undef RESIST_ATTACK_DEFAULT
#undef RESIST_ATTACK_CLAWS
#undef RESIST_ATTACK_BITE

/mob/living/carbon/human/proc/can_break_straight_jacket()
	if((HULK in mutations) || species.can_shred(src,1))
		return 1

/mob/living/carbon/human/proc/break_straight_jacket()
	visible_message(
		span_danger("[src] is trying to rip \the [get_equipped_item(SLOT_ID_WEAR_SUIT)]!"),
		span_warning("You attempt to rip your [get_equipped_item(SLOT_ID_WEAR_SUIT).name] apart. (This will take around 5 seconds and you need to stand still)")
		)

	if(do_after(src, 20 SECONDS, target = src, timed_action_flags = IGNORE_INCAPACITATED))	// Same scaling as breaking cuffs, 5 seconds to 120 seconds, 20 seconds to 480 seconds.
		if(!get_equipped_item(SLOT_ID_WEAR_SUIT) || buckled)
			return

		visible_message(
			span_danger("[src] manages to rip \the [get_equipped_item(SLOT_ID_WEAR_SUIT)]!"),
			span_warning("You successfully rip your [get_equipped_item(SLOT_ID_WEAR_SUIT).name].")
			)

		if(HULK in mutations)
			say(pick(";RAAAAAAAARGH!", ";HNNNNNNNNNGGGGGGH!", ";GWAAAAAAAARRRHHH!", "NNNNNNNNGGGGGGGGHH!", ";AAAAAAARRRGH!", "RAAAAAAAARGH!", "HNNNNNNNNNGGGGGGH!", "GWAAAAAAAARRRHHH!", "AAAAAAARRRGH!" ))

		var/obj/item/ripped = get_equipped_item(SLOT_ID_WEAR_SUIT)
		drop_from_inventory(ripped)
		qdel(ripped)
		if(buckled && buckled.buckle_require_restraints)
			buckled.unbuckle_mob()

/mob/living/carbon/human/can_break_cuffs()
	if(species.can_shred(src,1))
		return 1
	return ..()
