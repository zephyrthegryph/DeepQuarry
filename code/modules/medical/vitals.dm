// Vital-sign readings.
//
// Each instrument calls one of these procs to get a raw numeric value
// for the patient. The values are deliberately *uninterpreted* — the
// scanner doesn't say "fever," it says "39.4°C." Players have to learn
// what's normal and what's worrying.
//
// Baselines:
//   pulse        : 70 bpm (range 0..220+)
//   temperature  : 37.0 °C (range body-frozen .. 42+)
//   bp_systolic  : 120 mmHg
//   bp_diastolic : 80 mmHg
//   o2_sat       : 99 % (range 0..100)
//
// Conditions modulate these via their `vital_effects` list, keyed by:
//   "pulse_mod"     bpm offset
//   "temp_mod_c"    celsius offset
//   "bp_sys_mod"    systolic offset
//   "bp_dia_mod"    diastolic offset
//   "o2_sat_mod"    saturation %% offset
// Effects are summed across all of the mob's active conditions.
//
// We layer condition effects on top of whatever vitals the upstream
// mob already tracks (BYOND `bodytemperature` in kelvin, heart pulse
// enum). For pulse and BP we synthesize from the heart organ's enum
// rather than tracking a separate bpm var, so existing code that reads
// the enum still works.

/// Sum a single vital_effects key across the mob's active conditions.
/// Each condition's contribution comes from its per-subtype
/// `get_vital_effects()` proc (which returns a shared static list).
/mob/living/carbon/human/proc/_vital_modifier(key)
	. = 0
	for(var/datum/medical_issue/condition/C in get_all_conditions())
		var/list/ve = C.get_vital_effects()
		if(ve && ve[key])
			. += ve[key]

// Per-reading jitter. Real instruments don't return identical numbers
// on consecutive checks; we apply a small random offset so repeated
// measurements feel realistic and the doctor can't lock onto a precise
// number. Helper returns a uniform random in [-amount, +amount].
/proc/_dq_jitter(amount)
	return (rand() * 2 - 1) * amount

/mob/living/carbon/human/proc/get_temperature_reading_c()
	// bodytemperature is in kelvin upstream; convert to celsius for the
	// instrument readout. T0C = 273.15 (defined in upstream defines).
	var/celsius = bodytemperature - T0C
	celsius += _vital_modifier("temp_mod_c")
	celsius += _dq_jitter(0.1)
	return round(celsius * 10) / 10  // one decimal place

/mob/living/carbon/human/proc/get_pulse_reading_bpm()
	// Map the upstream pulse enum to a bpm baseline, then offset by
	// compensatory tachycardia from blood loss and per-condition mods.
	var/obj/item/organ/internal/heart/H = internal_organs_by_name?[O_HEART]
	if(!H || H.is_broken())
		return 0
	var/baseline
	switch(H.standard_pulse_level)
		if(PULSE_NONE)    baseline = 0
		if(PULSE_SLOW)    baseline = 50
		if(PULSE_NORM)    baseline = 75
		if(PULSE_FAST)    baseline = 105
		if(PULSE_2FAST)   baseline = 135
		if(PULSE_THREADY) baseline = 150
		else              baseline = 75
	if(baseline == 0)
		return 0
	// Compensatory tachycardia: the heart speeds up as blood volume
	// drops. Tracks the upstream "blood_level_*" thresholds. Conditions
	// that *cause* bleeding (internal_hemorrhage, lacerated_artery)
	// don't need a `pulse_mod = +N` — the bleed itself shows up here
	// through the patient's actual blood volume.
	if(species && vessel)
		var/blood_now = vessel.get_reagent_amount(REAGENT_ID_BLOOD)
		if(species.blood_volume > 0 && blood_now < species.blood_volume)
			var/lost = (species.blood_volume - blood_now) / species.blood_volume
			baseline += round(lost * 80)  // up to +80 bpm at full exsanguination
	baseline += _vital_modifier("pulse_mod")
	baseline += _dq_jitter(3)
	return max(0, round(baseline))

/mob/living/carbon/human/proc/get_bp_reading()
	// Synthesize systolic / diastolic. Defaults: 120/80. Blood volume
	// has a strong effect; we mirror the upstream "blood_level_*"
	// thresholds. Returns list(systolic, diastolic) or null if no
	// detectable blood pressure (dead, no heart).
	var/obj/item/organ/internal/heart/H = internal_organs_by_name?[O_HEART]
	if(!H || H.is_broken() || stat == DEAD)
		return null
	var/sys = 120
	var/dia = 80
	var/blood_vol = vessel?.get_reagent_amount(REAGENT_ID_BLOOD)
	if(blood_vol != null && species)
		var/ratio = blood_vol / species.blood_volume
		// Shock as blood volume drops.
		if(ratio < 0.60)        { sys -= 50; dia -= 30 }
		else if(ratio < 0.75)   { sys -= 30; dia -= 18 }
		else if(ratio < 0.85)   { sys -= 15; dia -= 8 }
	sys += _vital_modifier("bp_sys_mod")
	dia += _vital_modifier("bp_dia_mod")
	sys += _dq_jitter(3)
	dia += _dq_jitter(2)
	sys = max(0, round(sys))
	dia = max(0, round(dia))
	return list(sys, dia)

/mob/living/carbon/human/proc/get_o2_sat_reading()
	// Pulse oximetry. 99% normal; drops as oxyloss climbs.
	if(stat == DEAD)
		return 0
	var/sat = 99
	var/oxy = getOxyLoss()
	// Linear drop: every 5 oxyloss = 1% sat lost (rough mapping).
	sat -= round(oxy / 5)
	sat += _vital_modifier("o2_sat_mod")
	sat += _dq_jitter(1)
	return clamp(round(sat), 0, 100)

/mob/living/carbon/human/proc/get_respiratory_rate()
	// Respirations per minute. Conditions add via "resp_mod". A dead
	// or non-breathing patient returns 0.
	if(stat == DEAD)
		return 0
	if(!should_have_organ(O_LUNGS))
		return 0
	var/rate = 14
	rate += _vital_modifier("resp_mod")
	rate += _dq_jitter(1)
	return max(0, round(rate))
