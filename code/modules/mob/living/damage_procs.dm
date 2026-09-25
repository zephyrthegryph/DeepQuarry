
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
			status_at_least(EFFECT_STUNNED, effect * blocked)
		if(WEAKEN)
			status_at_least(EFFECT_WEAKENED, effect * blocked)
		if(PARALYZE)
			status_at_least(EFFECT_PARALYZED, effect * blocked)
		if(AGONY)
			injure(INJURY_PAIN, effect * blocked) // Useful for objects that cause "subdual" damage. PAIN!
		if(IRRADIATE)
			var/rad_protection = injury_armor(INJURY_RADIATION, null)
			rad_protection = (100-rad_protection)/100
			if(!(SEND_SIGNAL(src, COMSIG_LIVING_IRRADIATE_EFFECT, effect, effecttype, blocked, check_protection, rad_protection) & COMPONENT_BLOCK_IRRADIATION))
				radiation += max((effect * rad_protection), 0)
		if(STUTTER)
			if(!status_immune(EFFECT_STUNNED)) // stun is usually associated with stutter
				status_at_least(EFFECT_STUTTERING, (effect * blocked))
		if(EYE_BLUR)
			status_at_least(EFFECT_BLURRY, (effect * blocked))
		if(DROWSY)
			status_at_least(EFFECT_DROWSY, (effect * blocked))
	return 1


/mob/living/proc/apply_effects(stun = 0, weaken = 0, paralyze = 0, irradiate = 0, stutter = 0, eyeblur = 0, drowsy = 0, agony = 0, blocked = 0, ignite = 0, flammable = 0)
	if(SEND_SIGNAL(src, COMSIG_TAKING_APPLY_EFFECT) & COMSIG_CANCEL_EFFECT)
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
