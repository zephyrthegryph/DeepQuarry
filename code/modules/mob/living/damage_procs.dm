
/// Apply a status effect (stun, weaken, agony, radiation, ...). Harm is
/// routed through injure(); see doc/body_architecture.md.
/mob/living/proc/apply_effect(effect = 0,effecttype = STUN, blocked = 0, check_protection = 1)
	if(GLOB.Debug2)
		log_world("## DEBUG: apply_effect() was called.  The type of effect is [effecttype].  Blocked by [blocked].")
	if(!effect || (blocked >= 100))
		return 0
	blocked = (100-blocked)/100

	switch(effecttype)
		if(STUN)
			status_at_least(STAT_STUNNED, effect * blocked)
		if(WEAKEN)
			status_at_least(STAT_WEAKENED, effect * blocked)
		if(PARALYZE)
			status_at_least(STAT_PARALYZED, effect * blocked)
		if(AGONY)
			injure(INJURY_PAIN, effect * blocked) // Useful for objects that cause "subdual" damage. PAIN!
		if(IRRADIATE)
			// P2-F7: check_protection is honoured: callers that pass 0 (DNA scanners and
			// injectors dosing from inside the suit) skip the radiation armour.
			var/rad_protection = check_protection ? radiation_protection_fraction() : 1
			var/datum/act/irradiate/dose = ACT_TRY(src, irradiate, effect, blocked, check_protection, rad_protection)
			if(dose)
				act_done(dose)
				add_radiation(effect * rad_protection)
		if(STUTTER)
			if(!status_immune(STAT_STUNNED)) // stun is usually associated with stutter
				status_at_least(STAT_STUTTERING, (effect * blocked))
		if(EYE_BLUR)
			status_at_least(STAT_BLURRY, (effect * blocked))
		if(DROWSY)
			status_at_least(STAT_DROWSY, (effect * blocked))
	return 1


/// Fraction of incoming radiation that gets through this mob's radiation armour (1 = none stops it).
/mob/living/proc/radiation_protection_fraction()
	return (100 - injury_armor(INJURY_RADIATION, null)) / 100

/mob/living/proc/apply_effects(stun = 0, weaken = 0, paralyze = 0, irradiate = 0, stutter = 0, eyeblur = 0, drowsy = 0, agony = 0, blocked = 0, ignite = 0, flammable = 0)
	if(in_godmode(src))
		return 0	// Cancelled by a component
	if(blocked >= 100)
		return 0
	if(stun)		apply_effect(stun, STUN, blocked)
	if(weaken)		apply_effect(weaken, WEAKEN, blocked)
	if(paralyze)	apply_effect(paralyze, PARALYZE, blocked)
	if(irradiate)	apply_effect(irradiate, IRRADIATE, blocked)
	if(stutter)		apply_effect(stutter, STUTTER, blocked)
	if(eyeblur)		apply_effect(eyeblur, EYE_BLUR, blocked)
	if(drowsy)		apply_effect(drowsy, DROWSY, blocked)
	if(agony)		apply_effect(agony, AGONY, blocked)
	if(flammable)	adjust_fire_stacks(flammable)
	if(ignite)
		adjust_fire_stacks(ignite)
		ignite_mob()
	return 1
