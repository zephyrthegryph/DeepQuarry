// Vitals contract (diag <-> physio). Placeholder body-level vitals queries
// derived from what exists today; the physiology slice owns the real
// implementations and replaces this file at merge.
//
// Every query returns null when the body plan has no such system.
//   ventilation()      0..1 fraction of normal breathing
//   oxygenation()      SpO2, 0..100
//   perfusion()        0..1 fraction of normal circulation
//   oxygen_debt()      accumulated oxygen debt (0 = none)
//   heart_rate()       beats per minute
//   blood_pressure()   list(systolic, diastolic), or null
//   respiratory_rate() breaths per minute

/datum/body/proc/ventilation()
	return null

/datum/body/proc/oxygenation()
	return null

/datum/body/proc/perfusion()
	return null

/datum/body/proc/oxygen_debt()
	return null

/datum/body/proc/heart_rate()
	return null

/datum/body/proc/blood_pressure()
	return null

/datum/body/proc/respiratory_rate()
	return null

/datum/body/humanoid/ventilation()
	var/mob/living/carbon/human/H = owner
	if(!H.should_have_organ(O_LUNGS))
		return null
	return (H.stat == DEAD || H.breath_blocked()) ? 0 : 1

/datum/body/humanoid/oxygenation()
	var/mob/living/carbon/human/H = owner
	if(!H.should_have_organ(O_LUNGS))
		return null
	return H.get_o2_sat_reading()

/datum/body/humanoid/perfusion()
	var/mob/living/carbon/human/H = owner
	if(!H.should_have_organ(O_HEART))
		return null
	return (H.stat != DEAD && H.has_cardiac_output()) ? 1 : 0

/datum/body/humanoid/oxygen_debt()
	var/saturation = oxygenation()
	if(isnull(saturation))
		return null
	return max(0, 95 - saturation)

/datum/body/humanoid/heart_rate()
	var/mob/living/carbon/human/H = owner
	if(!H.should_have_organ(O_HEART))
		return null
	return H.get_pulse_reading_bpm()

/datum/body/humanoid/blood_pressure()
	var/mob/living/carbon/human/H = owner
	if(!H.should_have_organ(O_HEART))
		return null
	return H.get_bp_reading() || list(0, 0)

/datum/body/humanoid/respiratory_rate()
	var/mob/living/carbon/human/H = owner
	if(!H.should_have_organ(O_LUNGS))
		return null
	return H.get_respiratory_rate()
