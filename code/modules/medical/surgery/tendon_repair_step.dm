// Tendon repair surgical step.
//
// Single-step suture-the-tendon procedure. Runs on a limb that has the
// flesh retracted (same access stage as nerve / vein work) and clears
// any tendon_severed condition on the limb via the dq_apply_surgery_cures
// hook in surgery.dm. Mapped from /datum/dq_surgery/tendon_repair.
//
// Tool: FixOVein (also used by the vessel-repair step in other.dm — it's
// the codebase's general fine-suture tool). Surgical stapler-class tools
// don't exist as compiled items, so we reuse FixOVein and let the surgery
// description in the book call it "stapling" for flavour.

/datum/surgery_step/fix_tendon
	surgery_name = "Repair Tendon"
	priority = 2
	allowed_tools = list(
		/obj/item/surgical/FixOVein = 100,
	)
	can_infect = TRUE
	blood_level = 1
	req_open = TRUE

	min_duration = 50
	max_duration = 50

/datum/surgery_step/fix_tendon/can_use(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	if(!ishuman(target))
		return FALSE
	var/obj/item/organ/external/affected = target.get_organ(target_zone)
	if(!affected)
		return FALSE
	if(coverage_check(user, target, affected, tool))
		return FALSE
	if(affected.robotic >= ORGAN_ROBOT)
		return FALSE
	if(affected.open < (affected.encased ? 3 : 2))
		return FALSE
	for(var/datum/medical_issue/condition/tendon_severed/C in affected.medical_issues)
		return TRUE
	return FALSE

/datum/surgery_step/fix_tendon/begin_step(mob/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	var/obj/item/organ/external/affected = target.get_organ(target_zone)
	user.visible_message(
		span_filter_notice("[user] starts re-attaching the severed tendon in [target]'s [affected.name] with \the [tool]."),
		span_filter_notice("You start re-attaching the severed tendon in [target]'s [affected.name] with \the [tool]."),
	)
	user.balloon_alert_visible(
		"starts re-attaching the severed tendon in [target]'s [affected.name]",
		"repairing the tendon in \the [affected.name]",
	)
	target.custom_pain("Sharp, stabbing pain runs the length of \the [affected.name]!", 80)
	..()

/datum/surgery_step/fix_tendon/end_step(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	var/obj/item/organ/external/affected = target.get_organ(target_zone)
	user.visible_message(
		span_notice("[user] has re-attached the severed tendon in [target]'s [affected.name] with \the [tool]."),
		span_notice("You have re-attached the severed tendon in [target]'s [affected.name] with \the [tool]."),
	)
	user.balloon_alert_visible(
		"re-attaches the severed tendon in [target]'s [affected.name]",
		"repaired the tendon in \the [affected.name]",
	)

/datum/surgery_step/fix_tendon/fail_step(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	var/obj/item/organ/external/affected = target.get_organ(target_zone)
	user.visible_message(
		span_danger("[user]'s hand slips, tearing further at the tendon in [target]'s [affected.name]!"),
		span_danger("Your hand slips, tearing further at the tendon in [target]'s [affected.name]!"),
	)
	user.balloon_alert_visible(
		"slips, tearing the tendon in [target]'s [affected.name]",
		"your hand slips, tearing the tendon in \the [affected.name]",
	)
	affected.take_damage(5, 0)
