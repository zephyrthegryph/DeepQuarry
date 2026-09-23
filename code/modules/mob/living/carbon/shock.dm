/mob/living/var/traumatic_shock = 0
/mob/living/carbon/var/shock_stage = 0

// How much pain the mob is in right now. The body computes pain once per
// tick (afflictions + wound load - analgesia, scaled by species trauma_mod);
// traumatic_shock mirrors it for the shock-stage / feral / HUD consumers.
/mob/living/carbon/proc/updateshock()
	traumatic_shock = current_pain()
	return traumatic_shock

