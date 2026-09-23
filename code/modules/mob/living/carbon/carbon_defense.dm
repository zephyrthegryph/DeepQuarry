//Called when the mob is hit with an item in combat.
/mob/living/carbon/resolve_item_attack(obj/item/I, mob/living/user, target_zone)
	if(check_neckgrab_attack(I, user, target_zone))
		return null
	return ..()

/mob/living/carbon/standard_weapon_hit_effects(obj/item/I, mob/living/user, effective_force, blocked, hit_zone)
	if(!effective_force || blocked >= 100)
		return 0

	// The harm goes through injure(), whose armour stage can also turn the edge.
	receive_weapon_hit(I, user, effective_force, zone = hit_zone, silent = FALSE)

	//Melee weapon embedded object code.
	if (I && I.obj_damage_type() == BRUTE && !I.anchored && !is_robot_module(I) && I.embed_chance > 0)
		var/weapon_sharp = is_sharp(I)
		var/hit_embed_chance = I.embed_chance
		if(prob(blocked)) // Armour that turns the edge also keeps the blade from lodging.
			weapon_sharp = FALSE
			hit_embed_chance = I.force/(I.w_class*3)
		var/damage = effective_force
		if (blocked)
			damage *= (100 - blocked)/100
			hit_embed_chance *= (100 - blocked)/100

		//blunt objects should really not be embedding in things unless a huge amount of force is involved
		var/embed_threshold = weapon_sharp? 5*I.w_class : 15*I.w_class

		if(damage > embed_threshold && prob(hit_embed_chance))
			src.embed(I, hit_zone)

	return 1

// Attacking someone with a weapon while they are neck-grabbed
/mob/living/carbon/proc/check_neckgrab_attack(obj/item/W, mob/user, hit_zone)
	if(IS_HARMING(user))
		for(var/obj/item/grab/G in src.grabbed_by)
			if(G.assailant == user)
				if(G.state >= GRAB_AGGRESSIVE)
					if(hit_zone == BP_TORSO && shank_attack(W, G, user))
						return 1
				if(G.state >= GRAB_NECK)
					if(hit_zone == BP_HEAD && attack_throat(W, G, user, hit_zone))
						return 1
	return 0


// Knifing
/mob/living/carbon/proc/attack_throat(obj/item/W, obj/item/grab/G, mob/user)

	if(!W.edge || !W.force || W.obj_damage_type() != BRUTE)
		return 0 //unsuitable weapon

	user.visible_message(span_danger("\The [user] begins to slit [src]'s throat with \the [W]!"))

	user.next_move = world.time + 20 //also should prevent user from triggering this repeatedly
	if(!do_after(user, 2 SECONDS, target = src))
		return 0
	if(!(G && G.assailant == user && G.affecting == src)) //check that we still have a grab
		return 0

	var/damage_mod = 1
	//presumably, if they are wearing a helmet that stops pressure effects, then it probably covers the throat as well
	var/obj/item/clothing/head/helmet = get_equipped_item(slot_head)
	if(istype(helmet) && (helmet.body_parts_covered & HEAD) && (helmet.min_pressure_protection != null)) // Both min- and max_pressure_protection must be set for it to function at all, so we can just check that one is set.
		//we don't do an armor_check here because this is not an impact effect like a weapon swung with momentum, that either penetrates or glances off.
		damage_mod = 1.0 - (helmet.armor["melee"]/100)

	var/total_damage = 0
	for(var/i in 1 to 3)
		var/damage = min(W.force*1.5, 20)*damage_mod
		receive_weapon_hit(W, user, damage, zone = BP_HEAD, silent = FALSE, armored = FALSE)
		total_damage += damage

	// Blood floods the cut airway: a deep enough cut closes it.
	var/aspirated = total_damage >= 40 ? 60 : total_damage
	if(aspirated)
		body?.afflict(/datum/affliction/airway_obstruction, null, aspirated)

	if(total_damage)
		if(aspirated >= 40)
			user.visible_message(span_danger("\The [user] slit [src]'s throat open with \the [W]!"))
		else
			user.visible_message(span_danger("\The [user] cut [src]'s neck with \the [W]!"))

		if(W.hitsound)
			playsound(src, W.hitsound, 50, 1, -1)

	G.last_action = world.time
	flick(G.hud.icon_state, G.hud)

	add_attack_logs(user,src,"Knifed (throat slit)")

	return 1

/mob/living/carbon/proc/shank_attack(obj/item/W, obj/item/grab/G, mob/user, hit_zone)

	if(!W.sharp || !W.force || W.obj_damage_type() != BRUTE)
		return 0 //unsuitable weapon

	user.visible_message(span_danger("\The [user] plunges \the [W] into \the [src]!"))

	var/damage = shank_armor_helper(W, G, user)
	receive_weapon_hit(W, user, damage, zone = BP_TORSO, silent = FALSE, armored = FALSE)

	if(W.hitsound)
		playsound(src, W.hitsound, 50, 1, -1)

	add_attack_logs(user,src,"Knifed (shanked)")

	return 1

/mob/living/carbon/proc/shank_armor_helper(obj/item/W, obj/item/grab/G, mob/user)
	var/damage = W.force
	var/damage_mod = 1
	if(W.edge)
		damage = damage * 1.25 //small damage bonus for having sharp and edge

	var/obj/item/clothing/suit/worn_suit
	var/obj/item/clothing/under/worn_under
	var/worn_suit_armor
	var/worn_under_armor

	//if(slot_wear_suit)
	if(get_equipped_item(slot_wear_suit))
		worn_suit = get_equipped_item(slot_wear_suit)
		//worn_suit = get_equipped_item(slot_wear_suit)
		worn_suit_armor = worn_suit.armor["melee"]
	else
		worn_suit_armor = 0

	//if(slot_w_uniform)
	if(get_equipped_item(slot_w_uniform))
		worn_under = get_equipped_item(slot_w_uniform)
		//worn_under_armor = slot_w_uniform.armor["melee"]
		worn_under_armor = worn_under.armor["melee"]
	else
		worn_under_armor = 0

	if(worn_under_armor > worn_suit_armor)
		damage_mod = 1 - (worn_under_armor/100)
	else
		damage_mod = 1 - (worn_suit_armor/100)

	damage = damage * damage_mod

	return damage

/// Carbons react to every injury after it lands (pain noises; humans add
/// suit breaches, damage overlays and husking — see on_injured()).
/mob/living/carbon/injure(kind, amount, zone = null, atom/source = null, armor_pen = 0, affliction = null, flags = NONE)
	. = ..()
	if(.)
		on_injured(kind, ., zone, source, flags)

/// Post-injury reactions. `amount` is what the body actually received.
/mob/living/carbon/proc/on_injured(kind, amount, zone, atom/source, flags)
	if(flags & INJURE_SILENT)
		return
	if(!(can_feel_pain() || (isSynthetic() && synth_cosmetic_pain)))
		return
	injury_pain_noise(amount)

/// Pain emotes scaled by the size of the hit and the species' pain sensitivity:
/// 50 incoming at 0.6 sensitivity is prob 30 * 1.5, etc.
/mob/living/carbon/proc/injury_pain_noise(amount)
	if(isbelly(loc)) // No pain noises inside bellies.
		return
	var/pain_noise = species ? amount * incoming_injury_factor(INJURY_CATEGORY_PAIN) : amount * rand(0.5, 1.5)
	switch(amount)
		if(-INFINITY to 0)
			return
		if(0 to 25)
			if(prob(pain_noise))
				emote("pain")
		if(25 to 50)
			if(prob(pain_noise * 1.5))
				emote("pain")
		if(50 to INFINITY)
			if(prob(pain_noise * 3)) // More likely, most severe damage.
				emote("pain")
