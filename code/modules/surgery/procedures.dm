// Procedure records: the medical book's surgery entries, tied to the runtime.
//
// Each /datum/dq_surgery describes one clinical procedure for the book (prose
// steps, tools, region) and names the /datum/surgical_step types that perform
// it (`procedure`). The runtime never reads these to cure anything: the steps
// deliver treatment tags, and the treated conditions respond through their
// own treated_by. The tests hold the two together: every condition a record
// `treats` must be treated by a mechanism one of its steps delivers, unless
// the record repairs organs (`repairs_organs`), whose integrity conditions
// clear as the organ heals.

/datum/dq_surgery
	/// Display name in the book.
	var/name = "surgery"
	/// One-sentence clinical overview.
	var/description = ""
	/// Book category: "Trauma" / "Bone" / "Vascular" / "Chest" / "Limb" /
	/// "Soft Tissue" / "Brain" / "Special".
	var/category = "Trauma"
	/// Finer grouping rendered as a grey subheader.
	var/subcategory
	/// Body region, in plain English.
	var/body_region = ""
	/// Prose steps for the book reader, in order.
	var/list/steps
	/// Tools needed (display strings).
	var/list/tools
	/// /datum/affliction typepaths the procedure treats.
	var/list/treats
	/// /datum/surgical_step typepaths that perform the procedure, in order.
	var/list/procedure
	/// O_* organs whose lesions the procedure repairs (their integrity
	/// conditions resolve as the organ heals).
	var/list/repairs_organs

/// Every treatment mechanism the procedure's steps deliver.
/datum/dq_surgery/proc/delivered_tags()
	. = list()
	for(var/step_type in procedure)
		var/datum/surgical_step/S = surgical_step(step_type)
		for(var/tag in S?.treatments)
			. |= tag

// --- Bone ---------------------------------------------------------------

/datum/dq_surgery/fracture_setting
	name = "Fracture setting"
	category = "Bone"
	subcategory = "Bone repair"
	description = "Re-aligning a broken bone and securing it with bone gel or a setter so it can heal cleanly."
	body_region = "Affected limb"
	steps = list(
		"Cut through the skin and muscle over the fracture.",
		"Clamp any bleeding vessels at the wound edge.",
		"Retract the skin to expose the bone.",
		"Set the bone with a bone setter or bone gel.",
		"Cauterize the incision closed.",
	)
	tools = list("Scalpel", "Hemostat", "Retractor", "Bone setter or bone gel", "Cautery")
	treats = list(/datum/affliction/untreated_fracture)
	procedure = list(
		/datum/surgical_step/access/incise,
		/datum/surgical_step/clamp_bleeders,
		/datum/surgical_step/access/retract,
		/datum/surgical_step/set_bone,
		/datum/surgical_step/cauterize,
	)


// --- Vascular -----------------------------------------------------------

/datum/dq_surgery/vessel_repair
	name = "Vessel repair"
	category = "Vascular"
	subcategory = "Bleeding"
	description = "Locating and repairing a torn vessel. Stops arterial and internal bleeding that pressure alone can't control."
	body_region = "Affected limb or torso"
	steps = list(
		"Cut down through the tissue overlying the bleed.",
		"Clamp the bleeders and retract the tissue.",
		"Mend the vessel wall with a FixOVein.",
		"Cauterize the incision closed.",
	)
	tools = list("Scalpel", "Hemostat", "Retractor", "FixOVein", "Cautery")
	treats = list(
		/datum/affliction/lacerated_artery,
		/datum/affliction/internal_hemorrhage,
	)
	procedure = list(
		/datum/surgical_step/access/incise,
		/datum/surgical_step/clamp_bleeders,
		/datum/surgical_step/access/retract,
		/datum/surgical_step/treat/vessel_repair,
		/datum/surgical_step/cauterize,
	)


// --- Limb soft tissue ---------------------------------------------------

/datum/dq_surgery/tendon_repair
	name = "Tendon repair"
	category = "Limb"
	subcategory = "Soft tissue"
	description = "Locating, freeing and rejoining a severed tendon so the limb regains function."
	body_region = "Affected limb"
	steps = list(
		"Cut down to expose the severed tendon.",
		"Retract the tissue around it.",
		"Bring the tendon ends together and join them.",
		"Cauterize the incision closed.",
	)
	tools = list("Scalpel", "Retractor", "FixOVein", "Cautery")
	treats = list(/datum/affliction/tendon_severed)
	procedure = list(
		/datum/surgical_step/access/incise,
		/datum/surgical_step/access/retract,
		/datum/surgical_step/treat/tendon_repair,
		/datum/surgical_step/cauterize,
	)

/datum/dq_surgery/debridement
	name = "Debridement"
	category = "Soft Tissue"
	subcategory = "Infection"
	description = "Cutting away dead or badly infected tissue so the healthy tissue around it can recover. The only treatment for necrosis."
	body_region = "Affected limb or torso"
	steps = list(
		"Open the skin over the affected tissue.",
		"Retract the wound edges.",
		"Cut away the dead and infected tissue.",
		"Cauterize the wound closed.",
	)
	tools = list("Scalpel", "Retractor", "Cautery")
	treats = list(
		/datum/affliction/tissue_necrosis,
		/datum/affliction/wound_infection,
		/datum/affliction/cellulitis,
	)
	procedure = list(
		/datum/surgical_step/access/incise,
		/datum/surgical_step/access/retract,
		/datum/surgical_step/treat/debridement,
		/datum/surgical_step/cauterize,
	)

/datum/dq_surgery/fasciotomy
	name = "Fasciotomy"
	category = "Limb"
	subcategory = "Soft tissue"
	description = "Cutting the fascial sheath of a swollen limb to relieve the pressure inside the muscle compartment, restoring blood flow before the tissue dies."
	body_region = "Affected limb"
	steps = list(
		"Make a long incision through the skin.",
		"Retract the skin to expose the fascia.",
		"Cut the fascia open along its length to release the pressure.",
		"Cauterize the incision closed.",
	)
	tools = list("Scalpel", "Retractor", "Cautery")
	treats = list(/datum/affliction/compartment_syndrome)
	procedure = list(
		/datum/surgical_step/access/incise,
		/datum/surgical_step/access/retract,
		/datum/surgical_step/treat/decompression,
		/datum/surgical_step/cauterize,
	)


// --- Chest --------------------------------------------------------------

/datum/dq_surgery/chest_decompression
	name = "Chest tube placement"
	category = "Chest"
	subcategory = "Thoracic"
	description = "Opening the pleural space to vent trapped air, letting the collapsed lung re-expand."
	body_region = "Torso"
	steps = list(
		"Incise through the skin below the armpit.",
		"Retract the intercostal muscle.",
		"Open the pleural space and release the trapped air.",
		"Cauterize the incision closed.",
	)
	tools = list("Scalpel", "Retractor", "Cautery")
	treats = list(/datum/affliction/pneumothorax)
	procedure = list(
		/datum/surgical_step/access/incise,
		/datum/surgical_step/access/retract,
		/datum/surgical_step/treat/decompression,
		/datum/surgical_step/cauterize,
	)

/datum/dq_surgery/lung_repair
	name = "Lung tissue repair"
	category = "Chest"
	subcategory = "Thoracic"
	description = "Opening the chest to mend torn or bruised lung tissue directly. Respiratory failure driven by the damaged lung recedes as it heals."
	body_region = "Torso"
	steps = list(
		"Open the chest and retract the skin.",
		"Saw through and retract the ribcage.",
		"Suture the damaged lung.",
		"Set the ribcage back together.",
		"Cauterize the incision closed.",
	)
	tools = list("Scalpel", "Retractor", "Circular saw", "FixOVein", "Bone gel", "Cautery")
	treats = list(/datum/affliction/respiratory_failure)
	repairs_organs = list(O_LUNGS)
	procedure = list(
		/datum/surgical_step/access/incise,
		/datum/surgical_step/access/retract,
		/datum/surgical_step/access/saw,
		/datum/surgical_step/access/pry_bone,
		/datum/surgical_step/treat/organ/suture,
		/datum/surgical_step/set_bone,
		/datum/surgical_step/cauterize,
	)

/datum/dq_surgery/cardiac_repair
	name = "Open cardiac repair"
	category = "Chest"
	subcategory = "Thoracic"
	description = "Opening the chest to suture damaged heart muscle. Heart damage recedes as the muscle heals; follow-up care is still needed."
	body_region = "Torso"
	steps = list(
		"Open the chest and retract the skin.",
		"Saw through and retract the ribcage.",
		"Suture the damaged cardiac tissue.",
		"Set the ribcage back together.",
		"Cauterize the incision closed.",
	)
	tools = list("Scalpel", "Retractor", "Circular saw", "FixOVein", "Bone gel", "Cautery")
	treats = list(/datum/affliction/heart_damage)
	repairs_organs = list(O_HEART)
	procedure = list(
		/datum/surgical_step/access/incise,
		/datum/surgical_step/access/retract,
		/datum/surgical_step/access/saw,
		/datum/surgical_step/access/pry_bone,
		/datum/surgical_step/treat/organ/suture,
		/datum/surgical_step/set_bone,
		/datum/surgical_step/cauterize,
	)

/datum/dq_surgery/organ_resection
	name = "Necrotic organ resection"
	category = "Chest"
	subcategory = "Organs"
	description = "Cutting dead tissue out of an internal organ before it spreads. Sutures don't touch necrosis; only resection removes it."
	body_region = "Torso, groin or head"
	steps = list(
		"Open the region and retract the tissue (and bone, where encased).",
		"Resect the necrotic tissue from the organ.",
		"Close the region in layers.",
	)
	tools = list("Scalpel", "Retractor", "Circular saw", "Bone gel", "Cautery")
	procedure = list(
		/datum/surgical_step/access/incise,
		/datum/surgical_step/access/retract,
		/datum/surgical_step/treat/organ/resection,
		/datum/surgical_step/cauterize,
	)


// --- Brain & neuro ------------------------------------------------------

/datum/dq_surgery/craniotomy
	name = "Craniotomy"
	category = "Brain"
	subcategory = "Neurological"
	description = "Opening the skull to drain a subdural bleed and relieve cranial pressure, then repairing the bruised brain tissue beneath. A brain that has already died does not recover."
	body_region = "Head"
	steps = list(
		"Open the scalp.",
		"Cut into the skull with a circular saw and lift the bone flap.",
		"Drain the bleed and relieve the pressure.",
		"Suture the injured brain tissue.",
		"Set the skull back in place.",
		"Close the scalp.",
	)
	tools = list("Scalpel", "Retractor", "Circular saw", "Scalpel", "FixOVein", "Bone gel", "Cautery")
	treats = list(/datum/affliction/subdural_hematoma)
	repairs_organs = list(O_BRAIN)
	procedure = list(
		/datum/surgical_step/access/incise,
		/datum/surgical_step/access/retract,
		/datum/surgical_step/access/saw,
		/datum/surgical_step/access/pry_bone,
		/datum/surgical_step/treat/decompression,
		/datum/surgical_step/treat/organ/suture,
		/datum/surgical_step/set_bone,
		/datum/surgical_step/cauterize,
	)


// --- Abdominal ----------------------------------------------------------

/datum/dq_surgery/laparotomy_bleeding
	name = "Exploratory laparotomy for bleeding"
	category = "Trauma"
	subcategory = "Abdominal"
	description = "Opening the abdomen to find and repair bleeding that imaging or pressure couldn't resolve."
	body_region = "Torso"
	steps = list(
		"Make a midline abdominal incision.",
		"Retract the abdominal wall.",
		"Find the source of the bleeding and repair the vessel.",
		"Close in layers.",
	)
	tools = list("Scalpel", "Retractor", "FixOVein", "Cautery")
	treats = list(/datum/affliction/internal_hemorrhage)
	procedure = list(
		/datum/surgical_step/access/incise,
		/datum/surgical_step/access/retract,
		/datum/surgical_step/treat/vessel_repair,
		/datum/surgical_step/cauterize,
	)


// --- Eyes --------------------------------------------------------------

/datum/dq_surgery/retinal_repair
	name = "Retinal repair"
	category = "Special"
	subcategory = "Ophthalmic"
	description = "Opening the orbit to repair damaged eye tissue. Vision loss from the injured eye recedes as it heals."
	body_region = "Head"
	steps = list(
		"Open the skin around the eye.",
		"Retract the lids and soft tissue.",
		"Suture the damaged eye.",
		"Close the incision.",
	)
	tools = list("Scalpel", "Retractor", "FixOVein", "Cautery")
	treats = list(/datum/affliction/ischemic_vision_loss)
	repairs_organs = list(O_EYES)
	procedure = list(
		/datum/surgical_step/access/incise,
		/datum/surgical_step/access/retract,
		/datum/surgical_step/treat/organ/suture,
		/datum/surgical_step/cauterize,
	)


// --- Synthetic ----------------------------------------------------------

/datum/dq_surgery/prosthetic_maintenance
	name = "Prosthetic maintenance"
	category = "Special"
	subcategory = "Synthetic"
	description = "Opening a prosthetic limb's maintenance hatch to weld dented plating, replace burned wiring and restore faulted components."
	body_region = "Any prosthetic part"
	steps = list(
		"Unscrew the maintenance hatch.",
		"Pry the hatch open.",
		"Weld the damaged plating and replace burned wiring.",
		"Repair faulted internal components with nanopaste.",
		"Close and secure the hatch.",
	)
	tools = list("Screwdriver", "Crowbar", "Welder", "Cable coil", "Nanopaste")
	procedure = list(
		/datum/surgical_step/access/unscrew_panel,
		/datum/surgical_step/access/open_hatch,
		/datum/surgical_step/treat/repair_plating,
		/datum/surgical_step/treat/repair_wiring,
		/datum/surgical_step/treat/organ/system_restore,
		/datum/surgical_step/close_panel,
	)
