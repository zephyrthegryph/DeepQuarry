// Authored surgery records. One subtype per procedure.
//
// `completion_step` references the upstream /datum/surgery_step typepath
// whose successful `end_step()` signals the cure hook. When that step
// completes on a patient, the integration module clears every active
// instance of the conditions listed in `treats`.
//
// Surgeries without a `completion_step` are documentation-only entries
// (in the book) until a real upstream step lands for them.

// --- Bone ---------------------------------------------------------------

/datum/dq_surgery/fracture_setting
	name = "Fracture setting"
	category = "Bone"
	subcategory = "Bone repair"
	description = "Re-aligning a broken bone and securing it with bone gel or a brace so it can heal cleanly."
	body_region = "Affected limb"
	steps = list(
		"Cut through the skin and muscle over the fracture.",
		"Clamp any bleeding vessels at the wound edge.",
		"Apply bone gel to glue the broken edges together.",
		"Set the bone with a hemostat.",
		"Seal the bone with a hardener.",
		"Stitch the soft tissue closed.",
	)
	tools = list("Scalpel", "Hemostat", "Bone gel", "Bone setter", "Cautery")
	treats = list(/datum/medical_issue/condition/untreated_fracture)
	completion_step = /datum/surgery_step/bones/finish_bone


// --- Vascular -----------------------------------------------------------

/datum/dq_surgery/vessel_repair
	name = "Vessel repair"
	category = "Vascular"
	subcategory = "Bleeding"
	description = "Locating and ligating a torn vessel inside a wound. Stops active arterial bleeding that pressure alone can't control."
	body_region = "Affected limb or torso"
	steps = list(
		"Cut down through the tissue overlying the bleed.",
		"Clamp the bleeding vessel.",
		"Mend the vessel wall with a fixovein applicator.",
		"Stitch the surrounding tissue closed.",
	)
	tools = list("Scalpel", "Hemostat", "Fixovein", "Cautery")
	treats = list(
		/datum/medical_issue/condition/lacerated_artery,
		/datum/medical_issue/condition/internal_hemorrhage,
	)
	completion_step = /datum/surgery_step/fix_vein


// --- Limb soft tissue ---------------------------------------------------

/datum/dq_surgery/tendon_repair
	name = "Tendon repair"
	category = "Limb"
	subcategory = "Soft tissue"
	description = "Locating, freeing, and stapling a severed tendon back together so the limb regains function."
	body_region = "Affected limb"
	steps = list(
		"Cut down to expose the severed tendon.",
		"Free the cut tendon ends from surrounding tissue.",
		"Bring the tendon ends together and staple them.",
		"Seal the closure and stitch the tissue.",
	)
	tools = list("Scalpel", "Hemostat", "Surgical stapler", "Cautery")
	treats = list(/datum/medical_issue/condition/tendon_severed)
	completion_step = /datum/surgery_step/fix_tendon


/datum/dq_surgery/debridement
	name = "Necrotic tissue debridement"
	category = "Limb"
	subcategory = "Soft tissue"
	description = "Cutting away dead tissue from a limb so that the surrounding healthy tissue can recover. The only treatment for necrosis."
	body_region = "Affected limb"
	steps = list(
		"Open the skin over the necrotic tissue.",
		"Cut away the dead tissue with the scalpel.",
		"Wash the wound with sterile solution.",
		"Stitch the wound closed.",
	)
	tools = list("Scalpel", "Sterile solution", "Cautery")
	treats = list(/datum/medical_issue/condition/tissue_necrosis)
	completion_step = /datum/surgery_step/necrotic/fix_dead_tissue


/datum/dq_surgery/fasciotomy
	name = "Fasciotomy"
	category = "Limb"
	subcategory = "Soft tissue"
	description = "Cutting the fascial sheath of a swollen limb to relieve pressure inside the muscle compartment, restoring blood flow before the tissue dies."
	body_region = "Affected limb"
	steps = list(
		"Identify the firmest, most painful compartment of the limb.",
		"Make a long incision through the skin.",
		"Cut the fascia open along its length to release pressure.",
		"Pack the wound open for delayed closure.",
	)
	tools = list("Scalpel", "Hemostat")
	treats = list(/datum/medical_issue/condition/compartment_syndrome)
	completion_step = /datum/surgery_step/fasciotomy


// --- Chest --------------------------------------------------------------

/datum/dq_surgery/chest_decompression
	name = "Chest tube placement"
	category = "Chest"
	subcategory = "Thoracic"
	description = "Inserting a chest tube to vent trapped air from the pleural space, allowing the collapsed lung to re-expand."
	body_region = "Torso"
	steps = list(
		"Identify the intercostal space below the armpit.",
		"Incise through skin and intercostal muscle.",
		"Open the pleural space and release the trapped air.",
		"Place the chest tube and secure it.",
	)
	tools = list("Scalpel", "Hemostat")
	treats = list(/datum/medical_issue/condition/tension_pneumothorax)
	completion_step = /datum/surgery_step/chest_tube


/datum/dq_surgery/lung_repair
	name = "Lung tissue repair"
	category = "Chest"
	subcategory = "Thoracic"
	description = "Opening the chest to mend torn lung tissue directly. The only durable fix when chemistry isn't enough."
	body_region = "Torso"
	steps = list(
		"Open the chest and retract the ribcage.",
		"Locate the damaged lung.",
		"Mend the torn tissue.",
		"Close the chest cavity in layers.",
	)
	tools = list("Scalpel", "Retractor", "Hemostat", "Fixovein", "Bone gel", "Cautery")
	treats = list(/datum/medical_issue/condition/respiratory_failure)
	completion_step = /datum/surgery_step/internal/fix_organ
	heals_organs = list(O_LUNGS)
	// Mechanical lung repair drops severity substantially but doesn't
	// fully resolve respiratory failure on its own — the patient still
	// needs oxygenation support to clear the rest.
	cure_severity = 70


// --- Brain & neuro ------------------------------------------------------
//
// Note: established brain tissue damage is intentionally NOT surgically
// treatable in this fork. Once the brain's organ-damage % is high enough
// to spawn the `brain_damage` cascading condition, no surgery brings it
// back — alkysine + time is the only path, and past ~60% organ damage
// alkysine can't keep up with the underlying decay. A subdural hematoma
// (the bleed that drives the damage in the first place) IS surgically
// drainable; that's what craniotomy is for now.

/datum/dq_surgery/craniotomy
	name = "Craniotomy"
	category = "Brain"
	subcategory = "Neurological"
	description = "Opening the skull to drain a subdural bleed and relieve cranial pressure. Doesn't reverse brain-tissue damage that's already occurred — that's permanent and untreatable surgically."
	body_region = "Head"
	steps = list(
		"Open the scalp.",
		"Cut into the skull bone with a circular saw.",
		"Open the dural sheath.",
		"Drain the bleed and relieve the pressure.",
		"Reseal the dura and replace the skull section.",
		"Close the scalp.",
	)
	tools = list("Scalpel", "Circular saw", "Retractor", "Hemostat", "Bone gel")
	treats = list(/datum/medical_issue/condition/subdural_hematoma)
	completion_step = /datum/surgery_step/internal/fix_organ
	// Heals the brain organ damage that the bleed inflicted — but not
	// brain_damage condition itself (it isn't in `treats`). If the
	// hematoma already pushed brain damage past the unsalvageable
	// threshold, the patient's brain_damage condition continues
	// progressing regardless.
	heals_organs = list(O_BRAIN)


// --- Cardiac ------------------------------------------------------------

/datum/dq_surgery/cardiac_repair
	name = "Open cardiac repair"
	category = "Chest"
	subcategory = "Thoracic"
	description = "Opening the chest to repair damaged cardiac tissue. Indicated when the heart is too damaged for pharmacological recovery. A single procedure can lift the patient out of cardiac arrest but not fully restore cardiac function — follow-up care is required."
	body_region = "Torso"
	steps = list(
		"Open the chest and retract the ribcage.",
		"Expose the heart.",
		"Mend the damaged cardiac tissue.",
		"Close the chest in layers.",
	)
	tools = list("Scalpel", "Retractor", "Hemostat", "Fixovein", "Bone gel", "Cautery")
	treats = list(/datum/medical_issue/condition/heart_damage)
	completion_step = /datum/surgery_step/cardiac_repair
	// Cardiac repair is severe surgery: drops 60 severity. A patient in
	// cardiac arrest (severity ~80+) is dropped to cardiogenic shock
	// territory but not fully cured — the heart still needs chems and
	// time. Saving a life, not finishing the treatment.
	cure_severity = 60


// --- Abdominal ----------------------------------------------------------

/datum/dq_surgery/laparotomy_bleeding
	name = "Exploratory laparotomy for bleeding"
	category = "Trauma"
	subcategory = "Abdominal"
	description = "Opening the abdomen to find and stop internal bleeding that imaging or pressure alone couldn't resolve."
	body_region = "Torso"
	steps = list(
		"Make a midline abdominal incision.",
		"Retract the abdominal wall.",
		"Identify the source of bleeding.",
		"Clamp and repair the bleeding vessel.",
		"Wash out the cavity and close in layers.",
	)
	tools = list("Scalpel", "Retractor", "Hemostat", "Fixovein", "Cautery")
	treats = list(/datum/medical_issue/condition/internal_hemorrhage)
	completion_step = /datum/surgery_step/exploratory_laparotomy


// --- Infection / wound -------------------------------------------------

/datum/dq_surgery/wound_debridement
	name = "Wound debridement"
	category = "Soft Tissue"
	subcategory = "Infection"
	description = "Mechanically cleaning out a severely contaminated wound — cutting away the worst of the dead tissue and irrigating with sterile solution. Restarts a wound's chance of healing without progressing to systemic infection."
	body_region = "Affected limb or torso"
	steps = list(
		"Open the wound widely.",
		"Cut away grossly infected tissue.",
		"Irrigate thoroughly with sterile solution.",
		"Leave the wound packed open for delayed closure.",
	)
	tools = list("Scalpel", "Sterile solution", "Hemostat")
	treats = list(
		/datum/medical_issue/condition/wound_infection,
		/datum/medical_issue/condition/cellulitis,
	)
	completion_step = /datum/surgery_step/necrotic/treat_necrosis


// --- Eyes --------------------------------------------------------------

/datum/dq_surgery/retinal_repair
	name = "Retinal repair"
	category = "Special"
	subcategory = "Ophthalmic"
	description = "Restoring blood supply or mechanical structure to a damaged eye. Indicated when chemistry alone cannot recover the patient's sight."
	body_region = "Head"
	steps = list(
		"Open the eyelid with a retractor.",
		"Access the back of the eye through a small incision.",
		"Repair the damaged retinal tissue.",
		"Close the incision with fine sutures.",
	)
	tools = list("Scalpel", "Retractor", "Fixovein", "Cautery")
	treats = list(/datum/medical_issue/condition/ischemic_vision_loss)
	completion_step = /datum/surgery_step/retinal_repair
