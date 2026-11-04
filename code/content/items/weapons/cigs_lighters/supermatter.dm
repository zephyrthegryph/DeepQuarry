/obj/item/flame/lighter/supermatter
	name = "Hardlight Supermatter Zippo"	// Base SM Lighter
	desc = "State of the Art Supermatter Lighter."
	icon_state = "SMzippo"
	item_state = "SMzippo"
	activation_sound = SFX_ITEMS_ZIPPO_ON_ALT
	deactivation_sound = SFX_ITEMS_ZIPPO_OFF
	special_variant = TRUE
	///Special supermatter var used for attack_self chain logic.
	var/special_supermatter = FALSE

CAPABILITIES(/obj/item/flame/lighter/supermatter)
	configure(atom_rules(description_fluff = "A zippo style lighter with a tiny supermatter sliver held by a hardlight shield. When lighting a cigar, make sure to hover the tip near the sliver, not against it!"))

// safe smzippo
/// The hardlight supermatter zippo (the dangerous ones below override this).
/obj/item/flame/lighter/supermatter/toggled(datum/act/op/A)
	var/mob/living/user = A.actor
	if(special_supermatter)
		return OP_DECLINE
	if(!base_state)
		base_state = icon_state
	if(!lit)
		set_lit(1)
		set_icon_state("[base_state]on")
		set_item_state("[base_state]on")
		playsound(src, activation_sound, 75, 1)
		if(prob(50))
			act_message(user, src, others = span_notice(span_rose("%U% safely activates %T% with a push of a button!")))
		else
			if(prob(95))
				act_message(user, src, others = span_notice("After a few attempts, %U% manages to excite the supermatter within %T%."))
			else			// Just like the cheap lighter, this time you can shock/burn yourself a little on the hardlight shield
				to_chat(user, span_warning("You hurt yourself on the shielding!"))
				if (user.get_left_hand() == src)
					user.injure(INJURY_BURN, 1/3, BP_L_HAND, src)
					user.injure(INJURY_BLUNT, 2/3, BP_L_HAND, src)
					user.injure(INJURY_ELECTRIC, 2, BP_L_HAND, src)
					user.injure(INJURY_CELLULAR, 3, BP_L_HAND, src)
					user.emp_act(EMP_HARMLESS)
				else
					user.injure(INJURY_BURN, 1/3, BP_R_HAND, src)
					user.injure(INJURY_BLUNT, 2/3, BP_R_HAND, src)
					user.injure(INJURY_ELECTRIC, 2, BP_R_HAND, src)
					user.injure(INJURY_CELLULAR, 3, BP_R_HAND, src)
					user.emp_act(EMP_HARMLESS)
				act_message(user, src, others = span_notice("After a few attempts, %U% manages to activate %T%, they however sting themselves on the shielding!"))

		set_glow(src, GLOW(2, null, null))
	else
		set_lit(0)
		set_icon_state("[base_state]")
		set_item_state("[base_state]")
		playsound(src, deactivation_sound, 75, 1)
		if(istype(src, /obj/item/flame/lighter/supermatter) )
			act_message(user, src, others = span_notice(span_rose("You hear a quiet click, as %U% shuts %T% without even looking at what they're doing.")))
		else
			act_message(user, src, others = span_notice("%U% quietly shuts %T%."))

		set_glow(src, GLOW(0, null, null))
	return OP_OK

/obj/item/flame/lighter/supermatter/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(lit == 1)
		M.ignite_mob()
		add_attack_logs(user,M,"Lit on fire with [src]")
		return ITEM_INTERACT_SUCCESS

	if(istype(M.get_equipped_item(SLOT_ID_MASK), /obj/item/clothing/mask/smokable/cigarette) && hud_of(user)?.zone_sel?.selecting == O_MOUTH && lit)
		var/obj/item/clothing/mask/smokable/cigarette/cig = M.get_equipped_item(SLOT_ID_MASK)
		if(M == user)
			cig.attackby(src, user)
		else
			if(istype(src, /obj/item/flame/lighter/supermatter))
				cig.light(span_notice(span_rose("[user] whips the [name] out and holds it for [M].")), user)
			else
				cig.light(span_notice("[user] holds the [name] out for [M], and lights the [cig.name]."), user)
		return ITEM_INTERACT_SUCCESS
	else
		..()
