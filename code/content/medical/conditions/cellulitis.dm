// Infection cascade chain.
//
// wound_infection → cellulitis → sepsis → septic_shock → cardiac_arrest
//
// Spaceacillin is the universal cure but the further down the chain,
// the harder it gets to push severity back down. Septic shock is
// nearly terminal and only modern care + active antibiotics + fluids
// can pull a patient back.
//
// Each link presents differently:
//   cellulitis    — local: swelling, throbbing, fever
//   sepsis        — systemic: confusion, tachycardia, fever
//   septic_shock  — circulatory collapse: pallor, low BP, weakness

/datum/affliction/cellulitis
	name = "cellulitis"
	category = "Infection"
	clinical_description = "Bacterial infection spreading through soft tissue. The site grows hot, red, and tender."
	progression_rate = 0.5
	// Spaceacillin is the standard narrow-spectrum antibiotic;
	// corophizine is the wide-spectrum alternative (faster but causes
	// GI side effects). Either works; their combo has a documented
	// interference, see the chemical side-effect conditions.
	treated_by = list(TREAT_ANTIMICROBIAL = 1.2, TREAT_RESECTION = 1)
	symptom_pool = list(
		/datum/affliction_symptom/throbbing_pain  = 80,
		/datum/affliction_symptom/fever_sensation = 70,
		/datum/affliction_symptom/chills          = 50,
		/datum/affliction_symptom/fatigue         = 60,
	)
	min_symptoms = 1
	max_symptoms = 3
	// Pulse derives from body state; tachycardia comes from raised
	// body temp (handled in tick below). We only need to
	// fudge temp readings if we want a discrepancy between actual and
	// reading — leave readings linked to truth.
	// C16: fever raises the thermoregulation set point (up to +2 K at severity 100).
	factors = alist(STAT_SLOWDOWN = 0.3, STAT_TEMPERATURE = 2.0)
	spontaneous_emotes = list("wince", "shudder")
	spontaneous_emote_prob = 3
