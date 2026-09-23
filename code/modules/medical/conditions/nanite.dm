// Nanite afflictions: what goes wrong with a protean's swarm. See
// doc/mob_life_architecture.md §6.2.
//
//   Affliction             Sits on        Caused by                          Treated by
//   cohesion loss          whole swarm    heavy physical / thermal hits      regeneration, plating repair
//   refactory depletion    refactory      needing repair with no steel       feedstock (steel)
//   orchestrator damage    orchestrator   hits to the orchestrator, shocks   calibration, wiring repair
//   contamination          refactory      foreign reagents or materials      regeneration (filtering)
//   form strain            whole swarm    switching too fast, holding long   calibration, regeneration
//
// All are BIOLOGY_NANOFORM: nothing organic grows them, and only the nanite
// mechanisms reach them (see treatment_tag_biology()). The triggers live in
// the nanoform body plan (code/modules/body/plans/nanoform.dm) and the
// protean forms component; these types own only their progression and
// treatment.

/datum/affliction/nanite
	abstract_type = /datum/affliction/nanite
	name = "nanite fault"
	category = "Synthetic"
	subcategory = "Nanite swarm"
	biology = BIOLOGY_NANOFORM
	body_plans = BODY_PLAN_HUMANOID
	progression_rate = 0
	min_symptoms = 1
	max_symptoms = 2

/// The swarm's working refactory, or null.
/datum/affliction/nanite/proc/refactory()
	RETURN_TYPE(/obj/item/organ/internal/nano/refactory)
	return owner?.nano_get_refactory()

/// Severity drift this tick from the swarm's own state (positive worsens).
/// The base progress() applies it with any continuous treatment.
/datum/affliction/nanite/proc/state_drift()
	return 0

/datum/affliction/nanite/progress()
	var/drift = state_drift()
	if(drift > 0)
		drift *= body.get_factor(BF_PROGRESSION)
	set_severity(severity + drift + pending_treatment)
	pending_treatment = 0
	if(severity <= 0)
		cure()


// --- Cohesion loss ------------------------------------------------------------------------

/// The swarm's bonds have been torn apart by trauma. It moves sluggishly and
/// comes apart more easily under further blows. It reknits from refactory
/// steel; with no steel it keeps unravelling.
/datum/affliction/nanite/cohesion_loss
	name = "cohesion loss"
	clinical_description = "Trauma has torn the bonds between the swarm's nanites. The body moves sluggishly, holds tools poorly and tears more easily under further blows. The swarm reknits itself from refactory steel (regeneration) or with nanopaste; without steel it keeps unravelling."
	injury_category = INJURY_CATEGORY_PHYSICAL
	treated_by = list(TREAT_REGENERATION = 1, TREAT_PLATING_REPAIR = 0.5)
	factors = alist(BF_SLOWDOWN = 2, BF_MOTOR_CONTROL = 0.9, BF_INCOMING_PHYSICAL = 1.3)
	symptom_pool = list(
		/datum/affliction_symptom/nanite/sloughing = 90,
		/datum/affliction_symptom/nanite/cohesion_warning = 80,
		/datum/affliction_symptom/nanite/bond_density_low = 95,
	)

/// Unravels while there is no steel to reknit with; slowly settles otherwise.
/datum/affliction/nanite/cohesion_loss/state_drift()
	var/obj/item/organ/internal/nano/refactory/R = refactory()
	if(!R || R.get_stored_material(MAT_STEEL) < NANOFORM_STEEL_PER_POINT)
		return AFFLICTION_BASE_PROGRESSION * 0.5
	return -AFFLICTION_BASE_PROGRESSION * 0.25


// --- Refactory depletion ------------------------------------------------------------------

/// The refactory has run dry while the swarm needed repair. Regeneration is
/// crippled until it is fed steel.
/datum/affliction/nanite/refactory_depletion
	name = "refactory depletion"
	clinical_description = "The refactory has run out of steel while the swarm needed repair. The nanites cannibalise one another to stay whole: regeneration slows and the body grows sluggish. Feed the refactory steel."
	treated_by = list(TREAT_FEEDSTOCK = 1)
	factors = alist(BF_HEALING = 0.5, BF_SLOWDOWN = 1)
	symptom_pool = list(
		/datum/affliction_symptom/nanite/thinning = 90,
		/datum/affliction_symptom/nanite/feedstock_warning = 85,
		/datum/affliction_symptom/nanite/refactory_stock_empty = 95,
	)

/// Recovers on its own once the refactory holds a working stock again.
/datum/affliction/nanite/refactory_depletion/state_drift()
	var/obj/item/organ/internal/nano/refactory/R = refactory()
	if(R && R.get_stored_material(MAT_STEEL) >= NANITE_DEPLETION_RELIEF_STEEL)
		return -AFFLICTION_BASE_PROGRESSION * 2
	return 0


// --- Orchestrator damage --------------------------------------------------------------------

/// The orchestrator coordinates the swarm. Damaged, it loses fine control and
/// cannot reliably hold a form together through a change of shape.
/datum/affliction/nanite/orchestrator_damage
	name = "orchestrator damage"
	clinical_description = "The orchestrator module, which coordinates the swarm, is damaged. Movement and aim lose precision, form changes can fail outright, and at worst the swarm loses awareness. Recalibrate it with a multitool or reboot programmer and repair its wiring."
	consciousness_at_max = 60
	treated_by = list(TREAT_CALIBRATION = 2, TREAT_WIRING_REPAIR = 1)
	factors = alist(BF_MOTOR_CONTROL = 0.85, BF_ACCURACY = -20, BF_ATTACK_SPEED = 1.3)
	symptom_pool = list(
		/datum/affliction_symptom/nanite/desync = 90,
		/datum/affliction_symptom/nanite/control_errors = 85,
		/datum/affliction_symptom/nanite/orchestrator_fault = 95,
	)

/// A damaged coordinator slowly drifts further out of sync.
/datum/affliction/nanite/orchestrator_damage/state_drift()
	return severity >= 50 ? AFFLICTION_BASE_PROGRESSION * 0.2 : 0


// --- Contamination --------------------------------------------------------------------------

/// Foreign matter the swarm can't use has worked its way through it. The
/// refactory filters it out while the swarm regenerates, and on its own once
/// the source is gone.
/datum/affliction/nanite/contamination
	name = "swarm contamination"
	clinical_description = "Foreign reagents or materials have worked their way into the swarm and the refactory. The nanites misfire around the contaminant: healing slows and fine control suffers. Purge the reagents; the refactory filters the rest while the swarm regenerates."
	injury_category = INJURY_CATEGORY_TOXIC
	treated_by = list(TREAT_REGENERATION = 1)
	factors = alist(BF_HEALING = 0.6, BF_ACCURACY = -10, BF_MOTOR_CONTROL = 0.95)
	symptom_pool = list(
		/datum/affliction_symptom/nanite/discoloured_swarm = 90,
		/datum/affliction_symptom/nanite/contaminant_warning = 80,
		/datum/affliction_symptom/nanite/foreign_matter = 95,
	)

/// Clears slowly while nothing foreign remains in the swarm.
/datum/affliction/nanite/contamination/state_drift()
	var/datum/body/humanoid/nanoform/B = body
	if(istype(B) && B.foreign_reagent_volume() > 0)
		return 0
	return -AFFLICTION_BASE_PROGRESSION * 0.5


// --- Form strain ----------------------------------------------------------------------------

/// The swarm has been held in an unnatural shape too long, or reshaped too
/// often. It eases on its own in the character's humanoid form.
/datum/affliction/nanite/form_strain
	name = "form strain"
	clinical_description = "The swarm has been reshaped too quickly, or held in a shapeless form too long, and its structure is fatigued. Movement and attacks slow. It eases with rest in humanoid form, recalibration or regeneration."
	treated_by = list(TREAT_CALIBRATION = 1, TREAT_REGENERATION = 0.5)
	factors = alist(BF_SLOWDOWN = 1, BF_MOTOR_CONTROL = 0.9, BF_ATTACK_SPEED = 1.2)
	symptom_pool = list(
		/datum/affliction_symptom/nanite/wavering_shape = 90,
		/datum/affliction_symptom/nanite/strain_warning = 80,
		/datum/affliction_symptom/nanite/structural_fatigue = 95,
	)

/// Rest in the humanoid form eases strain.
/datum/affliction/nanite/form_strain/state_drift()
	var/mob/living/carbon/human/H = owner
	if(istype(H) && istype(H.current_form(), /datum/form/human))
		return -AFFLICTION_BASE_PROGRESSION
	return 0


// --- Symptoms ---------------------------------------------------------------------------------

/datum/affliction_symptom/nanite
	category = "Synthetic"

/datum/affliction_symptom/nanite/sloughing
	name = "sloughing nanites"
	audiences = SYMPTOM_AUDIENCE_PUBLIC
	examine_line = "Grey motes flake off their surface and drift to the floor."
	clinical_description = "Loosely bonded nanites shed from the swarm."

/datum/affliction_symptom/nanite/cohesion_warning
	name = "cohesion warnings"
	audiences = SYMPTOM_AUDIENCE_PATIENT
	clinical_description = "The swarm reports failing inter-nanite bonds."
/datum/affliction_symptom/nanite/cohesion_warning/get_patient_messages()
	var/static/list/msgs = list("Your mass feels loose, as if it could run off you.", "Bond integrity warnings flicker through your swarm.")
	return msgs

/datum/affliction_symptom/nanite/bond_density_low
	name = "low bond density"
	audiences = SYMPTOM_AUDIENCE_SCANNER
	scanner_phrase = "inter-nanite bond density below nominal"
	clinical_description = "Diagnostic readout of weakened swarm cohesion."

/datum/affliction_symptom/nanite/thinning
	name = "thinning mass"
	audiences = SYMPTOM_AUDIENCE_PUBLIC
	examine_line = "Their body looks thin and translucent in places."
	clinical_description = "The swarm has consumed its own mass to stay whole."

/datum/affliction_symptom/nanite/feedstock_warning
	name = "feedstock warnings"
	audiences = SYMPTOM_AUDIENCE_PATIENT
	clinical_description = "The refactory reports an empty steel store."
/datum/affliction_symptom/nanite/feedstock_warning/get_patient_messages()
	var/static/list/msgs = list("Your refactory is empty. You need steel.", "Your nanites are cannibalising one another.")
	return msgs

/datum/affliction_symptom/nanite/refactory_stock_empty
	name = "refactory stock empty"
	audiences = SYMPTOM_AUDIENCE_SCANNER
	scanner_phrase = "refactory feedstock exhausted"
	clinical_description = "Diagnostic readout of an empty refactory store."

/datum/affliction_symptom/nanite/desync
	name = "desynchronised motion"
	audiences = SYMPTOM_AUDIENCE_PUBLIC
	examine_line = "Parts of their body move a moment out of step with the rest."
	clinical_description = "The swarm's motion is visibly uncoordinated."

/datum/affliction_symptom/nanite/control_errors
	name = "control errors"
	audiences = SYMPTOM_AUDIENCE_PATIENT
	clinical_description = "The orchestrator reports lost control packets."
/datum/affliction_symptom/nanite/control_errors/get_patient_messages()
	var/static/list/msgs = list("Your swarm lags behind your intentions.", "Orchestrator fault: control packets dropped.")
	return msgs

/datum/affliction_symptom/nanite/orchestrator_fault
	name = "orchestrator fault"
	audiences = SYMPTOM_AUDIENCE_SCANNER
	scanner_phrase = "orchestrator module reporting faults"
	clinical_description = "Diagnostic readout of a damaged orchestrator."

/datum/affliction_symptom/nanite/discoloured_swarm
	name = "discoloured swarm"
	audiences = SYMPTOM_AUDIENCE_PUBLIC
	examine_line = "Streaks of foreign colour swirl through their body."
	clinical_description = "Contaminants visibly carried through the swarm."

/datum/affliction_symptom/nanite/contaminant_warning
	name = "contaminant warnings"
	audiences = SYMPTOM_AUDIENCE_PATIENT
	clinical_description = "The refactory reports matter it cannot process."
/datum/affliction_symptom/nanite/contaminant_warning/get_patient_messages()
	var/static/list/msgs = list("Something foreign is gumming up your nanites.", "Refactory warning: unprocessable matter detected.")
	return msgs

/datum/affliction_symptom/nanite/foreign_matter
	name = "foreign matter"
	audiences = SYMPTOM_AUDIENCE_SCANNER
	scanner_phrase = "foreign matter detected in swarm"
	clinical_description = "Diagnostic readout of contaminants in the swarm."

/datum/affliction_symptom/nanite/wavering_shape
	name = "wavering shape"
	audiences = SYMPTOM_AUDIENCE_PUBLIC
	examine_line = "Their outline wavers, as if struggling to hold its shape."
	clinical_description = "The swarm visibly struggles to hold its form."

/datum/affliction_symptom/nanite/strain_warning
	name = "strain warnings"
	audiences = SYMPTOM_AUDIENCE_PATIENT
	clinical_description = "The swarm reports structural fatigue."
/datum/affliction_symptom/nanite/strain_warning/get_patient_messages()
	var/static/list/msgs = list("Holding this shape is getting harder.", "Your swarm aches to settle into its natural form.")
	return msgs

/datum/affliction_symptom/nanite/structural_fatigue
	name = "structural fatigue"
	audiences = SYMPTOM_AUDIENCE_SCANNER
	scanner_phrase = "swarm structural fatigue"
	clinical_description = "Diagnostic readout of a strained swarm."
