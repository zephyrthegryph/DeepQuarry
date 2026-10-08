//Some basic metroid specific mechanics. Lifted from slime code, but gutted all the xenobio taming stuff. Feel free to add it back in, but I recommend making a new specific subset of tamable metroids and leaving the others as wild or soemthing.

/mob/living/simple_mob/metroid/juvenile
	desc = "This metroid should not be spawned. Yell at your local dev or event manager."
	layer = MOB_LAYER + 1 // Need them on top of other mobs or it looks weird when consuming something.
	max_nutrition = 1000
	var/is_queen = FALSE // When the metroid is a queen, it should just be shitting out babies. Found in metAI.dm and in metTypes for the queen.
	var/endurance_adult = 200
	var/power_charge = 0 // Disarm attacks can shock someone if high/lucky enough.
	var/mob/living/victim = null // the person the metroid is currently feeding on
	var/consuming = FALSE // whether it is latched on and feeding (tracked, so a change redraws)
	var/amount_grown = 0 // controls how long the metroid has been overfed, if 10, grows or reproduces
	var/number = 0 // This is used to make the metroid semi-unique for indentification.
	var/harmless = FALSE // Set to true when pacified. Makes the metroid harmless, not get hungry, and not be able to grow/reproduce.

TRACKED(/mob/living/simple_mob/metroid/juvenile, consuming)

// it lets go of its victim.
/mob/living/simple_mob/metroid/juvenile/on_destroy(force)
	if(victim)
		stop_consumption() // Unbuckle us from our victim.
	..()

/mob/living/simple_mob/metroid/juvenile/life_special_due()
	return TRUE

/mob/living/simple_mob/metroid/juvenile/life_special(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		if(src.victim)
			src.handle_consumption()

	..()

/mob/living/simple_mob/metroid/juvenile/examine(mob/user)
	. = ..()
	if(stat == DEAD)
		. += "It appears to be dead."
	else if(incapacitated(INCAPACITATION_DISABLED))
		. += "It appears to be incapacitated."
	else if(harmless)
		. += "It appears to have been pacified."

/mob/living/simple_mob/metroid/juvenile/verb/evolve()
	set category = VERB_CAT_SLIME
	set desc = "This will let you advance to next form."

	if(stat)
		to_chat(src, span_warning("I must be conscious to do this..."))
		return

	if(is_queen)
		status_set(STAT_PARALYZED, 7998)
		play_sfx(src, SFX_METROID_METROIDGROW)
		act_message(src, null, null, MSG_OTHERS(span_notice("%U% begins to lay an egg.")))
		after(src, 5 SECONDS, PROC_REF(lay_egg))
		return

	if(nutrition >= evo_point && !src?.buckled_to() && vore_fullness == 0 && !victim)
		if(next == "/mob/living/simple_mob/metroid/juvenile/queen" && GLOB.queen_amount > 0)
			to_chat(src, span_warning("There is already a queen."))
			return
		play_sfx(src, SFX_METROID_METROIDGROW)
		status_set(STAT_PARALYZED, 7998)
		after(src, 5 SECONDS, PROC_REF(expand_troid))

	if(nutrition >= evo_limit && (src?.buckled_to() || vore_fullness == 1)) //spit dat crap out if nutrition gets too high!
		release_vore_contents()
		rel_clear(src, nameof(prey_excludes))
		stop_consumption()

	else
		to_chat(src, span_warning("I am not ready to evolve yet..."))

/mob/living/simple_mob/metroid/juvenile/proc/expand_troid()
	if(loc?.release_refusal(src))
		return
	var/mob/living/L
	L = new next(get_turf(src)) //Next is a variable defined by metTypes.dm that just points to the next metroid in the evolutionary stage.
	if(mind)
		src.mind.transfer_to(L)
	act_message(src, null, null, MSG_OTHERS(span_warning("%U% suddenly evolves!")))
	global.consume(src)

// Code for metroids attacking other things.
// metroid attacks change based on intent.
/mob/living/simple_mob/metroid/juvenile/apply_attack(mob/living/L, damage_to_do, stance = I_HURT)
	if(istype(L))
		switch(stance)
			if(I_HELP) // This shouldn't happen but just in case.
				return FALSE

			if(I_DISARM)
				var/stun_power = between(0, power_charge + rand(0, 3), 10)

				if(ishuman(L))
					var/mob/living/carbon/human/H = L
					stun_power *= max(H.species.siemens_coefficient, 0)

				if(prob(stun_power * 10)) // Try an electric shock.
					power_charge = max(0, power_charge - 3)
					act_message(L, src, MSG_SELF(span_danger("%T% has shocked you!")), MSG_OTHERS(span_danger("%T% has shocked %U%!")))
					play_sfx(src, SFX_WEAPONS_EGLOVES, 1.5, extrarange = 0)
					L.status_at_least(STAT_WEAKENED, 4)
					L.status_at_least(STAT_STUNNED, 4)
					do_attack_animation(L)
					if(L?.buckled_to())
						var/atom/movable/_tmp_buck_23 = L?.buckled_to()
						_tmp_buck_23.unbuckle_mob() // To prevent an exploit where being src?.buckled_to() prevents metroids from jumping on you.
					L.status_at_least(STAT_STUTTERING, stun_power)

					fx_sparks(L, 5)

					if(prob(stun_power * 10) && stun_power >= 8)
						L.injure(INJURY_ELECTRIC, power_charge * rand(1, 2), source = src)
					return FALSE

				else if(prob(20)) // Try to do a regular disarm attack.
					act_message(L, src, MSG_SELF(span_danger("%T% has pounced at you!")), MSG_OTHERS(span_danger("%T% has pounced at %U%!")))
					play_sfx(src, SFX_WEAPONS_THUDSWOOSH, 1.5, extrarange = 0)
					L.status_at_least(STAT_WEAKENED, 2)
					do_attack_animation(L)
					if(L?.buckled_to())
						var/atom/movable/_tmp_buck_24 = L?.buckled_to()
						_tmp_buck_24.unbuckle_mob() // To prevent an exploit where being src?.buckled_to() prevents metroids from jumping on you.
					return FALSE

				else // Failed to do anything this time.
					act_message(L, src, MSG_SELF(span_warning("%T% has tried to pounce at you!")), MSG_OTHERS(span_warning("%T% has tried to pounce at %U%!")))
					play_sfx(src, SFX_WEAPONS_PUNCHMISS, 3, extrarange = 0)
					do_attack_animation(L)
					return FALSE

			if(I_GRAB)
				start_consuming(L)
				return FALSE

			if(I_HURT)
				return ..() // Regular stuff.
	else
		return ..() // Do the regular stuff if we're hitting a window/mech/etc.

/mob/living/simple_mob/metroid/juvenile/apply_melee_effects(mob/living/L, stance = I_HURT)
	if(istype(L) && stance == I_HURT)
		// Feed off of their flesh, if able.
		consume(L, 5)

//Code to remove metroid from someone
CAPABILITIES(/mob/living/simple_mob/metroid/juvenile)
	op("metroid_juvenile_hand", hand(), ungated(), then(PROC_REF(metroid_juvenile_interaction_hand)))

/// Old attack_hand: wrestle it off its victim.
/mob/living/simple_mob/metroid/juvenile/proc/metroid_juvenile_interaction_hand(datum/act/op/A)
	var/mob/living/L = A.actor
	. = OP_OK
	if(victim) // Are we eating someone?
		var/fail_odds = 30
		if(victim == L) // Harder to get the metroid off if it's you that is being eatten.
			fail_odds = 60

		if(prob(fail_odds))
			visible_message(span_warning("\The [L] attempts to wrestle \the [name] off!"))
			play_sfx(loc, SFX_WEAPONS_PUNCHMISS)

		else
			visible_message(span_warning("\The [L] manages to wrestle \the [name] off!"))
			play_sfx(loc, SFX_WEAPONS_THUDSWOOSH)
			stop_consumption()
			step_away(src, L)

	else
		return OP_DECLINE

/mob/living/simple_mob/metroid/juvenile/proc/lay_egg()
	new /obj/effect/metroid/egg(loc, src)
	adjust_nutrition(-500)
	status_set(STAT_PARALYZED, 0)

