// Brain trauma chain.
//
// concussion (in trauma.dm) — first hit, mostly nuisance, self-heals.
// A second head hit spawns subdural_hematoma (in cascades.dm). The
// hematoma damages the brain directly, and once brain damage crosses
// 40% / 80% the staged `brain_damage` condition appears in its
// Significant / Critical stages respectively (see organ_failures.dm).

/datum/affliction/subdural_hematoma
	name = "subdural hematoma"
	category = "Brain"
	clinical_description = "A bleed beneath the dura. Pressure builds inside the skull as the bleed grows, crowding healthy tissue."
	progression_rate = 1.0
	// Synaptizine repairs neural tissue from the bleed; bicaridaze
	// slows the bleed itself. The surgical option (craniotomy) is the
	// real fix for severe cases.
	treated_by = list(TREAT_NEURAL_REPAIR = 0.8, TREAT_HEMOSTATIC = 0.3, TREAT_DECOMPRESSION = 1)
	symptom_pool = list(
		/datum/affliction_symptom/headache             = 90,
		/datum/affliction_symptom/confusion            = 80,
		/datum/affliction_symptom/blurred_vision       = 70,
		/datum/affliction_symptom/nausea               = 60,
		/datum/affliction_symptom/dizziness            = 70,
		/datum/affliction_symptom/pupillary_asymmetry  = 70,
		/datum/affliction_symptom/unsteady_gait        = 60,
	)
	min_symptoms = 3
	max_symptoms = 5
	factors = alist(BF_SLOWDOWN = 1, BF_ACCURACY = -30, BF_MOTOR_CONTROL = 0.97, BF_ACTION_BLOCKS = ACTION_BLOCK_SURGERY, BF_HEART_RATE = 15, BF_BP_SYSTOLIC = 10)
	spontaneous_emotes = list("stumble", "groan", "wince")
	spontaneous_emote_prob = 5
	// Damages the brain at moderate-to-high severity; once brain damage
	// climbs past 40% the staged brain_damage condition appears, and
	// past 80% it advances to its Critical stage.
	organ_damage_threshold = 50
	organ_damage_type = "internal"
	organ_damage_per_tick = 2
	organ_damage_targets = list(O_BRAIN)
	// Compression starves the brain of blood.
	organ_lesion_type = /datum/affliction/lesion/ischemic_injury

