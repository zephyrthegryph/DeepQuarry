// Code for slimes attacking other things.

// Slime attacks change based on intent.
/mob/living/simple_mob/slime/xenobio/apply_attack(mob/living/L, damage_to_do, stance = I_HURT)
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
						var/atom/movable/_tmp_buck_25 = L?.buckled_to()
						_tmp_buck_25.unbuckle_mob() // To prevent an exploit where being buckled prevents slimes from jumping on you.
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
						var/atom/movable/_tmp_buck_26 = L?.buckled_to()
						_tmp_buck_26.unbuckle_mob() // To prevent an exploit where being buckled prevents slimes from jumping on you.
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

/mob/living/simple_mob/slime/xenobio/apply_melee_effects(mob/living/L, stance = I_HURT)
	if(istype(L) && stance == I_HURT)
		// Pump them full of toxins, if able.
		if(L.reagents && L.can_inject() && reagent_injected)
			L.reagents.add_reagent(reagent_injected, injection_amount)

		// Feed off of their flesh, if able.
		consume(L, 5)


/mob/living/simple_mob/slime/xenobio/action_alternate(atom/movable/A)
	if(isliving(A) && Adjacent(A))
		animal_nom(A)
	else
		..()
