// Seizures: a whole-body condition that floors and blanks the patient for a short while.
//
// Who seizes is the body stat STAT_SEIZURE_PRONENESS (SUM, 0 by default; a drug that lowers the threshold gives
// `factors = alist(STAT_SEIZURE_PRONENESS = 5)` mild / 10 strong). The threshold a shock must reach is
// SEIZURE_BASE_THRESHOLD - proneness * SEIZURE_PRONENESS_SCALE (/mob/living/proc/seizure_threshold()), so a body with no proneness
// never seizes from a shock. A shock (an INJURY_ELECTRIC injury that lands) at or above the threshold seizes the patient with a
// chance of proneness * SEIZURE_CHANCE_PER_PRONENESS percent.
//
// Drugs make it a side effect by subtyping, like the overdoses (the base type has no caused_by_chems, so nothing spawns it on its own):
//   /datum/affliction/seizure/<drug>
//       caused_by_chems = list(REAGENT_ID_X = 10)
//       caused_by_chems_organ = O_BRAIN
// A chem-caused seizure is re-spawned while the chem stays above its threshold, so it recurs in bouts until the chem clears;
// anticonvulsants (TREAT_ANTICONVULSANT) end a bout early. Give a subtype `progression_rate = 0` to hold it for as long as the chem is present.

/datum/affliction/seizure
	name = "seizure"
	category = "Brain"
	subcategory = "Seizure"
	clinical_description = "A burst of uncontrolled electrical activity in the brain. The patient convulses, loses awareness and cannot stand until it passes; it ends on its own within a minute or two, and anticonvulsants end it sooner."
	systemic_singleton = TRUE
	initial_severity = 100
	// Resolves by itself: the severity drains, quickest while it is high.
	progression_rate = -6
	treated_by = list(TREAT_ANTICONVULSANT = 3)
	// Passes the patient out once the severity is above about 40.
	consciousness_at_max = 160
	symptom_pool = list(
		/datum/affliction_symptom/convulsions  = 100,
		/datum/affliction_symptom/unresponsive = 80,
		/datum/affliction_symptom/jittery      = 60,
	)
	min_symptoms = 2
	max_symptoms = 3
	factors = alist(STAT_MOTOR_CONTROL = 0.3, STAT_ACCURACY = -50, STAT_SLOWDOWN = 2, STAT_HEART_RATE = 20)

/datum/affliction/seizure/on_added()
	. = ..()
	if(owner)
		to_chat(owner, span_danger("You have a seizure!"))
		owner.visible_message(span_danger("[owner] starts having a seizure!"))
		log_game("SEIZURE: [key_name(owner)] started a seizure.")


// --- The trigger: a shock on a body prone to seizures --------------------------------------------------------------

/// The shock (an injury's applied amount) a body needs to take to seize: lower the more prone it is.
/mob/living/proc/seizure_threshold()
	return max(0, SEIZURE_BASE_THRESHOLD - seizure_proneness * SEIZURE_PRONENESS_SCALE)

/// A shock of `amount` landed. Seizes the patient when they are prone and it reaches the threshold; returns TRUE when it did.
/mob/living/proc/seizure_from_shock(amount)
	if(!body || stat == DEAD || seizure_proneness <= 0 || amount < SEIZURE_MIN_SHOCK)
		return FALSE
	var/threshold = seizure_threshold()
	if(amount < threshold)
		return FALSE
	var/chance = min(100, seizure_proneness * SEIZURE_CHANCE_PER_PRONENESS)
	if(!prob(chance))
		return FALSE
	if(GLOB.chem_trace)
		log_world("CHEM: shock of [amount] seizes [src] (proneness [seizure_proneness], threshold [threshold], chance [chance]%)")
	return !!body.afflict(/datum/affliction/seizure)

CAPABILITIES_PART(/mob/living/carbon, seizure)
	on_notice(/datum/notice/living_injured, then(PROC_REF(seizure_notice_injured)))

/// An injury landed: a shock may seize a prone body.
/mob/living/carbon/proc/seizure_notice_injured(datum/act/notice/A)
	var/datum/notice/living_injured/event = A
	if(event.kind != INJURY_ELECTRIC || event.applied <= 0)
		return
	seizure_from_shock(event.applied)
