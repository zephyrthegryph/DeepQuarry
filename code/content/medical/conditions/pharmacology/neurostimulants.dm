// Stimulants and neuro-active drugs: pharmacological side effects, overdoses and interactions.
// Families and the stage template: _pharmacology.dm.

/datum/affliction/chem_side_effect/alkysine_confusion
	name = "alkysine confusion"
	clinical_description = "Alkysine in the bloodstream at therapeutic dose can produce mild confusion. Resolves as the chem clears."
	symptom_pool = list(
		/datum/affliction_symptom/confusion = 70,
	)
	min_symptoms = 1
	max_symptoms = 1
	caused_by_chems = list(REAGENT_ID_ALKYSINE = 5)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/chem_side_effect/synaptizine_jitter
	name = "synaptizine jitteriness"
	clinical_description = "Synaptizine's neuro-stimulant component can produce restless movements and elevated heart rate at therapeutic dose. Resolves as the chem clears."
	symptom_pool = list(
		/datum/affliction_symptom/jittery       = 80,
		/datum/affliction_symptom/palpitations  = 50,
	)
	min_symptoms = 1
	max_symptoms = 2
	caused_by_chems = list(REAGENT_ID_SYNAPTIZINE = 5)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/overdose/alkysine
	name = "alkysine overdose"
	clinical_description = "Excess alkysine is itself neurotoxic — the same neurotransmitter pathway it's meant to support gets overwhelmed. Confusion, headache, and accumulating brain damage."
	symptom_pool = list(
		/datum/affliction_symptom/confusion = 80,
		/datum/affliction_symptom/headache  = 60,
		/datum/affliction_symptom/jittery   = 40,
	)
	min_symptoms = 1
	max_symptoms = 3
	organ_damage_threshold = 0
	organ_damage_type = "internal"
	organ_damage_per_tick = 0.5
	organ_damage_targets = list(O_BRAIN)
	caused_by_chems = list(REAGENT_ID_ALKYSINE = 20)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/overdose/alkysine
	overdose_stage_data = list(
		list(list(
			/datum/affliction_symptom/headache = 60,
			/datum/affliction_symptom/jittery  = 40,
		), 1, 1, list("organ_damage_per_tick" = 0.15, "organ_damage_type" = "internal", "organ_damage_targets" = list(O_BRAIN))),
		list(list(
			/datum/affliction_symptom/confusion = 75,
			/datum/affliction_symptom/headache  = 60,
			/datum/affliction_symptom/jittery   = 40,
		), 1, 2, list("organ_damage_per_tick" = 0.35, "organ_damage_type" = "internal", "organ_damage_targets" = list(O_BRAIN))),
		list(list(
			/datum/affliction_symptom/confusion           = 95,
			/datum/affliction_symptom/headache            = 80,
			/datum/affliction_symptom/jittery             = 60,
			/datum/affliction_symptom/pupillary_asymmetry = 50,
		), 2, 3, list("organ_damage_per_tick" = 0.7, "organ_damage_type" = "internal", "organ_damage_targets" = list(O_BRAIN))),
	)

/datum/affliction/overdose/synaptizine
	name = "synaptizine overdose"
	clinical_description = "Synaptizine at overdose drives the CNS past stimulation into excitotoxicity — restless tremor, accelerated heart rate, tissue stress on the brain. The chem also crosses the blood-brain barrier hard enough at OD doses to repair tissue damage above the salvage threshold — but only enough to win if paired with alkysine. Past the terminal threshold, brain decay outpaces any combination."
	symptom_pool = list(
		/datum/affliction_symptom/jittery        = 90,
		/datum/affliction_symptom/palpitations   = 70,
		/datum/affliction_symptom/confusion      = 50,
	)
	min_symptoms = 2
	max_symptoms = 3
	organ_damage_threshold = 0
	organ_damage_type = "internal"
	organ_damage_per_tick = 0.4
	organ_damage_targets = list(O_BRAIN)
	factors = alist(STAT_NEURAL_REPAIR = 0.3)
	caused_by_chems = list(REAGENT_ID_SYNAPTIZINE = 20)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/overdose/synaptizine
	overdose_stage_data = list(
		list(list(
			/datum/affliction_symptom/jittery      = 70,
			/datum/affliction_symptom/palpitations = 50,
		), 1, 2, list("organ_damage_per_tick" = 0.15, "organ_damage_type" = "internal", "organ_damage_targets" = list(O_BRAIN), "factors" = alist(STAT_NEURAL_REPAIR = 0.1))),
		list(list(
			/datum/affliction_symptom/jittery      = 85,
			/datum/affliction_symptom/palpitations = 70,
			/datum/affliction_symptom/confusion    = 50,
		), 2, 3, list("organ_damage_per_tick" = 0.3, "organ_damage_type" = "internal", "organ_damage_targets" = list(O_BRAIN), "factors" = alist(STAT_NEURAL_REPAIR = 0.22))),
		list(list(
			/datum/affliction_symptom/jittery          = 100,
			/datum/affliction_symptom/palpitations     = 85,
			/datum/affliction_symptom/confusion        = 70,
			/datum/affliction_symptom/sharp_chest_pain = 50,
		), 3, 4, list("organ_damage_per_tick" = 0.5, "organ_damage_type" = "internal", "organ_damage_targets" = list(O_BRAIN), "factors" = alist(STAT_NEURAL_REPAIR = 0.35), "always_spawns" = list(/datum/affliction/chem_interaction/tachycardia_chem))),
	)

/datum/affliction/overdose/earthsblood
	name = "earthsblood overdose"
	clinical_description = "Earthsblood's psychoactive component overwhelms the cortex at overdose — the same neuron-tithing that powers its healing turns aggressive. Hallucinations, confusion, and ongoing brain tissue loss. The hand-off it offers in exchange: tox, oxy, and clone damage continue to bleed off rapidly even at OD."
	symptom_pool = list(
		/datum/affliction_symptom/confusion       = 80,
		/datum/affliction_symptom/jittery         = 60,
		/datum/affliction_symptom/headache        = 50,
		/datum/affliction_symptom/unsteady_gait   = 40,
	)
	min_symptoms = 2
	max_symptoms = 3
	organ_damage_threshold = 0
	organ_damage_type = "internal"
	organ_damage_per_tick = 0.5
	organ_damage_targets = list(O_BRAIN)
	caused_by_chems = list(REAGENT_ID_EARTHSBLOOD = 15)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/overdose/earthsblood
	overdose_stage_data = list(
		list(list(
			/datum/affliction_symptom/jittery  = 50,
			/datum/affliction_symptom/headache = 40,
		), 1, 2, list("organ_damage_per_tick" = 0.15, "organ_damage_type" = "internal", "organ_damage_targets" = list(O_BRAIN))),
		list(list(
			/datum/affliction_symptom/confusion     = 75,
			/datum/affliction_symptom/jittery       = 60,
			/datum/affliction_symptom/headache      = 50,
			/datum/affliction_symptom/unsteady_gait = 40,
		), 2, 3, list("organ_damage_per_tick" = 0.35, "organ_damage_type" = "internal", "organ_damage_targets" = list(O_BRAIN))),
		list(list(
			/datum/affliction_symptom/confusion           = 95,
			/datum/affliction_symptom/jittery             = 80,
			/datum/affliction_symptom/headache            = 70,
			/datum/affliction_symptom/unsteady_gait       = 60,
			/datum/affliction_symptom/pupillary_asymmetry = 50,
		), 3, 4, list("organ_damage_per_tick" = 0.7, "organ_damage_type" = "internal", "organ_damage_targets" = list(O_BRAIN))),
	)

/datum/affliction/chem_side_effect/adranol_jitter
	name = "adranol agitation"
	clinical_description = "Adranol overstimulates a little: the patient is restless, jittery and agitated while it is in the blood. Resolves as the chem clears."
	symptom_pool = list(
		/datum/affliction_symptom/jittery = 100,
	)
	min_symptoms = 1
	max_symptoms = 1
	caused_by_chems = list(REAGENT_ID_ADRANOL = 2)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/chem_side_effect/adranol_drowsy
	name = "adranol drowsiness"
	clinical_description = "A mild drowsiness under the restlessness. Resolves as the chem clears."
	symptom_pool = list(
		/datum/affliction_symptom/drowsy = 100,
	)
	min_symptoms = 1
	max_symptoms = 1
	factors = alist(STAT_SLOWDOWN = 0.15)
	caused_by_chems = list(REAGENT_ID_ADRANOL = 2)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/chem_side_effect/ethylredoxrazine_disorientation
	name = "ethylredoxrazine disorientation"
	clinical_description = "Ethylredoxrazine leaves the patient confused and dizzy, and their speech slurs. Resolves as the chem clears."
	symptom_pool = list(
		/datum/affliction_symptom/confusion      = 100,
		/datum/affliction_symptom/dizziness      = 100,
		/datum/affliction_symptom/slurred_speech = 100,
	)
	min_symptoms = 3
	max_symptoms = 3
	caused_by_chems = list(REAGENT_ID_ETHYLREDOXRAZINE = 2)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/chem_side_effect/tercozolam_drowsy
	name = "tercozolam drowsiness"
	clinical_description = "Tercozolam leaves the patient mildly drowsy and slow while it is in the blood. Resolves as the chem clears."
	symptom_pool = list(
		/datum/affliction_symptom/drowsy = 100,
	)
	min_symptoms = 1
	max_symptoms = 1
	factors = alist(STAT_SLOWDOWN = 0.15)
	caused_by_chems = list(REAGENT_ID_TERCOZOLAM = 3)
	caused_by_chems_organ = O_BRAIN

/datum/affliction/chem_side_effect/anticonvulsant_drowsy
	name = "anticonvulsant drowsiness"
	clinical_description = "Anticonvulsants dull the nervous system a little: the patient is mildly drowsy while it is in the blood. Resolves as the chem clears."
	symptom_pool = list(
		/datum/affliction_symptom/drowsy = 100,
	)
	min_symptoms = 1
	max_symptoms = 1
	factors = alist(STAT_SLOWDOWN = 0.15)
	caused_by_chems = list(REAGENT_ID_ANTICONVULSANT = 3)
	caused_by_chems_organ = O_BRAIN
