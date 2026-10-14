/mob/living/var/traumatic_shock = 0
/mob/living/carbon/var/shock_stage = 0

// How much pain the mob is in right now. The body computes pain once per
// tick (afflictions + wound load - analgesia, scaled by species trauma_mod);
// traumatic_shock mirrors it for the shock-stage / feral / HUD consumers.
/mob/living/carbon/proc/updateshock()
	traumatic_shock = current_pain()
	return traumatic_shock


/// Maximum traumatic shock stage the shock system tracks.
#define SHOCK_STAGE_MAX 160

/// The one writer of shock_stage outside the shock life stage. Adds `amount`
/// (negative to relieve), clamps to [0, SHOCK_STAGE_MAX] and wakes the shock stage.
/// `source` is a short reason for debugging/tracing. Returns the new stage.
/mob/living/carbon/proc/adjust_shock(amount, source)
	if(!amount)
		return shock_stage
	return set_shock(shock_stage + amount, source)

/// Sets shock_stage absolutely (clamped) and wakes the shock stage.
/mob/living/carbon/proc/set_shock(value, source)
	var/new_stage = clamp(value, 0, SHOCK_STAGE_MAX)
	if(new_stage == shock_stage)
		return shock_stage
	shock_stage = new_stage
	PUBLISH_CHANGE(src, MOB_KEY_HEALTH)
	return shock_stage

#undef SHOCK_STAGE_MAX
