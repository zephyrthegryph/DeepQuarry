/datum/surgical_step/set_bone
	name = "Set Bone"
	finds = TRUE
	book_category = "Bone"
	about = "Re-aligning a broken bone and holding it with bone gel or a setter, and closing a sawn bone layer."
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

/// Needed for an open bone layer or a fracture. TREAT_BONE_SETTING mends the
/// fracture affliction, and with it the fracture.
/datum/surgical_step/set_bone/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	var/datum/affliction/surgical_incision/I = part.get_incision()
	if(I?.needs_bone_setting())
		return TRUE
	if(part.is_fractured())
		return TRUE
	return ..()


/// A bone that knitted crooked cannot be set: it has to be broken again first. Breaking it hands the limb a fresh fracture, which
/// Set Bone then answers to like any other; nothing about the order is fixed, the surgeon can do anything else in the open limb
/// between the two.
/datum/surgical_step/rebreak_bone
	name = "Break Bone Again"
	phase = SURGERY_PHASE_OPERATE
	priority = 2
	finds = TRUE
	book_category = "Bone"
	about = "Breaking a crooked, healed-over fracture again so that it can be set straight."
	allowed_tools = list(
		/obj/item/surgical/bonesetter = 100,
		/obj/item/surgical/bone_clamp = 75,
	)
	allowed_tool_qualities = list(TOOL_WRENCH = 50)
	part_biology = BIOLOGY_ORGANIC
	min_depth = FLESH_RETRACTED
	extra_treats = list(/datum/affliction/malunion)
	duration = 5 SECONDS
	pain = 80
	blood_level = 2
	begin_text = "forcing the crooked bone to break again in"
	end_text = "breaks the crooked bone again in"
	fail_text = "slips, shattering the bone of"
	pain_text = "Your %PART% is being broken all over again!"
	complication_kind = INJURY_BLUNT
	complication_amount = 15

/// The crooked fracture on the limb, if it has one.
/datum/surgical_step/rebreak_bone/proc/crooked_fracture(mob/living/carbon/human/target, obj/item/organ/external/part)
	RETURN_TYPE(/datum/affliction/malunion)
	return target.body.find_affliction(/datum/affliction/malunion, part)

/datum/surgical_step/rebreak_bone/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	return !!crooked_fracture(target, part)

/datum/surgical_step/rebreak_bone/findings(mob/living/carbon/human/target, obj/item/organ/external/part, full)
	. = list()
	var/datum/affliction/malunion/M = crooked_fracture(target, part)
	if(M)
		. += list(surgical_finding_row(M.name, part, M, src))

/datum/surgical_step/rebreak_bone/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	var/datum/affliction/malunion/M = crooked_fracture(target, part)
	if(!M)
		return
	M.cure()
	part.fracture()
	log_game("SURGERY: [key_name(user)] broke the crooked bone in [key_name(target)]'s [part] again (now fractured: [part.is_fractured()])")
