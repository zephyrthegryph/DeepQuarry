// Hit by a projectile.
/mob/living/simple_mob/bullet_act(obj/item/projectile/P)
	//Projectiles with bonus SA damage
	if(!P.nodamage && P.mob_bonus_damage && !mind) //If the projectile is NOT a nodamage projectile, we HAVE A BONUS damage, AND the mob is not player controlled (it has no mind), we do bonus damage
		P.damage += P.mob_bonus_damage

	. = ..()


// When someone clicks us with an empty hand
/mob/living/simple_mob/attack_hand(mob/living/L)
	..()

	switch(L.use_stance())
		if(I_HELP)
			if(stat != DEAD)
				if(L.zone_sel.selecting == BP_GROIN)
					if(L.vore_bellyrub(src))
						return
				L.visible_message(span_notice("\The [L] [response_help] \the [src]."))

		if(I_DISARM)
			L.visible_message(span_notice("\The [L] [response_disarm] \the [src]."))
			L.do_attack_animation(src)
			//TODO: Push the mob away or something

		if(I_GRAB)
			if (L == src)
				return
			if (!(status_flags & CANPUSH))
				return
			if(!incapacitated(INCAPACITATION_ALL) && prob(grab_resist))
				L.visible_message(span_warning("\The [L] tries to grab \the [src] but fails!"))
				return

			var/obj/item/grab/G = new /obj/item/grab(L, src)

			L.put_in_active_hand(G)

			G.synch()
			G.affecting = src
			LAssailant = L

			L.visible_message(span_warning("\The [L] has grabbed [src] passively!"))
			L.do_attack_animation(src)

		if(I_HURT)
			if(ishuman(L))
				var/mob/living/carbon/human/attacker = L //We are a human!
				var/datum/unarmed_attack/attack = attacker.get_unarmed_attack(src, BP_TORSO) //What attack are we using? Also, just default to attacking the chest.
				var/rand_damage = rand(1, 5) //Like normal human attacks, let's randomize the damage...
				var/real_damage = rand_damage //Let's go ahead and start calculating our damage.
				var/hit_kind = attack.injury_kind //What the unarmed attack inflicts.
				real_damage += attack.get_unarmed_damage(attacker) //Add the damage that their special attack has. Some have 0. Some have 15.
				if(attacker.gloves && attack.is_punch)
					if(istype(attacker.gloves, /obj/item/clothing/gloves))
						var/obj/item/clothing/gloves/G = attacker.gloves
						real_damage += G.punch_force
						hit_kind = G.punch_injury_kind || hit_kind
					else if(istype(attacker.gloves, /obj/item/clothing/accessory))
						var/obj/item/clothing/accessory/G = attacker.gloves
						real_damage += G.punch_force
						hit_kind = G.punch_injury_kind || hit_kind
					if(HULK in attacker.mutations)
						real_damage *= 2
				if(real_damage <= damage_threshold)
					L.visible_message(span_warning("\The [L] uselessly hits \the [src]!"))
					L.do_attack_animation(src)
					return
				injure(hit_kind, real_damage, null, L, flags = INJURE_ARMORED)
				L.visible_message(span_warning("\The [L] [pick(attack.attack_verb)] \the [src]!"))
				L.do_attack_animation(src)
				return
			injure(INJURY_BLUNT, harm_intent_damage, null, L, flags = INJURE_ARMORED)
			L.visible_message(span_warning("\The [L] [response_harm] \the [src]!"))
			L.do_attack_animation(src)

	return


// When somoene clicks us with an item in hand
/mob/living/simple_mob/attackby(obj/item/O, mob/user)
	if(istype(O, /obj/item/stack/medical))
		if(stat != DEAD)
			// This could be done better.
			var/obj/item/stack/medical/MED = O
			if(is_injured())
				if(MED.use(1))
					mend(TREAT_TISSUE_REPAIR, MED.heal_brute)
					visible_message(span_infoplain(span_bold("\The [user]") + " applies the [MED] on [src]."))
		else
			to_chat(user, span_notice("\The [src] is dead, medical items won't bring [p_them()] back to life.")) // the gender lookup is somewhat overkill, but it functions identically to the obsolete gender macros and future-proofs this code
	if(can_butcher(user, O))	//if the animal can be butchered, do so and return. It's likely to be gibbed.
		harvest(user, O)
		return

	if(IS_HELPING(user) && harvest_tool && istype(O, harvest_tool) && stat != DEAD)
		if(world.time > (harvest_recent + harvest_cooldown))
			livestock_harvest(O, user)
			return
		else
			to_chat(user, span_notice("\The [src] can't be [harvest_verb] so soon."))
			return

	if(can_tame(O, user))
		to_chat(user, span_notice("You offer \the [src] \the [O]."))
		if(tame_prob(O, user))
			to_chat(user, span_notice("\The [src] appears to accept \the [O], seemingly calmed."))
			do_tame(O,user)
		else
			fail_tame(O, user)
		return

	return ..()


// Handles the actual harming by a melee weapon.
/mob/living/simple_mob/hit_with_weapon(obj/item/O, mob/living/user, effective_force, hit_zone)
	effective_force = O.force

	//Animals can't be stunned(?)
	if(O.injury_kind == INJURY_PAIN)
		effective_force = 0
	if(supernatural && istype(O,/obj/item/nullrod))
		effective_force *= 2
		purge = 3
	if(O.force <= resistance)
		to_chat(user,span_danger("This weapon is ineffective, it does no damage."))
		return 2 //???

	. = ..()


// Exploding.
/mob/living/simple_mob/ex_act(severity)
	if(is_incorporeal()) // Can't explode shadekin in phase
		return

	if(!blinded)
		flash_eyes()

	var/explosion_shift = factor(BF_EXPLOSION_SHIFT)
	if(explosion_shift)
		severity = CLAMP(severity + explosion_shift, 1, 4)

	severity = round(severity)

	if(severity > 3)
		return

	var/bombdam = 500
	switch (severity)
		if (1.0)
			bombdam = 500
		if (2.0)
			bombdam = 60
		if (3.0)
			bombdam = 30

	injure(INJURY_BLUNT, bombdam * (100 - armor_against(ARMOR_BLAST)) / 100)

	if(bombdam > get_endurance())
		gib()

// Cold stuff.
/mob/living/simple_mob/get_cold_protection()
	. = cold_resist
	. = 1 - . // Invert from 1 = immunity to 0 = immunity.

	// Body factors stack multiplicatively.
	. *= factor(BF_COLD_EXPOSURE)

	// Code that calls this expects 1 = immunity so we need to invert again.
	. = 1 - .
	. = min(., 1.0)

/mob/living/simple_mob/get_heat_protection()
	. = heat_resist
	. = 1 - . // Invert from 1 = immunity to 0 = immunity.

	// Body factors stack multiplicatively.
	. *= factor(BF_HEAT_EXPOSURE)

	// Code that calls this expects 1 = immunity so we need to invert again.
	. = 1 - .
	. = min(., 1.0)

// Electricity
/mob/living/simple_mob/electrocute_act(shock_damage, obj/source, siemens_coeff = 1.0, def_zone = null, stun = 1)
	shock_damage *= siemens_coeff
	if(shock_damage < 1)
		return 0

	receive_shock(shock_damage * (100 - resistance) / 100, source)
	playsound(src, "sparks", 50, 1, -1)

	var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
	s.set_up(5, 1, loc)
	s.start()

/mob/living/simple_mob/get_shock_protection()
	. = shock_resist
	. = 1 - . // Invert from 1 = immunity to 0 = immunity.

	// Body factors stack multiplicatively.
	. *= factor(BF_SIEMENS)

	// Code that calls this expects 1 = immunity so we need to invert again.
	. = 1 - .
	. = min(., 1.0)

// Shot with taser/stunvolver
/mob/living/simple_mob/stun_effect_act(stun_amount, agony_amount, def_zone, used_weapon=null, electric = FALSE)
	if(taser_kill)
		var/stunDam = 0
		var/agonyDam = 0

		if(stun_amount)
			stunDam += stun_amount * 0.5
			injure(INJURY_ELECTRIC, stunDam, null, used_weapon, flags = INJURE_ARMORED)

		if(agony_amount)
			agonyDam += agony_amount * 0.5
			injure(INJURY_ELECTRIC, agonyDam, null, used_weapon, flags = INJURE_ARMORED) // Simple bodies ignore pain; taser_kill mobs take it as a real electrical injury.


// Electromagnetism
/mob/living/simple_mob/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	if(!(biology & BIOLOGY_SYNTHETIC))
		return
	var/endurance_scale = get_endurance()
	// Scaled to endurance: weak mobs always take two direct EMP hits to kill; stronger ones may take more.
	var/static/list/cap_by_severity = list(60, 30, 15, 7)
	var/static/list/share_by_severity = list(0.5, 0.25, 0.125, 0.0625)
	var/band = round(severity)
	if(band >= 1 && band <= length(cap_by_severity))
		deal_damage(DAMAGE_IONIC, min(cap_by_severity[band], endurance_scale * share_by_severity[band]), flags = DAMAGE_PACKET_UNARMORED)

// Water
/mob/living/simple_mob/get_water_protection()
	return water_resist

// "Poison" (aka what reagents would do if we wanted to deal with those).
/mob/living/simple_mob/get_poison_protection()
	return poison_resist

// Armor
/mob/living/simple_mob/injury_armor(kind, zone = null)
	. = armor_factor(kind)
	var/key = injury_armor_key(kind)
	if(key && armor)
		. += armor[key] || 0

// Lightning
/mob/living/simple_mob/lightning_act()
	..()
	// If a non-player simple_mob was struck, inflict huge damage.
	// If the damage is fatal, it is turned to ash.
	if(!client)
		inflict_shock_damage(200) // Mobs that are very beefy or resistant to shock may survive getting struck.
		if(stat == DEAD)
			visible_message(span_critical("\The [src] disintegrates into ash!"))
			ash()
			return // No point deafening something that wont exist.

// Lava
/mob/living/simple_mob/lava_act()
	..()
	// Similar to lightning, the mob is turned to ash if the lava tick was fatal and it isn't a player.
	// Unlike lightning, we don't add an additional damage spike (since lava already hurts a lot).
	if(!client)
		if(stat == DEAD)
			visible_message(span_critical("\The [src] flashes into ash as the lava consumes them!"))
			ash()

// Injections.
/mob/living/simple_mob/can_inject(mob/user, error_msg, target_zone, ignore_thickness)
	if(ignore_thickness)
		return TRUE
	return !thick_armor
