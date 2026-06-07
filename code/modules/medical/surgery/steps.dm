// Surgery steps for procedures the upstream chain didn't have a real
// step for. Each step is a single-stage operation that completes a
// /datum/dq_surgery via its `completion_step` mapping. The actual cure
// is dispatched by the DQEdit in code/modules/surgery/surgery.dm — these
// steps just describe what the surgeon does to make it happen.
//
// Each step's `can_use` matches what the corresponding /datum/dq_surgery
// is meant to treat: there must be at least one active instance of one
// of the surgery's treated conditions on the relevant body part, so a
// surgeon can't fire the procedure on a healthy patient.

// --- Fasciotomy (compartment syndrome) ----------------------------------
//
// Cut the fascial sheath of a swollen limb to relieve compartment
// pressure. The fasciotomy needs the flesh opened; the surgeon uses a
// scalpel to slit the deep fascia.

/datum/surgery_step/fasciotomy
	surgery_name = "Fasciotomy"
	priority = 2
	allowed_tools = list(
		/obj/item/surgical/scalpel = 100,
		/obj/item/material/knife = 65,
	)
	can_infect = TRUE
	blood_level = 1
	req_open = TRUE
	min_duration = 60
	max_duration = 80

/datum/surgery_step/fasciotomy/can_use(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	if(!ishuman(target))
		return FALSE
	var/obj/item/organ/external/affected = target.get_organ(target_zone)
	if(!affected || coverage_check(user, target, affected, tool))
		return FALSE
	if(affected.robotic >= ORGAN_ROBOT)
		return FALSE
	if(affected.open < FLESH_RETRACTED)
		return FALSE
	// Only valid on limbs.
	if(!(affected.organ_tag in list(BP_L_ARM, BP_R_ARM, BP_L_LEG, BP_R_LEG)))
		return FALSE
	for(var/datum/medical_issue/condition/compartment_syndrome/C in affected.medical_issues)
		return TRUE
	return FALSE

/datum/surgery_step/fasciotomy/begin_step(mob/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	var/obj/item/organ/external/affected = target.get_organ(target_zone)
	user.visible_message(
		span_filter_notice("[user] starts slitting the fascia of [target]'s [affected.name] to release the pressure."),
		span_filter_notice("You start slitting the fascia of [target]'s [affected.name] to release the pressure."),
	)
	user.balloon_alert_visible("releasing compartment pressure in [target]'s [affected.name]", "releasing compartment pressure in \the [affected.name]")
	target.custom_pain("The pressure inside \the [affected.name] surges before easing!", 90)
	..()

/datum/surgery_step/fasciotomy/end_step(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	var/obj/item/organ/external/affected = target.get_organ(target_zone)
	user.visible_message(
		span_notice("[user] releases the trapped pressure in [target]'s [affected.name] with \the [tool]."),
		span_notice("You release the trapped pressure in [target]'s [affected.name] with \the [tool]."),
	)
	user.balloon_alert_visible("releases pressure in [target]'s [affected.name]", "released pressure in \the [affected.name]")

/datum/surgery_step/fasciotomy/fail_step(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	var/obj/item/organ/external/affected = target.get_organ(target_zone)
	user.visible_message(
		span_danger("[user]'s hand slips and gouges deep into [target]'s [affected.name]!"),
		span_danger("Your hand slips and gouges deep into [target]'s [affected.name]!"),
	)
	user.balloon_alert_visible("slips, gouging deep into [target]'s [affected.name]", "your hand slips, gouging \the [affected.name]")
	affected.take_damage(10, 0)


// --- Chest tube placement (tension pneumothorax) ------------------------

/datum/surgery_step/chest_tube
	surgery_name = "Place Chest Tube"
	priority = 2
	allowed_tools = list(
		/obj/item/surgical/scalpel = 100,
		/obj/item/surgical/hemostat = 80,
	)
	can_infect = TRUE
	blood_level = 1
	req_open = TRUE
	min_duration = 50
	max_duration = 60

/datum/surgery_step/chest_tube/can_use(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	if(!ishuman(target))
		return FALSE
	var/obj/item/organ/external/affected = target.get_organ(target_zone)
	if(!affected || coverage_check(user, target, affected, tool))
		return FALSE
	if(affected.organ_tag != BP_TORSO)
		return FALSE
	if(affected.open < FLESH_RETRACTED)
		return FALSE
	for(var/datum/medical_issue/condition/tension_pneumothorax/C in affected.medical_issues)
		return TRUE
	return FALSE

/datum/surgery_step/chest_tube/begin_step(mob/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	user.visible_message(
		span_filter_notice("[user] starts inserting a chest tube into [target]'s torso to vent the trapped air."),
		span_filter_notice("You start inserting a chest tube into [target]'s torso to vent the trapped air."),
	)
	user.balloon_alert_visible("inserting chest tube into [target]'s torso", "inserting chest tube")
	target.custom_pain("A sharp pressure releases as something gives way in your chest!", 80)
	..()

/datum/surgery_step/chest_tube/end_step(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	user.visible_message(
		span_notice("[user] vents the trapped pleural air with \the [tool]; [target]'s breathing eases."),
		span_notice("You vent the trapped pleural air with \the [tool]; [target]'s breathing eases."),
	)
	user.balloon_alert_visible("vents trapped pleural air from [target]'s chest", "vented trapped pleural air")

/datum/surgery_step/chest_tube/fail_step(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	user.visible_message(
		span_danger("[user]'s hand slips, mis-piercing [target]'s chest with \the [tool]!"),
		span_danger("Your hand slips, mis-piercing [target]'s chest with \the [tool]!"),
	)
	user.balloon_alert_visible("slips, mis-piercing [target]'s chest", "your hand slips, mis-piercing the chest")
	var/obj/item/organ/external/affected = target.get_organ(target_zone)
	if(affected)
		affected.take_damage(8, 0)


// --- Open cardiac repair (heart_damage) --------------------------------

/datum/surgery_step/cardiac_repair
	surgery_name = "Cardiac Repair"
	priority = 2
	allowed_tools = list(
		/obj/item/surgical/FixOVein = 100,
		/obj/item/stack/cable_coil = 50,
	)
	can_infect = TRUE
	blood_level = 2
	req_open = TRUE
	min_duration = 90
	max_duration = 120

/datum/surgery_step/cardiac_repair/can_use(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	if(!ishuman(target))
		return FALSE
	var/obj/item/organ/external/affected = target.get_organ(target_zone)
	if(!affected || coverage_check(user, target, affected, tool))
		return FALSE
	if(affected.organ_tag != BP_TORSO)
		return FALSE
	if(affected.open < BONE_RETRACTED)
		return FALSE
	var/obj/item/organ/internal/heart = target.internal_organs_by_name[O_HEART]
	if(!heart)
		return FALSE
	for(var/datum/medical_issue/condition/heart_damage/C in heart.medical_issues)
		return TRUE
	return FALSE

/datum/surgery_step/cardiac_repair/begin_step(mob/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	user.visible_message(
		span_filter_notice("[user] begins suturing [target]'s damaged cardiac tissue with \the [tool]."),
		span_filter_notice("You begin suturing [target]'s damaged cardiac tissue with \the [tool]."),
	)
	user.balloon_alert_visible("suturing [target]'s heart", "suturing the heart")
	target.custom_pain("Your chest feels like it's being torn in half!", 100)
	..()

/datum/surgery_step/cardiac_repair/end_step(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	user.visible_message(
		span_notice("[user] finishes suturing the damaged cardiac tissue in [target]'s chest."),
		span_notice("You finish suturing the damaged cardiac tissue in [target]'s chest."),
	)
	user.balloon_alert_visible("repairs the cardiac tissue in [target]'s chest", "repaired the cardiac tissue")
	var/obj/item/organ/internal/heart = target.internal_organs_by_name[O_HEART]
	if(heart)
		// Real heart-muscle repair: drop the organ's damage substantially
		// so the heart can actually pump again. The DQ severity drop on
		// the condition itself happens via dq_apply_surgery_cures.
		heart.damage = max(0, heart.damage - heart.max_damage * 0.6)

/datum/surgery_step/cardiac_repair/fail_step(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	user.visible_message(
		span_danger("[user]'s hand slips, tearing into [target]'s heart with \the [tool]!"),
		span_danger("Your hand slips, tearing into [target]'s heart with \the [tool]!"),
	)
	user.balloon_alert_visible("slips, tearing into [target]'s heart", "your hand slips, tearing the heart")
	var/obj/item/organ/internal/heart = target.internal_organs_by_name[O_HEART]
	if(heart)
		heart.take_damage(10, 0)


// --- Exploratory laparotomy (internal_hemorrhage in abdomen) ----------

/datum/surgery_step/exploratory_laparotomy
	surgery_name = "Exploratory Laparotomy"
	priority = 2
	allowed_tools = list(
		/obj/item/surgical/FixOVein = 100,
		/obj/item/surgical/hemostat = 80,
		/obj/item/stack/cable_coil = 60,
	)
	can_infect = TRUE
	blood_level = 2
	req_open = TRUE
	min_duration = 70
	max_duration = 90

/datum/surgery_step/exploratory_laparotomy/can_use(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	if(!ishuman(target))
		return FALSE
	var/obj/item/organ/external/affected = target.get_organ(target_zone)
	if(!affected || coverage_check(user, target, affected, tool))
		return FALSE
	if(!(affected.organ_tag in list(BP_TORSO, BP_GROIN)))
		return FALSE
	if(affected.open < FLESH_RETRACTED)
		return FALSE
	for(var/datum/medical_issue/condition/internal_hemorrhage/C in affected.medical_issues)
		return TRUE
	return FALSE

/datum/surgery_step/exploratory_laparotomy/begin_step(mob/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	var/obj/item/organ/external/affected = target.get_organ(target_zone)
	user.visible_message(
		span_filter_notice("[user] opens [target]'s [affected.name] further to find and clamp the source of bleeding."),
		span_filter_notice("You open [target]'s [affected.name] further to find and clamp the source of bleeding."),
	)
	user.balloon_alert_visible("clamping the bleed in [target]'s [affected.name]", "clamping the bleed in \the [affected.name]")
	target.custom_pain("A pressure deep in your belly eases as something gives way!", 90)
	..()

/datum/surgery_step/exploratory_laparotomy/end_step(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	var/obj/item/organ/external/affected = target.get_organ(target_zone)
	user.visible_message(
		span_notice("[user] clamps off the source of the internal bleeding in [target]'s [affected.name]."),
		span_notice("You clamp off the source of the internal bleeding in [target]'s [affected.name]."),
	)
	user.balloon_alert_visible("controls the bleed in [target]'s [affected.name]", "controlled the bleed in \the [affected.name]")
	// Remove any active internal wounds — the bleeders that drove the
	// internal_hemorrhage condition. The DQ side will drop the condition
	// severity separately via dq_apply_surgery_cures.
	for(var/datum/wound/W in affected.wounds)
		if(W.internal)
			affected.wounds -= W
	affected.update_damages()

/datum/surgery_step/exploratory_laparotomy/fail_step(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	var/obj/item/organ/external/affected = target.get_organ(target_zone)
	user.visible_message(
		span_danger("[user]'s hand slips, tearing further into [target]'s [affected.name]!"),
		span_danger("Your hand slips, tearing further into [target]'s [affected.name]!"),
	)
	user.balloon_alert_visible("slips, tearing [target]'s [affected.name]", "your hand slips, tearing \the [affected.name]")
	affected.take_damage(8, 0)


// --- Retinal repair (ischemic_vision_loss) -----------------------------

/datum/surgery_step/retinal_repair
	surgery_name = "Retinal Repair"
	priority = 2
	allowed_tools = list(
		/obj/item/surgical/FixOVein = 100,
	)
	can_infect = TRUE
	blood_level = 1
	req_open = FALSE
	min_duration = 80
	max_duration = 100

/datum/surgery_step/retinal_repair/can_use(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	if(!ishuman(target))
		return FALSE
	// Retinal work is on the eyes zone, but the player targets the head
	// or the eye zone depending on the UI. Accept either.
	if(!(target_zone in list(O_EYES, BP_HEAD)))
		return FALSE
	var/obj/item/organ/internal/eyes = target.internal_organs_by_name[O_EYES]
	if(!eyes)
		return FALSE
	for(var/datum/medical_issue/condition/ischemic_vision_loss/C in eyes.medical_issues)
		return TRUE
	return FALSE

/datum/surgery_step/retinal_repair/begin_step(mob/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	user.visible_message(
		span_filter_notice("[user] begins repairing the damaged retina in [target]'s eye with \the [tool]."),
		span_filter_notice("You begin repairing the damaged retina in [target]'s eye with \the [tool]."),
	)
	user.balloon_alert_visible("repairing the retina in [target]'s eye", "repairing the retina")
	target.custom_pain("A pinprick of bright light flashes inside your eye!", 60)
	..()

/datum/surgery_step/retinal_repair/end_step(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	user.visible_message(
		span_notice("[user] reattaches the torn retina in [target]'s eye."),
		span_notice("You reattach the torn retina in [target]'s eye."),
	)
	user.balloon_alert_visible("reattaches the retina in [target]'s eye", "reattached the retina")
	var/obj/item/organ/internal/eyes = target.internal_organs_by_name[O_EYES]
	if(eyes)
		eyes.damage = max(0, eyes.damage - eyes.max_damage * 0.5)

/datum/surgery_step/retinal_repair/fail_step(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	user.visible_message(
		span_danger("[user]'s hand slips, scoring [target]'s retina with \the [tool]!"),
		span_danger("Your hand slips, scoring [target]'s retina with \the [tool]!"),
	)
	user.balloon_alert_visible("slips, scoring [target]'s retina", "your hand slips, scoring the retina")
	var/obj/item/organ/internal/eyes = target.internal_organs_by_name[O_EYES]
	if(eyes)
		eyes.take_damage(5, 0)
