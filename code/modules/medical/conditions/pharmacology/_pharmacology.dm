// Pharmacological conditions: chem side effects, drug interactions and
// overdoses, split by drug class across this folder.
//
// These conditions are spawned by the chem dispatcher (dq_check_chem_conditions
// in emergent.dm) while the relevant reagent(s) are in the body above a
// threshold. They despawn automatically when the chems clear — the patient
// doesn't have to do anything special to recover, the effect just fades.
//
// They are intentionally low-impact below overdose: mild symptoms that
// complicate the diagnostic picture rather than threaten the patient. A medic
// who sees "confusion" on a brain-damage patient who's been dosed with
// alkysine has to work out whether the confusion is the brain damage
// (worsening) or the alkysine (expected side effect).
//
// Each condition declares its trigger via `caused_by_chems`:
//   list(REAGENT_ID = threshold)                — single chem: side effect / overdose
//   list(A = threshold, B = threshold)          — multi-chem: interaction
// `caused_by_chems_organ` sets the host organ for the spawned condition.
//
// The three families below carry the shared header (category, subcategory,
// no natural progression); concrete conditions only declare what is theirs.
// Staged overdoses build their Mild -> Severe -> Critical table with
// overdose_stages() and chem_stage().

/// Shared by every pharmacological condition: the dispatcher adds and clears
/// them with the chem, so they never progress on their own.
/datum/affliction/chem_side_effect
	abstract_type = /datum/affliction/chem_side_effect
	category = "Pharmacological"
	subcategory = "Side effect"
	progression_rate = 0

/// Two chems in the body together. Silent markers (no symptoms) exist only to
/// scale another chem's effectiveness through `interferes_with`.
/datum/affliction/chem_interaction
	abstract_type = /datum/affliction/chem_interaction
	category = "Pharmacological"
	subcategory = "Interaction"
	progression_rate = 0

/// A reagent above its `overdose` threshold. Thresholds match the reagent
/// declarations (code/modules/reagents/reagents/medicine.dm); severity scales
/// with the excess (chem_scaling), and the reagent's encyclopedia entry links
/// straight to the condition.
/datum/affliction/overdose
	abstract_type = /datum/affliction/overdose
	category = "Pharmacological"
	subcategory = "Overdose"
	progression_rate = 0
	chem_scaling = TRUE

/// One stage of a staged pharmacological condition: its symptom pool, how
/// many of those symptoms show, and any other stage keys (organ damage,
/// "factors", "always_spawns", emotes...).
/proc/chem_stage(list/symptom_pool, min_symptoms, max_symptoms, list/extra)
	. = list("symptom_pool" = symptom_pool, "min_symptoms" = min_symptoms, "max_symptoms" = max_symptoms)
	if(extra)
		for(var/key in extra)
			.[key] = extra[key]

/// The Mild -> Severe -> Critical stage table every overdose uses.
/proc/overdose_stages(list/mild, list/severe, list/critical)
	return list("Mild" = mild, "Severe" = severe, "Critical" = critical)
