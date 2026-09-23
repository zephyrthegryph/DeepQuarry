// Operate steps that treat: each delivers TREAT_* mechanisms to the limb, the
// region, or one organ through mend(). They offer themselves only when an
// affliction in scope is treated by their mechanism, so a new condition that
// needs surgery only has to declare the surgical tag in its treated_by.

/datum/surgical_step/treat
	abstract_type = /datum/surgical_step/treat
	phase = SURGERY_PHASE_OPERATE
	priority = 2
	needs_full_access = TRUE
	duration = 5 SECONDS
	pain = 60


// --- Organ repair ------------------------------------------------------------------------
// One organ at a time. Each step cures only the lesions its mechanism fully
// repairs: sutures close tears, contusions, ischemic and toxic injury;
// resection removes necrosis; a system restore repairs prosthetic organs.

/// Organ repair: one chosen organ. An organ beyond repair can still be worked
/// on; the surgeon sees what's wrong and nothing heals.
/datum/surgical_step/treat/organ
	abstract_type = /datum/surgical_step/treat/organ
	scope = SURGERY_SCOPE_ORGAN
	// The organ decides: a prosthetic organ can sit in an organic torso.
	part_biology = BIOLOGY_ALL

/datum/surgical_step/treat/organ/location_needs_treatment(mob/living/carbon/human/target, location)
	var/obj/item/organ/internal/I = location
	if(istype(I) && I.is_beyond_repair())
		var/organ_biology = target.body.biology_of(I)
		for(var/tag in treatments)
			if(treatment_tag_biology(tag) & organ_biology)
				return TRUE
		return FALSE
	return ..()

/datum/surgical_step/treat/organ/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	var/obj/item/organ/internal/I = work_target
	if(istype(I) && I.is_beyond_repair())
		to_chat(user, span_warning(I.beyond_repair_perception(user)))
		log_game("SURGERY: [key_name(user)] [name] on [key_name(target)] [I]: beyond repair, nothing healed")
		return
	return ..()

/datum/surgical_step/treat/organ/suture
	name = "Repair Organ"
	allowed_tools = list(
		/obj/item/surgical/FixOVein = 100,
		/obj/item/stack/medical/advanced/bruise_pack = 60,
		/obj/item/stack/cable_coil = 40,
	)
	treatments = list(TREAT_SURGICAL_REPAIR = 100)
	duration = 6 SECONDS
	blood_level = 2
	begin_text = "suturing"
	end_text = "sutures"
	fail_text = "slips, tearing"
	pain_text = "Someone's digging needles into your %PART%!"
	// A nicked organ: a laceration lesion.
	complication_kind = INJURY_CUT
	complication_amount = 8
	complication_affliction = /datum/affliction/lesion/laceration

/datum/surgical_step/treat/organ/resection
	name = "Resect Necrotic Tissue"
	allowed_tools = list(
		/obj/item/surgical/scalpel = 100,
		/obj/item/material/knife = 50,
	)
	excluded_tools = list(/obj/item/surgical/scalpel/ripper)
	treatments = list(TREAT_RESECTION = 100)
	duration = 6 SECONDS
	blood_level = 2
	begin_text = "cutting the dead tissue out of"
	end_text = "resects the dead tissue from"
	fail_text = "slips, cutting healthy tissue in"
	complication_kind = INJURY_CUT
	complication_amount = 8
	complication_affliction = /datum/affliction/lesion/laceration

/datum/surgical_step/treat/organ/system_restore
	name = "Repair Prosthetic Organ"
	allowed_tools = list(/obj/item/stack/nanopaste = 100)
	allowed_tool_qualities = list(TOOL_MULTITOOL = 60)
	treatments = list(TREAT_SYSTEM_RESTORE = 100)
	pain = 0
	infection_risk = FALSE
	blood_level = 0
	begin_text = "repairing the components of"
	end_text = "repairs the components of"
	fail_text = "slips, shorting out"
	complication_kind = INJURY_ELECTRIC
	complication_amount = 8
	complication_affliction = /datum/affliction/lesion/synthetic/component_fault


// --- Limb and regional procedures ------------------------------------------------------------

/datum/surgical_step/treat/vessel_repair
	name = "Repair Blood Vessels"
	allowed_tools = list(
		/obj/item/surgical/FixOVein = 100,
		/obj/item/stack/cable_coil = 50,
	)
	scope = SURGERY_SCOPE_REGION
	needs_full_access = FALSE
	min_depth = FLESH_RETRACTED
	treatments = list(TREAT_VESSEL_REPAIR = 100)
	blood_level = 2
	begin_text = "repairing the torn vessels in"
	end_text = "repairs the torn vessels in"
	fail_text = "slips, tearing a vessel in"
	pain_text = "The pain in your %PART% is unbearable!"
	// A cut vessel: an arterial bleed.
	complication_kind = INJURY_CUT
	complication_amount = 10
	complication_affliction = /datum/affliction/wound/internal_bleeding

/datum/surgical_step/treat/tendon_repair
	name = "Repair Tendon"
	allowed_tools = list(/obj/item/surgical/FixOVein = 100)
	zones = list(BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND, BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT)
	needs_full_access = FALSE
	min_depth = FLESH_RETRACTED
	treatments = list(TREAT_TENDON_REPAIR = 100)
	begin_text = "rejoining the severed tendon in"
	end_text = "rejoins the severed tendon in"
	fail_text = "slips, tearing further at the tendon in"
	pain_text = "Sharp, stabbing pain runs the length of your %PART%!"
	complication_kind = INJURY_CUT
	complication_amount = 5

/// Fasciotomy on a limb, chest tube on the torso, burr hole on the head:
/// releasing pressure trapped in a compartment.
/datum/surgical_step/treat/decompression
	name = "Surgical Decompression"
	allowed_tools = list(
		/obj/item/surgical/scalpel = 100,
		/obj/item/surgical/hemostat = 80,
		/obj/item/material/knife = 65,
	)
	excluded_tools = list(/obj/item/surgical/scalpel/ripper)
	scope = SURGERY_SCOPE_REGION
	needs_full_access = FALSE
	min_depth = FLESH_RETRACTED
	treatments = list(TREAT_DECOMPRESSION = 100)
	begin_text = "releasing the trapped pressure in"
	end_text = "releases the trapped pressure in"
	fail_text = "slips, gouging deep into"
	pain_text = "The pressure inside your %PART% surges before easing!"
	complication_kind = INJURY_CUT
	complication_amount = 10

/datum/surgical_step/treat/debridement
	name = "Debride Dead Tissue"
	allowed_tools = list(
		/obj/item/surgical/scalpel = 100,
		/obj/item/surgical/bioregen = 90,
		/obj/item/material/knife = 50,
	)
	excluded_tools = list(/obj/item/surgical/scalpel/ripper)
	needs_full_access = FALSE
	min_depth = FLESH_RETRACTED
	treatments = list(TREAT_RESECTION = 100)
	blood_level = 2
	begin_text = "cutting away the dead tissue in"
	end_text = "debrides the dead tissue in"
	fail_text = "slips, cutting healthy flesh in"
	complication_kind = INJURY_CUT
	complication_amount = 15

/datum/surgical_step/treat/repair_flesh
	name = "Repair Flesh"
	allowed_tools = list(
		/obj/item/stack/medical/advanced/bruise_pack = 100,
		/obj/item/stack/medical/bruise_pack = 100,
		/obj/item/tape_roll = 40,
		/obj/item/taperoll = 10,
	)
	part_biology = BIOLOGY_ORGANIC
	needs_full_access = FALSE
	min_depth = INCISION_MADE
	treatments = list(TREAT_TISSUE_REPAIR = 40)
	priority = 1
	pain = 30
	begin_text = "repairing the torn flesh of"
	end_text = "repairs the torn flesh of"
	fail_text = "slips, tearing"
	complication_kind = INJURY_CUT
	complication_amount = 5

/datum/surgical_step/treat/repair_burns
	name = "Repair Burns"
	allowed_tools = list(
		/obj/item/stack/medical/advanced/ointment = 100,
		/obj/item/stack/medical/ointment = 100,
		/obj/item/tape_roll = 30,
		/obj/item/taperoll = 10,
	)
	part_biology = BIOLOGY_ORGANIC
	needs_full_access = FALSE
	min_depth = INCISION_MADE
	treatments = list(TREAT_BURN_CARE = 40)
	priority = 1
	pain = 30
	begin_text = "grafting the burned skin of"
	end_text = "grafts the burned skin of"
	fail_text = "slips, scraping"
	complication_kind = INJURY_BURN
	complication_amount = 5

/datum/surgical_step/treat/extract_foreign_body
	name = "Extract Foreign Body"
	allowed_tools = list(
		/obj/item/surgical/hemostat = 100,
		/obj/item/material/kitchen/utensil/fork = 50,
	)
	allowed_tool_qualities = list(TOOL_WIRECUTTER = 75)
	scope = SURGERY_SCOPE_REGION
	treatments = list(TREAT_FOREIGN_BODY_REMOVAL = 100)
	begin_text = "extracting foreign material from"
	end_text = "extracts foreign material from"
	fail_text = "slips, tearing"
	complication_kind = INJURY_CUT
	complication_amount = 10

/datum/surgical_step/treat/reoxygenate
	name = "Reoxygenate Tissue"
	allowed_tools = list(/obj/item/surgical/bioregen = 100)
	scope = SURGERY_SCOPE_REGION
	treatments = list(TREAT_OXYGENATION = 50)
	priority = 1
	begin_text = "reoxygenating the tissue in"
	end_text = "reoxygenates the tissue in"
	fail_text = "slips, scraping"
	complication_kind = INJURY_BLUNT
	complication_amount = 5

/// Only offered for afflictions that need oxygenation surgically: anything a
/// dose of dexalin would treat isn't worth opening someone up for.
/datum/surgical_step/treat/reoxygenate/location_needs_treatment(mob/living/carbon/human/target, location)
	for(var/datum/affliction/custom/A in target.body.afflictions_at(location))
		if(A.cure_surgery == TREAT_OXYGENATION)
			return TRUE
	return FALSE

/datum/surgical_step/treat/lithotripsy
	name = "Ultrasound Lithotripsy"
	allowed_tools = list(/obj/item/autopsy_scanner = 100)
	scope = SURGERY_SCOPE_REGION
	treatments = list(TREAT_LITHOTRIPSY = 100)
	pain = 20
	infection_risk = FALSE
	blood_level = 0
	begin_text = "breaking up deposits in"
	end_text = "breaks up the deposits in"
	fail_text = "slips, bruising"
	complication_kind = INJURY_BLUNT
	complication_amount = 5


// --- Synthetic limb repair ---------------------------------------------------------------

/datum/surgical_step/treat/repair_plating
	name = "Repair Robotic Brute"
	allowed_tool_qualities = list(TOOL_WELDER = 100)
	allowed_tools = list(/obj/item/stack/nanopaste = 90)
	needs_full_access = FALSE
	min_depth = FLESH_RETRACTED
	treatments = list(TREAT_PLATING_REPAIR = 40)
	priority = 1
	pain = 0
	infection_risk = FALSE
	blood_level = 0
	begin_text = "welding the damaged plating of"
	end_text = "welds the damaged plating of"
	fail_text = "slips, scorching"
	complication_kind = INJURY_BURN
	complication_amount = 5

/// A welder must be lit and fuelled.
/datum/surgical_step/treat/repair_plating/tool_quality(obj/item/tool)
	. = ..()
	if(. && istype(tool, /obj/item/weldingtool))
		var/obj/item/weldingtool/welder = tool
		if(!welder.isOn())
			return 0

/datum/surgical_step/treat/repair_wiring
	name = "Repair Robotic Burn"
	allowed_tools = list(/obj/item/stack/cable_coil = 100, /obj/item/stack/nanopaste = 90)
	needs_full_access = FALSE
	min_depth = FLESH_RETRACTED
	treatments = list(TREAT_WIRING_REPAIR = 40)
	priority = 1
	pain = 0
	infection_risk = FALSE
	blood_level = 0
	begin_text = "replacing the burned wiring in"
	end_text = "replaces the burned wiring in"
	fail_text = "slips, shorting"
	complication_kind = INJURY_ELECTRIC
	complication_amount = 5

/datum/surgical_step/treat/recalibrate
	name = "Recalibrate Actuators"
	allowed_tool_qualities = list(TOOL_MULTITOOL = 100)
	needs_full_access = FALSE
	min_depth = FLESH_RETRACTED
	treatments = list(TREAT_CALIBRATION = 100)
	priority = 1
	pain = 0
	infection_risk = FALSE
	blood_level = 0
	begin_text = "recalibrating the actuators of"
	end_text = "recalibrates the actuators of"
	fail_text = "slips, misaligning"
	complication_kind = INJURY_ELECTRIC
	complication_amount = 3


// --- Hook for organs past saving ------------------------------------------------------------

// is_beyond_repair() (organ_integrity.dm, brain override in brain.dm) is the
// single gate in the organ repair path: the step still runs, the surgeon
// perceives why nothing takes, and nothing heals.

/// What the surgeon sees in an organ past saving (in character, never rules).
/obj/item/organ/internal/proc/beyond_repair_perception(mob/living/user)
	return "\The [src] is necrotic through and through; there's nothing left to mend."
