// Eye and ear surgery: the cures for what no drug reaches (a destroyed eardrum, cataracts). Both work on the head, once it is open.

/// Ear damage a repaired eardrum is left with: the drug (cochlexine) or time finishes the healing from here.
#define EAR_DAMAGE_AFTER_REPAIR 40

/datum/surgical_step/repair_eardrum
	name = "Repair Eardrum"
	phase = SURGERY_PHASE_OPERATE
	priority = 2
	finds = TRUE
	book_category = "Head"
	about = "Rebuilding an eardrum that blast or noise destroyed (the body scanner reads it as severe, permanent-looking ear damage). A drug cannot do this; once the drum is rebuilt, cochlexine finishes healing the ear."
	allowed_tools = list(
		/obj/item/surgical/hemostat = 100,
		/obj/item/surgical/FixOVein = 80,
	)
	zones = list(BP_HEAD)
	needs_full_access = FALSE
	min_depth = FLESH_RETRACTED
	duration = 6 SECONDS
	pain = 50
	begin_text = "rebuilding the eardrum in"
	end_text = "rebuilds the eardrum in"
	fail_text = "slips, tearing the ear canal of"
	pain_text = "A needle-sharp pain stabs into your %PART%!"
	complication_kind = INJURY_PIERCE
	complication_amount = 8

/datum/surgical_step/repair_eardrum/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	return target.ear_damage >= EAR_DAMAGE_PERMANENT

/datum/surgical_step/repair_eardrum/findings(mob/living/carbon/human/target, obj/item/organ/external/part, full)
	. = list()
	if(part.organ_tag == BP_HEAD && target.ear_damage >= EAR_DAMAGE_PERMANENT)
		. += list(surgical_finding_row("destroyed eardrum", part, target, src))

/datum/surgical_step/repair_eardrum/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	if(target.ear_damage < EAR_DAMAGE_PERMANENT)
		return
	target.set_ear_damage(EAR_DAMAGE_AFTER_REPAIR)
	log_game("SURGERY: [key_name(user)] rebuilt the eardrum of [key_name(target)] (ear damage now [target.ear_damage])")

/datum/surgical_step/remove_cataracts
	name = "Remove Cataracts"
	phase = SURGERY_PHASE_OPERATE
	priority = 2
	finds = TRUE
	book_category = "Head"
	about = "Cutting a clouded lens out of the eye so the patient can see again (the body scanner reads cataracts). Imidazoline mends the eye itself but cannot clear a lens that has clouded over."
	allowed_tools = list(
		/obj/item/surgical/scalpel = 100,
		/obj/item/surgical/bioregen = 80,
		/obj/item/material/knife = 40,
	)
	excluded_tools = list(/obj/item/surgical/scalpel/ripper)
	zones = list(BP_HEAD)
	needs_full_access = FALSE
	min_depth = FLESH_RETRACTED
	duration = 6 SECONDS
	pain = 50
	begin_text = "clearing the cataracts from"
	end_text = "clears the cataracts from"
	fail_text = "slips, cutting into the eye in"
	pain_text = "Something sharp presses into your eye!"
	complication_kind = INJURY_CUT
	complication_amount = 8

/// The patient's organic eyes, when they are blind from cataracts rather than from the eyes being gone or prosthetic.
/datum/surgical_step/remove_cataracts/proc/cataract_eyes(mob/living/carbon/human/target)
	RETURN_TYPE(/obj/item/organ/internal/eyes)
	if(!(target.sdisabilities & BLIND))
		return null
	var/obj/item/organ/internal/eyes/E = target.organ_in(O_EYES)
	if(!istype(E) || E.is_robotic())
		return null
	return E

/datum/surgical_step/remove_cataracts/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	return !!cataract_eyes(target)

/datum/surgical_step/remove_cataracts/findings(mob/living/carbon/human/target, obj/item/organ/external/part, full)
	. = list()
	var/obj/item/organ/internal/eyes/E = cataract_eyes(target)
	if(part.organ_tag == BP_HEAD && E)
		. += list(surgical_finding_row("cataracts", part, E, src))

/datum/surgical_step/remove_cataracts/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	if(!cataract_eyes(target))
		return
	target.set_sdisabilities(target.sdisabilities & (~BLIND))
	log_game("SURGERY: [key_name(user)] removed the cataracts of [key_name(target)]")
