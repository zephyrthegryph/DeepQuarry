// Synthetic afflictions — the diagnostic counterpart of the organic set for
// full-body prosthetics and robotic limbs. A roboticist works these the way a
// doctor works organic afflictions: read the evidence (sparking, jerky
// motion, error chatter, a hot chassis), narrow the cause, apply the right
// mechanism.
//
//   Organic analogue      Synthetic              Treated by
//   hemorrhage          → coolant leak           plating repair (seal) + coolant
//   fracture            → actuator misalignment  recalibration (multitool)
//   concussion/brain    → processor corruption   system restore
//   hypovolemic shock   → power fault            wiring repair
//   heatstroke          → thermal runaway        coolant
//
// All are BIOLOGY_SYNTHETIC: organic parts can't grow them and biological
// treatments can't reach them (see treatment_tag_biology()).

/datum/affliction/synthetic
	name = "synthetic fault"
	category = "Synthetic"
	biology = BIOLOGY_SYNTHETIC | BIOLOGY_NANOFORM
	body_plans = BODY_PLAN_HUMANOID | BODY_PLAN_MACHINE
	progression_rate = 0

// --- Coolant leak ----------------------------------------------------------------
/datum/affliction/synthetic/coolant_leak
	name = "coolant leak"
	// Nanite swarms have no coolant loop or processor to fault.
	biology = BIOLOGY_SYNTHETIC
	subcategory = "Cooling"
	clinical_description = "A breach in the coolant loop. Coolant is lost steadily and the chassis heats up; left alone it overheats into thermal runaway. Seal the breach (plating repair) and replenish coolant."
	progression_rate = 0.5
	treated_by = list(TREAT_PLATING_REPAIR = 2, TREAT_COOLANT = 1.5)
	symptom_pool = list(
		/datum/affliction_symptom/synthetic/coolant_drip = 90,
		/datum/affliction_symptom/synthetic/overheat_warning = 60,
		/datum/affliction_symptom/synthetic/low_coolant_pressure = 95,
	)
	min_symptoms = 1
	max_symptoms = 3

/// Lost coolant means lost heat rejection: the chassis warms up.
/datum/affliction/synthetic/coolant_leak/tick()
	..()
	if(QDELETED(src) || !owner)
		return
	owner.bodytemperature += 1.5 * severity / AFFLICTION_SEVERITY_TERMINAL

// --- Thermal runaway ------------------------------------------------------------
/datum/affliction/synthetic/thermal_runaway
	name = "thermal runaway"
	// Nanite swarms have no coolant loop or processor to fault.
	biology = BIOLOGY_SYNTHETIC
	subcategory = "Cooling"
	clinical_description = "Cooling has failed and internal temperature is climbing faster than it can shed. Processors throttle and the unit loses awareness. Replenish coolant urgently."
	progression_rate = 0.8
	consciousness_at_max = 120
	treated_by = list(TREAT_COOLANT = 2)
	symptom_pool = list(
		/datum/affliction_symptom/synthetic/hot_chassis = 95,
		/datum/affliction_symptom/synthetic/fan_whine = 80,
		/datum/affliction_symptom/synthetic/overheat_warning = 90,
	)
	min_symptoms = 2
	max_symptoms = 3

// --- Actuator misalignment ------------------------------------------------------
/datum/affliction/synthetic/actuator_misalignment
	name = "actuator misalignment"
	subcategory = "Motor"
	clinical_description = "An impact has knocked a limb's actuators out of calibration. Movement is jerky and imprecise; the limb drops what it holds. Recalibrate with a multitool."
	treated_by = list(TREAT_CALIBRATION = 2)
	symptom_pool = list(
		/datum/affliction_symptom/synthetic/jerky_motion = 90,
		/datum/affliction_symptom/synthetic/servo_grind = 60,
		/datum/affliction_symptom/synthetic/calibration_offset = 95,
	)
	min_symptoms = 1
	max_symptoms = 3
	factors = alist(BF_SLOWDOWN = 0.5, BF_ACCURACY = -15, BF_MOTOR_CONTROL = 0.97)

// --- Processor corruption --------------------------------------------------------
/datum/affliction/synthetic/processor_corruption
	name = "processor corruption"
	// Nanite swarms have no coolant loop or processor to fault.
	biology = BIOLOGY_SYNTHETIC
	subcategory = "Processing"
	clinical_description = "Memory and processing faults from a blow to the processor housing or electromagnetic interference. Speech and thought degrade; severe corruption drops the unit into safe mode. A system restore clears it."
	progression_rate = 0.3
	consciousness_at_max = 80
	treated_by = list(TREAT_SYSTEM_RESTORE = 1.5)
	symptom_pool = list(
		/datum/affliction_symptom/synthetic/error_chatter = 90,
		/datum/affliction_symptom/synthetic/speech_glitch = 70,
		/datum/affliction_symptom/synthetic/checksum_errors = 95,
	)
	min_symptoms = 1
	max_symptoms = 3
	spontaneous_emotes = list("twitch", "blink_r")
	spontaneous_emote_prob = 4

// --- Power fault ------------------------------------------------------------------
/datum/affliction/synthetic/power_fault
	name = "power fault"
	subcategory = "Power"
	clinical_description = "Damaged power distribution: the bus can't deliver full current, so systems brown out. Optics dim, movement slows, and at worst the unit loses consciousness. Repair the wiring."
	consciousness_at_max = 60
	treated_by = list(TREAT_WIRING_REPAIR = 1.5)
	symptom_pool = list(
		/datum/affliction_symptom/synthetic/dimming_optics = 85,
		/datum/affliction_symptom/synthetic/power_warning = 80,
		/datum/affliction_symptom/synthetic/bus_voltage_low = 95,
	)
	min_symptoms = 1
	max_symptoms = 3
	factors = alist(BF_SLOWDOWN = 1)


// --- Symptoms ------------------------------------------------------------------------

/datum/affliction_symptom/synthetic
	category = "Synthetic"

/datum/affliction_symptom/synthetic/coolant_drip
	name = "coolant leaking"
	audiences = SYMPTOM_AUDIENCE_PUBLIC
	examine_line = "Thin blue coolant is dripping from a seam in their chassis."
	clinical_description = "Visible coolant loss from a breached loop."
	public_emote_chance = 3
/datum/affliction_symptom/synthetic/coolant_drip/get_public_emotes()
	var/static/list/emotes = list("drips coolant onto the floor.")
	return emotes

/datum/affliction_symptom/synthetic/overheat_warning
	name = "overheat warnings"
	audiences = SYMPTOM_AUDIENCE_PATIENT
	clinical_description = "Internal diagnostics report rising core temperature."
/datum/affliction_symptom/synthetic/overheat_warning/get_patient_messages()
	var/static/list/msgs = list("WARNING: core temperature rising.", "Thermal management reports reduced heat rejection.")
	return msgs

/datum/affliction_symptom/synthetic/low_coolant_pressure
	name = "low coolant pressure"
	audiences = SYMPTOM_AUDIENCE_SCANNER
	scanner_phrase = "coolant loop pressure below nominal"
	clinical_description = "Diagnostic readout of reduced coolant loop pressure."

/datum/affliction_symptom/synthetic/hot_chassis
	name = "hot chassis"
	audiences = SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_SCANNER
	scanner_phrase = "core temperature critical"
	examine_line = "Heat shimmers off their chassis."
	clinical_description = "The chassis is too hot to touch."

/datum/affliction_symptom/synthetic/fan_whine
	name = "fans at maximum"
	audiences = SYMPTOM_AUDIENCE_PUBLIC
	clinical_description = "Cooling fans running flat out, audibly."
	public_emote_chance = 4
/datum/affliction_symptom/synthetic/fan_whine/get_public_emotes()
	var/static/list/emotes = list("whirs loudly as their fans spin up.")
	return emotes

/datum/affliction_symptom/synthetic/jerky_motion
	name = "jerky movement"
	audiences = SYMPTOM_AUDIENCE_PUBLIC
	examine_line = "Their movements are stiff and jerky."
	clinical_description = "Motion overshoots and corrects in visible steps."

/datum/affliction_symptom/synthetic/servo_grind
	name = "grinding servos"
	audiences = SYMPTOM_AUDIENCE_PUBLIC | SYMPTOM_AUDIENCE_PATIENT
	clinical_description = "Audible grinding from a misaligned joint."
	public_emote_chance = 3
/datum/affliction_symptom/synthetic/servo_grind/get_public_emotes()
	var/static/list/emotes = list("makes a faint grinding noise as they move.")
	return emotes
/datum/affliction_symptom/synthetic/servo_grind/get_patient_messages()
	var/static/list/msgs = list("A joint grinds as it moves.", "Actuator feedback doesn't match the commanded position.")
	return msgs

/datum/affliction_symptom/synthetic/calibration_offset
	name = "calibration offset"
	audiences = SYMPTOM_AUDIENCE_SCANNER
	scanner_phrase = "actuator calibration offset detected"
	clinical_description = "Diagnostic readout of an actuator out of calibration."

/datum/affliction_symptom/synthetic/error_chatter
	name = "error messages"
	audiences = SYMPTOM_AUDIENCE_PATIENT
	clinical_description = "The unit's own diagnostics report memory and processing errors."
/datum/affliction_symptom/synthetic/error_chatter/get_patient_messages()
	var/static/list/msgs = list("ERROR: segmentation fault in cognitive subroutine.", "Memory checksum mismatch. Retrying...", "A thought loops, stalls, and restarts.")
	return msgs

/datum/affliction_symptom/synthetic/speech_glitch
	name = "speech glitches"
	audiences = SYMPTOM_AUDIENCE_PUBLIC
	examine_line = "Their voice module crackles and skips."
	clinical_description = "Speech output stutters and repeats."
/datum/affliction_symptom/synthetic/speech_glitch/tick(mob/living/M, datum/affliction/source)
	..()
	if(M && prob(5))
		M.stuttering = max(M.stuttering, 3)

/datum/affliction_symptom/synthetic/checksum_errors
	name = "checksum errors"
	audiences = SYMPTOM_AUDIENCE_SCANNER
	scanner_phrase = "memory checksum errors logged"
	clinical_description = "Diagnostic log of memory integrity failures."

/datum/affliction_symptom/synthetic/dimming_optics
	name = "dimming optics"
	audiences = SYMPTOM_AUDIENCE_PUBLIC
	examine_line = "Their optics flicker and dim."
	clinical_description = "Optical sensors brown out under low voltage."

/datum/affliction_symptom/synthetic/power_warning
	name = "power warnings"
	audiences = SYMPTOM_AUDIENCE_PATIENT
	clinical_description = "The unit reports brownouts and low supply voltage."
/datum/affliction_symptom/synthetic/power_warning/get_patient_messages()
	var/static/list/msgs = list("WARNING: supply voltage low.", "Your systems brown out for a moment.")
	return msgs

/datum/affliction_symptom/synthetic/bus_voltage_low
	name = "low bus voltage"
	audiences = SYMPTOM_AUDIENCE_SCANNER
	scanner_phrase = "power bus voltage below nominal"
	clinical_description = "Diagnostic readout of a failing power distribution bus."


// --- Triggers ----------------------------------------------------------------------------
// Synthetic-part injuries (see dq_dispatch_damage_event's biology filter).

/datum/affliction_trigger/injury/synthetic_sharp_torso
	name = "Breach of a synthetic torso"
	subcategory = "Synthetic"
	description = "A cut or puncture through chassis plating — the coolant loop and power bus run just beneath."
	biology = BIOLOGY_SYNTHETIC | BIOLOGY_NANOFORM
	wound_class = "sharp"
	body_regions = list(BP_TORSO, BP_GROIN)
	min_damage = 8

/datum/affliction_trigger/injury/synthetic_sharp_torso/setup()
	..()
	declare(/datum/affliction/synthetic/coolant_leak, chance = 35)
	declare(/datum/affliction/synthetic/power_fault, chance = 20, threshold = 15)

/datum/affliction_trigger/injury/synthetic_burn_torso
	name = "Burn through a synthetic torso"
	subcategory = "Synthetic"
	description = "Heat or current through the chassis fuses power distribution."
	biology = BIOLOGY_SYNTHETIC | BIOLOGY_NANOFORM
	wound_class = "burn"
	body_regions = list(BP_TORSO, BP_GROIN)
	min_damage = 10

/datum/affliction_trigger/injury/synthetic_burn_torso/setup()
	..()
	declare(/datum/affliction/synthetic/power_fault, chance = 30)

/datum/affliction_trigger/injury/synthetic_blunt_limb
	name = "Impact to a synthetic limb"
	subcategory = "Synthetic"
	description = "A hard knock to a prosthetic limb throws its actuators out of calibration."
	biology = BIOLOGY_SYNTHETIC | BIOLOGY_NANOFORM
	wound_class = "blunt"
	body_regions = list("limb")
	min_damage = 8

/datum/affliction_trigger/injury/synthetic_blunt_limb/setup()
	..()
	declare(/datum/affliction/synthetic/actuator_misalignment, chance = 40)

/datum/affliction_trigger/injury/synthetic_blunt_head
	name = "Impact to a synthetic head"
	subcategory = "Synthetic"
	description = "A blow to the processor housing corrupts memory and processing."
	biology = BIOLOGY_SYNTHETIC | BIOLOGY_NANOFORM
	wound_class = "blunt"
	body_regions = list(BP_HEAD)
	min_damage = 10

/datum/affliction_trigger/injury/synthetic_blunt_head/setup()
	..()
	declare(/datum/affliction/synthetic/processor_corruption, chance = 40)

/datum/affliction_trigger/progression/coolant_to_runaway
	name = "Coolant loss becomes thermal runaway"
	subcategory = "Synthetic"
	source_condition = /datum/affliction/synthetic/coolant_leak
	threshold = 60

/datum/affliction_trigger/progression/coolant_to_runaway/setup()
	..()
	declare(/datum/affliction/synthetic/thermal_runaway, chance = 20)
