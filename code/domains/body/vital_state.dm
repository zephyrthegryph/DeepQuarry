// Vital-state predicates: the one set of answers to "is it alive / down / dying / dead?".
//
//   is_alive()        stat != DEAD                                   (/mob, mob.dm)
//   is_dead()         stat == DEAD                                   (/mob, mob.dm)
//   is_critical()     down from injury: UNCONSCIOUS + TRAIT_CRITICAL_CONDITION   (injury.dm)
//   is_dying()        alive, but the body's injuries are lethal or vitality is spent
//   is_brain_dead()   the brain is past saving; only a resleeve helps  (living.dm, human)
//   vital_band()      one VITAL_BAND_* summarising all of the above plus vitality()
//
// body.is_lethal() is the damage question underneath ("would these injuries kill?"); it is
// not a stat predicate. Medical, body, surgery and diagnosis code asks these procs instead of
// reading `stat` or comparing vitality() against its own thresholds.

/// Alive, but not for long: the body's injuries are lethal (death applies on the next status
/// check) or vitality is spent while down.
/mob/living/proc/is_dying()
	if(stat == DEAD)
		return FALSE
	if(body?.is_lethal())
		return TRUE
	return is_critical() && vitality() <= 0

/// The named vitality band (VITAL_BAND_*), worst first.
/mob/living/proc/vital_band()
	if(stat == DEAD)
		return VITAL_BAND_DEAD
	if(is_dying())
		return VITAL_BAND_DYING
	if(is_critical())
		return VITAL_BAND_CRITICAL
	var/vitality = vitality()
	if(vitality <= VITALITY_SERIOUS)
		return VITAL_BAND_SERIOUS
	if(vitality <= VITALITY_HURT)
		return VITAL_BAND_HURT
	return VITAL_BAND_HEALTHY

/// Human-readable band name, for logs and debug readouts.
/proc/vital_band_name(band)
	switch(band)
		if(VITAL_BAND_DEAD)
			return "dead"
		if(VITAL_BAND_DYING)
			return "dying"
		if(VITAL_BAND_CRITICAL)
			return "critical"
		if(VITAL_BAND_SERIOUS)
			return "serious"
		if(VITAL_BAND_HURT)
			return "hurt"
		if(VITAL_BAND_HEALTHY)
			return "healthy"
	return "unknown"
