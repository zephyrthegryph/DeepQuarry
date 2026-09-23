// Access and closure steps.
//
// Access steps open the limb's surgical site one layer at a time; closure
// steps are treatments aimed at the site itself (see incision.dm).
//
// Organic:   incise -> retract -> (encased) saw -> pry bones
//            set bones (TREAT_BONE_SETTING) -> cauterize (TREAT_SURGICAL_CLOSURE)
// Synthetic: unscrew panel -> open hatch
//            close panel (TREAT_PANEL_CLOSURE)

/datum/surgical_step/access
	abstract_type = /datum/surgical_step/access
	phase = SURGERY_PHASE_ACCESS
	priority = 1
	/// Depth the site is at after this step.
	var/opens_to = INCISION_MADE
	/// Only on encased limbs (bone layers).
	var/encased_only = FALSE
	/// The step clamps the bleeders as it opens (laser / managed incisions).
	var/clamps = FALSE

/datum/surgical_step/access/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	if(encased_only && part.surgical_full_access() != BONE_RETRACTED)
		return FALSE
	return part.surgical_depth() < opens_to

/// Opening is harm to the tissue, not treatment: the site is created or
/// deepened on the limb, remembering how sterile the surface was.
/datum/surgical_step/access/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	var/cleanliness = target.get_surgery_cleanliness(user)
	var/datum/affliction/surgical_incision/I = part.open_surgical_site(opens_to, isnull(cleanliness) ? 0 : cleanliness)
	if(I && clamps)
		target.mend(TREAT_HEMOSTATIC, 1, part)
	log_game("SURGERY: [key_name(user)] [name] on [key_name(target)] [part]: site at depth [part.surgical_depth()]")


// --- Organic --------------------------------------------------------------------------

/datum/surgical_step/access/incise
	name = "Create Incision"
	allowed_tools = list(
		/obj/item/surgical/scalpel = 100,
		/obj/item/material/knife = 75,
		/obj/item/material/shard = 50,
	)
	excluded_tools = list(
		/obj/item/surgical/scalpel/laser1,
		/obj/item/surgical/scalpel/laser2,
		/obj/item/surgical/scalpel/laser3,
		/obj/item/surgical/scalpel/manager,
	)
	max_depth = SURGERY_DEPTH_CLOSED
	opens_to = INCISION_MADE
	duration = 4 SECONDS
	begin_text = "making an incision on"
	end_text = "makes an incision on"
	fail_text = "slips, slicing into the wrong place on"
	pain_text = "You feel a horrible pain as if from a sharp knife in your %PART%!"
	complication_kind = INJURY_CUT
	complication_amount = 10

/// Laser scalpels cauterize as they cut: no bleeders to clamp.
/datum/surgical_step/access/incise/laser
	name = "Create Bloodless Incision"
	priority = 2
	excluded_tools = null
	allowed_tools = list(
		/obj/item/surgical/scalpel/laser3 = 95,
		/obj/item/surgical/scalpel/laser2 = 85,
		/obj/item/surgical/scalpel/laser1 = 75,
	)
	clamps = TRUE
	begin_text = "making a bloodless incision on"
	end_text = "makes a bloodless incision on"
	fail_text = "slips, burning a gash into"
	complication_kind = INJURY_BURN

/// The incision management system opens, clamps and retracts in one go.
/datum/surgical_step/access/incise/managed
	name = "Create Prepared Incision"
	priority = 2
	excluded_tools = null
	allowed_tools = list(/obj/item/surgical/scalpel/manager = 100)
	opens_to = FLESH_RETRACTED
	clamps = TRUE
	duration = 6 SECONDS
	begin_text = "constructing a prepared incision on"
	end_text = "constructs a prepared incision on"
	fail_text = "jolts as the system sparks, ripping a hole in"
	complication_amount = 20

/datum/surgical_step/access/retract
	name = "Retract Skin"
	allowed_tools = list(
		/obj/item/surgical/retractor = 100,
		/obj/item/material/kitchen/utensil/fork = 50,
	)
	allowed_tool_qualities = list(TOOL_CROWBAR = 75)
	min_depth = INCISION_MADE
	max_depth = INCISION_MADE
	opens_to = FLESH_RETRACTED
	duration = 3 SECONDS
	begin_text = "prying open the incision on"
	end_text = "holds open the incision on"
	fail_text = "slips, tearing the edges of the incision on"
	pain_text = "It feels like the skin on your %PART% is on fire!"
	complication_kind = INJURY_PIERCE
	complication_amount = 12

/datum/surgical_step/access/saw
	name = "Cut Bone"
	allowed_tools = list(
		/obj/item/surgical/circular_saw = 100,
		/obj/item/material/knife/machete/hatchet = 75,
	)
	excluded_tools = list(/obj/item/surgical/circular_saw/manager)
	allowed_tool_qualities = list(TOOL_CROWBAR = 50)
	min_depth = FLESH_RETRACTED
	max_depth = FLESH_RETRACTED
	opens_to = BONE_CUT
	encased_only = TRUE
	duration = 6 SECONDS
	pain = 60
	blood_level = 2
	begin_text = "cutting through the bone of"
	end_text = "cuts through the bone of"
	fail_text = "slips, cracking the bone of"
	pain_text = "Something hurts horribly in your %PART%!"
	complication_kind = INJURY_BLUNT
	complication_amount = 15

/// A failed saw cracks the bone.
/datum/surgical_step/access/saw/complicate(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	..()
	part?.fracture()

/// The energetic bone diverter cuts and spreads in one go.
/datum/surgical_step/access/saw/managed
	name = "Advanced Cut Bone"
	priority = 2
	allowed_tools = list(/obj/item/surgical/circular_saw/manager = 100)
	allowed_tool_qualities = null
	excluded_tools = null
	opens_to = BONE_RETRACTED
	begin_text = "diverting the bone of"
	end_text = "diverts the bone of"

/datum/surgical_step/access/pry_bone
	name = "Retract Bone"
	allowed_tools = list(/obj/item/surgical/retractor = 100)
	allowed_tool_qualities = list(TOOL_CROWBAR = 75)
	min_depth = BONE_CUT
	max_depth = BONE_CUT
	opens_to = BONE_RETRACTED
	encased_only = TRUE
	duration = 4 SECONDS
	pain = 60
	begin_text = "forcing apart the bone of"
	end_text = "holds apart the bone of"
	fail_text = "slips, cracking the bone of"
	pain_text = "Something hurts horribly in your %PART%!"
	complication_kind = INJURY_BLUNT
	complication_amount = 20

/datum/surgical_step/access/pry_bone/complicate(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	..()
	part?.fracture()


// --- Site treatment: clamp, set, close ----------------------------------------------------

/datum/surgical_step/clamp_bleeders
	name = "Clamp Bleeders"
	phase = SURGERY_PHASE_ACCESS
	priority = 1
	allowed_tools = list(
		/obj/item/surgical/hemostat = 100,
		/obj/item/stack/cable_coil = 75,
		/obj/item/assembly/mousetrap = 25,
	)
	part_biology = BIOLOGY_ORGANIC
	min_depth = INCISION_MADE
	treatments = list(TREAT_HEMOSTATIC = 30)
	duration = 3 SECONDS
	begin_text = "clamping bleeders in"
	end_text = "clamps the bleeders in"
	fail_text = "slips, tearing blood vessels in"
	pain_text = "The pain in your %PART% is maddening!"
	// A torn vessel: an arterial bleed.
	complication_kind = INJURY_CUT
	complication_amount = 10
	complication_affliction = /datum/affliction/wound/internal_bleeding

/datum/surgical_step/clamp_bleeders/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	var/datum/affliction/surgical_incision/I = part.get_incision()
	return I?.needs_clamp()

/datum/surgical_step/set_bone
	name = "Set Bone"
	phase = SURGERY_PHASE_CLOSE
	priority = 1
	allowed_tools = list(
		/obj/item/surgical/bonesetter = 100,
		/obj/item/surgical/bonegel = 100,
		/obj/item/surgical/bone_clamp = 100,
	)
	allowed_tool_qualities = list(TOOL_WRENCH = 75, TOOL_SCREWDRIVER = 60)
	min_depth = FLESH_RETRACTED
	treatments = list(TREAT_BONE_SETTING = 100)
	duration = 4 SECONDS
	pain = 50
	begin_text = "setting the bone in"
	end_text = "sets the bone in"
	fail_text = "slips, grinding the broken bone in"
	pain_text = "Something in your %PART% is causing you a lot of pain!"
	complication_kind = INJURY_BLUNT
	complication_amount = 10

/// Needed for an open bone layer, a fracture condition, or a broken bone.
/datum/surgical_step/set_bone/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	var/datum/affliction/surgical_incision/I = part.get_incision()
	if(I?.needs_bone_setting())
		return TRUE
	if(part.status & ORGAN_BROKEN)
		return TRUE
	return ..()

/// Bone setting also mends the limb's fracture state (ORGAN_BROKEN), which
/// isn't an affliction yet.
/datum/surgical_step/set_bone/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	..()
	if(part.status & ORGAN_BROKEN)
		part.mend_fracture()

/datum/surgical_step/cauterize
	name = "Cauterize Incision"
	phase = SURGERY_PHASE_CLOSE
	allowed_tools = list(
		/obj/item/surgical/cautery = 100,
		/obj/item/clothing/mask/smokable/cigarette = 75,
		/obj/item/flame/lighter = 50,
		/obj/item/weldingtool = 25,
	)
	part_biology = BIOLOGY_ORGANIC
	min_depth = INCISION_MADE
	max_depth = FLESH_RETRACTED
	treatments = list(TREAT_SURGICAL_CLOSURE = 100)
	duration = 4 SECONDS
	begin_text = "cauterizing the incision on"
	end_text = "cauterizes the incision on"
	fail_text = "slips, leaving a burn on"
	pain_text = "Your %PART% is being burned!"
	complication_kind = INJURY_BURN
	complication_amount = 3

/datum/surgical_step/cauterize/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	var/datum/affliction/surgical_incision/I = part.get_incision()
	return I?.can_close()


// --- Synthetic -----------------------------------------------------------------------------

/datum/surgical_step/access/unscrew_panel
	name = "Unscrew Hatch"
	part_biology = BIOLOGY_SYNTHETIC | BIOLOGY_NANOFORM
	allowed_tool_qualities = list(TOOL_SCREWDRIVER = 100)
	allowed_tools = list(/obj/item/coin = 50, /obj/item/material/knife = 50)
	max_depth = SURGERY_DEPTH_CLOSED
	opens_to = INCISION_MADE
	duration = 3 SECONDS
	pain = 0
	infection_risk = FALSE
	blood_level = 0
	begin_text = "unscrewing the maintenance hatch on"
	end_text = "unscrews the maintenance hatch on"
	fail_text = "slips, scratching the plating of"
	complication_kind = INJURY_BLUNT
	complication_amount = 5

/datum/surgical_step/access/open_hatch
	name = "Open Hatch"
	part_biology = BIOLOGY_SYNTHETIC | BIOLOGY_NANOFORM
	allowed_tools = list(/obj/item/surgical/retractor = 100)
	allowed_tool_qualities = list(TOOL_CROWBAR = 100)
	min_depth = INCISION_MADE
	max_depth = INCISION_MADE
	opens_to = FLESH_RETRACTED
	duration = 3 SECONDS
	pain = 0
	infection_risk = FALSE
	blood_level = 0
	begin_text = "prying open the maintenance hatch on"
	end_text = "opens the maintenance hatch on"
	fail_text = "slips, denting the plating of"
	complication_kind = INJURY_BLUNT
	complication_amount = 5

/datum/surgical_step/close_panel
	name = "Close Hatch"
	phase = SURGERY_PHASE_CLOSE
	allowed_tool_qualities = list(TOOL_SCREWDRIVER = 100)
	allowed_tools = list(/obj/item/coin = 50, /obj/item/material/knife = 50)
	min_depth = INCISION_MADE
	max_depth = FLESH_RETRACTED
	treatments = list(TREAT_PANEL_CLOSURE = 100)
	duration = 3 SECONDS
	pain = 0
	infection_risk = FALSE
	blood_level = 0
	begin_text = "securing the maintenance hatch on"
	end_text = "secures the maintenance hatch on"
	fail_text = "slips, stripping a screw on"
	complication_kind = INJURY_BLUNT
	complication_amount = 3

/datum/surgical_step/close_panel/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	var/datum/affliction/surgical_incision/I = part.get_incision()
	return I?.can_close()
