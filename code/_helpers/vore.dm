// Grew a little tired of having to juggle with preference checks
// So instead of having multiple checks all over the code
// Let's get some helper procs so that we don't have to do it ALL OVER

/// Most basic check of them all.
/// Checks if PRED can eat PREY.
/proc/can_vore(mob/living/pred, mob/living/prey, allow_incorporeal = FALSE)
	if(pred == prey)
		return FALSE
	if(!istype(pred) || !istype(prey))
		return FALSE
	if(!vore_consents(/datum/entry/part/req/vore_consent/devourable, pred, prey))
		return FALSE
	if(!is_vore_predator(pred))
		return FALSE
	if(prey.is_incorporeal() || pred.is_incorporeal())
		if(!allow_incorporeal)
			return FALSE
	if(!vore_selected_of(pred))
		return FALSE
	if(!pred.vore_prefs.can_be_afk_pred && (!pred.client || pred.away_from_keyboard))
		return FALSE
	if(!prey.is_dead() && !prey.vore_prefs.can_be_afk_prey && (!prey.client || prey.away_from_keyboard))
		return FALSE
	if(!prey.vore_prefs.allowmobvore && isanimal(pred) && !pred.ckey)
		return FALSE
	return TRUE

/// Basic spont vore check.
/// Checks if both have spont vore enable
/proc/can_spontaneous_vore(mob/living/pred, mob/living/prey, allow_incorporeal = FALSE)
	if(!can_vore(pred, prey, allow_incorporeal))
		return FALSE
	if(!pred.vore_prefs.can_be_drop_pred || !prey.vore_prefs.can_be_drop_prey)
		return FALSE
	return TRUE

/proc/can_stumble_vore(mob/living/pred, mob/living/prey)
	if(!can_spontaneous_vore(pred, prey))
		return FALSE
	if(!pred.vore_prefs.stumble_vore || !prey.vore_prefs.stumble_vore)
		return FALSE
	return TRUE

/proc/can_drop_vore(mob/living/pred, mob/living/prey)
	if(!can_spontaneous_vore(pred, prey))
		return FALSE
	if(!pred.vore_prefs.drop_vore || !prey.vore_prefs.drop_vore)
		return FALSE
	return TRUE

/proc/can_throw_vore(mob/living/pred, mob/living/prey)
	if(!can_spontaneous_vore(pred, prey))
		return FALSE
	if(!pred.vore_prefs.throw_vore || !prey.vore_prefs.throw_vore)
		return FALSE
	return TRUE

/proc/can_food_vore(mob/living/pred, mob/living/prey)
	if(!can_spontaneous_vore(pred, prey))
		return FALSE
	if(!pred.vore_prefs.food_vore || !prey.vore_prefs.food_vore)
		return FALSE
	return TRUE

/proc/can_phase_vore(mob/living/pred, mob/living/prey, allow_incorporeal = FALSE)
	if(!can_spontaneous_vore(pred, prey, allow_incorporeal))
		return FALSE
	if(!pred.vore_prefs.phase_vore || !prey.vore_prefs.phase_vore)
		return FALSE
	return TRUE

/proc/can_slip_vore(mob/living/pred, mob/living/prey)
	if(!can_spontaneous_vore(pred, prey))
		return FALSE
	if(!pred.vore_prefs.slip_vore && !prey.vore_prefs.slip_vore)
		return FALSE
	if(!pred.is_slipping && !prey.is_slipping)
		return FALSE
	if(!cooldown_ready(prey, slip_protect))
		return FALSE
	return TRUE
