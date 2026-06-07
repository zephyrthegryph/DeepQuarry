// Brain trauma chain.
//
// concussion (in trauma.dm) — first hit, mostly nuisance, self-heals.
// A second head hit spawns subdural_hematoma (in cascades.dm). The
// hematoma damages the brain directly, and once brain damage crosses
// 40% / 80% the staged `brain_damage` condition appears in its
// Significant / Critical stages respectively (see organ_failures.dm).

/datum/medical_issue/condition/subdural_hematoma
	name = "subdural hematoma"
	category = "Brain"
	clinical_description = "A bleed beneath the dura. Pressure builds inside the skull as the bleed grows, crowding healthy tissue."
	progression_rate = 1.0
	// Synaptizine repairs neural tissue from the bleed; bicaridaze
	// slows the bleed itself. The surgical option (craniotomy) is the
	// real fix for severe cases.
	cured_by = list(REAGENT_ID_SYNAPTIZINE = 0.8, REAGENT_ID_BICARIDAZE = 0.4)
	symptom_pool = list(
		/datum/medical_symptom/headache             = 90,
		/datum/medical_symptom/confusion            = 80,
		/datum/medical_symptom/blurred_vision       = 70,
		/datum/medical_symptom/nausea               = 60,
		/datum/medical_symptom/dizziness            = 70,
		/datum/medical_symptom/pupillary_asymmetry  = 70,
		/datum/medical_symptom/unsteady_gait        = 60,
	)
	min_symptoms = 3
	max_symptoms = 5
	mechanical_effects = list(
		"slowdown" = 1.0,
		"accuracy_penalty" = 30,
		"drop_held_prob" = 3,
		"blocked_verbs" = list("Surgery"),
		"spontaneous_emotes" = list("stumble", "groan", "wince"),
		"spontaneous_emote_prob" = 5,
	)
	// Damages the brain at moderate-to-high severity; once brain damage
	// climbs past 40% the staged brain_damage condition appears, and
	// past 80% it advances to its Critical stage.
	organ_damage_threshold = 50
	organ_damage_type = "internal"
	organ_damage_per_tick = 2
	organ_damage_targets = list(O_BRAIN)

/datum/medical_issue/condition/subdural_hematoma/get_vital_effects()
	var/static/list/L = list("pulse_mod" = 15, "bp_sys_mod" = 10)
	return L
