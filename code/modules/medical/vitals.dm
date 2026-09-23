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
// Afflictions, reagents and modifiers modulate these through the readout
// body factors (BF_HEART_RATE, BF_TEMPERATURE, BF_BP_SYSTOLIC,
// BF_BP_DIASTOLIC, BF_O2_SAT, BF_RESP_RATE), summed across every source.
//
// We layer those on top of whatever vitals the upstream mob already tracks
// (BYOND `bodytemperature` in kelvin, heart pulse enum). For pulse and BP we
// synthesize from the heart organ's enum rather than tracking a separate bpm
// var, so existing code that reads the enum still works.

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
	celsius += factor(BF_TEMPERATURE)
	celsius += _dq_jitter(0.1)
	return round(celsius * 10) / 10  // one decimal place

/mob/living/carbon/human/proc/get_pulse_reading_bpm()
	// Map the upstream pulse enum to a bpm baseline, then offset by
	// compensatory tachycardia from blood loss and heart-rate factors.
	var/obj/item/organ/internal/heart/H = internal_organs_by_name?[O_HEART]
	if(!H || H.is_broken() || !has_cardiac_output())
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
	baseline += factor(BF_HEART_RATE)
	baseline += _dq_jitter(3)
	return max(0, round(baseline))

/mob/living/carbon/human/proc/get_bp_reading()
	// Synthesize systolic / diastolic. Defaults: 120/80. Blood volume
	// has a strong effect; we mirror the upstream "blood_level_*"
	// thresholds. Returns list(systolic, diastolic) or null if no
	// detectable blood pressure (dead, no heart).
	var/obj/item/organ/internal/heart/H = internal_organs_by_name?[O_HEART]
	if(!H || H.is_broken() || stat == DEAD || !has_cardiac_output())
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
	sys += factor(BF_BP_SYSTOLIC)
	dia += factor(BF_BP_DIASTOLIC)
	sys += _dq_jitter(3)
	dia += _dq_jitter(2)
	sys = max(0, round(sys))
	dia = max(0, round(dia))
	return list(sys, dia)

/mob/living/carbon/human/proc/get_o2_sat_reading()
	// Pulse oximetry. 99% normal; drops as tissue hypoxia climbs.
	if(stat == DEAD)
		return 0
	var/sat = 99
	var/hypoxia = oxygen_debt()
	// Linear drop: every 5 points of hypoxia = 1% sat lost (rough mapping).
	sat -= round(hypoxia / 5)
	sat += factor(BF_O2_SAT)
	sat += _dq_jitter(1)
	return clamp(round(sat), 0, 100)

/mob/living/carbon/human/proc/get_respiratory_rate()
	// Respirations per minute. Conditions add via "resp_mod". A dead
	// or non-breathing patient returns 0.
	if(stat == DEAD)
		return 0
	if(!should_have_organ(O_LUNGS))
		return 0
	// Apnea or a closed airway: nothing moves.
	if(breath_blocked())
		return 0
	var/rate = 14
	rate += factor(BF_RESP_RATE)
	rate += _dq_jitter(1)
	return max(0, round(rate))
