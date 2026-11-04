/obj/item/flame/lighter/supermatter/expsmzippo
	name = "Experimental SM Lighter"		// Dangerous WIP (admin/event only ATM)
	desc = "State of the Art Supermatter Lighter"
	icon_state = "ExpSMzippo"
	item_state = "ExpSMzippo"
	activation_sound = SFX_ITEMS_BUTTON_OPEN
	deactivation_sound = SFX_ITEMS_BUTTON_CLOSE
	special_supermatter = TRUE

CAPABILITIES(/obj/item/flame/lighter/supermatter/expsmzippo)
	configure(atom_rules(description_fluff = "A unique take originating from the zippo design, a shard of supermatter placed within lead-lined walls. Cautious, VERY DANGEROUS do NOT touch!"))

// Experimental smzippo
/// The experimental supermatter lighter.
/obj/item/flame/lighter/supermatter/expsmzippo/toggled(datum/act/op/A)
	var/mob/living/user = A.actor
	if (!base_state)
		base_state = icon_state
	if (!lit)
		set_lit(1)
		set_icon_state("[base_state]on")
		set_item_state("[base_state]on")
		playsound(src, activation_sound, 75, 1)
		var/i = rand(1, 100)
		switch(i)
			if(1 to 22)
				act_message(user, src, MSG_SELF(span_notice(span_rose("You safely revealed the supermatter shard within %T%!"))), MSG_OTHERS(span_notice(span_rose("%U% safely reveals the supermatter shard within %T%!"))))
				if (user.get_left_hand() == src)
					user.injure(INJURY_RADIATION, 1, BP_L_HAND, src)
				else			// Even using this safely will irradiate you a tiny tiny bit.
					user.injure(INJURY_RADIATION, 1, BP_R_HAND, src)
			if(23 to 33)
				act_message(user, null, MSG_SELF(span_notice("You accidentally grazed your hand across the supermatter!")), MSG_OTHERS(span_warning("%U%'s hand slipped and they brush against the supermatter within [src]!")))
				if (user.get_left_hand() == src)
					user.injure(INJURY_RADIATION, 10, BP_L_HAND, src)
					user.injure(INJURY_BURN, 20, BP_L_HAND, src)
					user.injure(INJURY_ELECTRIC, 20, BP_L_HAND, src)
					user.injure(INJURY_PAIN, 50, BP_L_HAND, src)
				else			// One of the outcomes will burn and shock you, the pain is the worst part of this one though.
					user.injure(INJURY_RADIATION, 10, BP_R_HAND, src)
					user.injure(INJURY_BURN, 20, BP_R_HAND, src)
					user.injure(INJURY_ELECTRIC, 20, BP_R_HAND, src)
					user.injure(INJURY_PAIN, 50, BP_R_HAND, src)
			if(34 to 44)
				act_message(user, src, MSG_SELF(span_notice("You accidentally burn yourself on %T%!")), MSG_OTHERS(span_warning("%U% burned themselves on %T%!")))
				if (user.get_left_hand() == src)
					user.injure(INJURY_RADIATION, 30, BP_L_HAND, src)
					user.injure(INJURY_BURN, 20 / 3, BP_L_HAND, src)
					user.injure(INJURY_BLUNT, 40 / 3, BP_L_HAND, src)
					user.injure(INJURY_BURN, 15, BP_L_HAND, src)
				else			// One of the outcomes is pure burn and radiation.
					user.injure(INJURY_RADIATION, 30, BP_R_HAND, src)
					user.injure(INJURY_BURN, 20 / 3, BP_R_HAND, src)
					user.injure(INJURY_BLUNT, 40 / 3, BP_R_HAND, src)
					user.injure(INJURY_BURN, 15, BP_R_HAND, src)
			if(45 to 55)
				act_message(user, src, MSG_SELF(span_notice("You fumble %T%, letting the supermatter spark as the case opens!")), MSG_OTHERS(span_warning("%U% fumbled %T% and the supermatter let out sparks!")))
				if (user.get_left_hand() == src)
					user.injure(INJURY_ELECTRIC, 1, BP_L_HAND, src)
					user.emp_act(EMP_HEAVY)
				else			// This one is mostly dangerous to synthetics and it will EMP you. But otherwise it's safe.
					user.injure(INJURY_ELECTRIC, 1, BP_R_HAND, src)
					user.emp_act(EMP_HEAVY)
			if(56 to 66)
				act_message(user, src, MSG_SELF(span_notice("You struggle to get the case to open, and when it does the heat that pours out of %T% burns!")), MSG_OTHERS(span_warning("%U% struggles to open their [src], but when they do they get burned by the extreme heat within!")))
				if (user.get_left_hand() == src)
					user.injure(INJURY_RADIATION, 1, BP_L_HAND, src)
					user.injure(INJURY_BLUNT, 1, BP_L_HAND, src)
					user.injure(INJURY_BURN, 200, BP_L_HAND, src)
					user.drop_l_hand()
				else			// This will INSTA-DUST your hand that you're holding the item in, and then make you drop the lighter.
					user.injure(INJURY_RADIATION, 1, BP_R_HAND, src)
					user.injure(INJURY_BLUNT, 1, BP_R_HAND, src)
					user.injure(INJURY_BURN, 200, BP_R_HAND, src)
					user.drop_r_hand()
			if(67 to 77)
				act_message(user, null, MSG_SELF(span_notice("You accidentally pushed your finger against the supermatter!")), MSG_OTHERS(span_warning("Ouch! While pushing on the release to open the [src], %U%'s finger slipped right as the case opened, pressing their finger firm against the supermatter!")))
				if (user.get_left_hand() == src)
					user.injure(INJURY_PAIN, 50, BP_L_HAND, src)
					user.injure(INJURY_RADIATION, 40, BP_L_HAND, src)
					user.injure(INJURY_BURN, 30, BP_L_HAND, src)
					user.injure(INJURY_TOXIN, 20, BP_L_HAND, src)
					user.injure(INJURY_ELECTRIC, 10, BP_L_HAND, src)
					user.apply_effect(25, STUTTER)
					user.apply_effect(15, SLUR)
					user.apply_effect(5, STUN)
				else			// This one is VERY punishing, you get a ton of damage, a lot of pain, and a minor stun. Once the stun goes away you'll be stuttering for awhile as if in crit.
					user.injure(INJURY_PAIN, 50, BP_R_HAND, src)
					user.injure(INJURY_RADIATION, 40, BP_R_HAND, src)
					user.injure(INJURY_BURN, 30, BP_R_HAND, src)
					user.injure(INJURY_TOXIN, 20, BP_R_HAND, src)
					user.injure(INJURY_ELECTRIC, 10, BP_R_HAND, src)
					user.apply_effect(25, STUTTER)
					user.apply_effect(15, SLUR)
					user.apply_effect(5, STUN)
			if(78 to 88)
				act_message(user, null, MSG_SELF(span_notice("You manage to pinch yourself on the case!")), MSG_OTHERS(span_notice("%U% managed to pinch themselves on the case of their [src]... it could have been worse.")))
				if (user.get_left_hand() == src)
					user.injure(INJURY_CELLULAR, 1, BP_L_HAND, src)
					user.injure(INJURY_PAIN, 1, BP_L_HAND, src)
				else			// Aside from the base, this one isn't punishing outside of giving you genetic damage.
					user.injure(INJURY_CELLULAR, 1, BP_R_HAND, src)
					user.injure(INJURY_PAIN, 1, BP_R_HAND, src)
			if(89 to 99)
				act_message(user, null, MSG_SELF(span_notice("You find yourself looking at the supermatter for longer than you should...")), MSG_OTHERS(span_notice("%U% opened the [src] but forgot that you aren't supposed to look at supermatter!")))
				if (user.get_left_hand() == src)
					user.injure(INJURY_PAIN, 15, BP_L_HAND, src)
					user.apply_effect(5, WEAKEN)
					user.injure(INJURY_RADIATION, 15, BP_L_HAND, src)
					user.apply_effect(100, EYE_BLUR)
					user.apply_effect(50, AGONY)
					user.add_oxygen_debt(5, src)
					user.status_set(STAT_BLURRY, 10)
				else			// This one just blinds and blurs your screen, but otherwise doesn't actually risk harming you. Even the oxy damage heals on its own.
					user.injure(INJURY_PAIN, 15, BP_R_HAND, src)
					user.apply_effect(5, WEAKEN)
					user.injure(INJURY_RADIATION, 15, BP_L_HAND, src)
					user.apply_effect(100, EYE_BLUR)
					user.apply_effect(50, AGONY)
					user.add_oxygen_debt(15, src)
					user.status_set(STAT_BLURRY, 10)
			if(100)				// This is the part that makes it admin only for the moment, it spawns 500 rads from the carbon's position, and dusts the carbon instantly. It does also drop everything unlike the supermatter crystal though, so hopefully you won't lose any items if you fumble this badly!
				act_message(user, src, MSG_SELF(span_danger("You almost dropped your [src], thank goodness you caught it! By the glowing crystal within. You find your ears filled with unearthly ringing and your last thought is \"Oh, fuck.\"")), MSG_OTHERS(span_warning("OH NO! %U% almost dropped their live %T%! Thank goodness they caught it... by the glowing yellow crystal... oh.")))
				user.drop_r_hand() // To ensure the lighter is dropped <3
				user.drop_l_hand() // To ensure the lighter is dropped <3
				for(var/obj/item/e in user)
					user.drop_from_inventory(e)
				log_and_message_admins("[user] dusted themselves and caused massive radiation with [src]!",user)
				user.dust()
				radiation_pulse(
					src,
					max_range = 12,
					threshold = RAD_HEAVY_INSULATION,
					chance = URANIUM_IRRADIATION_CHANCE * 2,
					strength = 300
				)
		set_glow(src, GLOW(5, null, null))
	else
		set_lit(0)
		set_icon_state("[base_state]")
		set_item_state("[base_state]")
		playsound(src, deactivation_sound, 75, 1)
		if (istype(src, /obj/item/flame/lighter/supermatter/expsmzippo))
			act_message(user, src, others = span_notice(span_rose("You hear a quiet click, as %U% closes %T%.")))
		else
			act_message(user, src, others = span_notice("%U% quietly shuts %T%."))

		set_glow(src, GLOW(0, null, null))
	return OP_OK

/obj/item/flame/lighter/supermatter/expsmzippo/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if (lit == 1)
		M.ignite_mob()
		add_attack_logs(user, M, "Lit on fire with [src]")

	if (istype(M.get_equipped_item(SLOT_ID_MASK), /obj/item/clothing/mask/smokable/cigarette) && hud_of(user)?.zone_sel?.selecting == O_MOUTH && lit)
		var/obj/item/clothing/mask/smokable/cigarette/cig = M.get_equipped_item(SLOT_ID_MASK)
		if (M == user)
			cig.attackby(src, user)
		else
			if (istype(src, /obj/item/flame/lighter/supermatter/expsmzippo))
				cig.light(span_notice(span_rose("[user] whips the [name] out and holds it for [M].")), user)
			else
				cig.light(span_notice("[user] holds the [name] out for [M], and lights the [cig.name]."), user)
	else
		..()
