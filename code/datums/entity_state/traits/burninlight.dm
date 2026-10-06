/datum/trait_state/burninlight
	// This is a merge of the old shadow species light burning life code, and Zaddat's environment_effects() proc.
	// It handles both cases, but shadows behave more like Zaddat do now. By default this code follows Zaddat damage with no healing.
	var/threshold = 0.2 // percent from 0 to 1
	// Damage or healing per life tick
	var/damage_rate = 1.25
	var/heal_rate = 0

/datum/trait_state/burninlight/shadow
	threshold = 0.15
	damage_rate = 1
	heal_rate = 1

/datum/trait_state/burninlight/life_tick()
	if(QDELETED(owner))
		return
	if(owner.is_incorporeal())
		return
	if(!isturf(owner.loc))
		return

	// P2-D7: the same light sample photosynthesis reads.
	var/light_amount = owner.skin_light_level()

	// Apply damage if beyond the minimum light threshold, actually makes zaddat SLIGHTLY more forgiving!
	if(light_amount > 0 && light_amount > threshold) // Checks light_amount, as threshold of 0 can pass 0s to the damage procs otherwise.
		if(damage_rate > 0)
			if(ishuman(owner))
				var/mob/living/carbon/human/H = owner
				var/damageable = H.get_damageable_organs()
				var/covered = H.get_coverage()
				for(var/K in damageable)
					if(!(K in covered))
						H.injure(INJURY_BURN, light_amount * damage_rate, K, flags = INJURE_SILENT)
			else
				owner.injure(INJURY_BLUNT, light_amount * damage_rate, flags = INJURE_SILENT)
				owner.injure(INJURY_BURN, light_amount * damage_rate, flags = INJURE_SILENT)

	// heal in the dark, if possible
	else if(heal_rate > 0)
		owner.mend(TREAT_TISSUE_REPAIR, heal_rate)
		owner.mend(TREAT_BURN_CARE, heal_rate)

/// Trait system: light burns.
/// One Life step per cycle while attached (doc/rewrite/om_retirement.md L1).
/datum/trait_state/burninlight/life_steps()
	return list(seq_step(PROC_REF(life_tick), after = list(LIFE_INPUT, "life_type_pre"), key = "life_trait_burninlight", when = list("placed", "!in_stasis", "alive")))
