// GM custom afflictions.
//
// Simple, one-off afflictions a GM builds on the fly for events. They are
// ordinary /datum/affliction instances living in the patient's body, located
// on the organ the GM picked, so every scanner, the detach/reattach system and
// the body's bookkeeping see them like any other affliction. Everything that
// would normally be authored on a subtype (name, harm, cure, symptoms,
// scanner visibility) is configured at runtime on the instance.
//
//   severity      the issue's remaining "health": starts at 100, the cure
//                 reagent wears it down, it resolves at 0. It does not
//                 progress on its own.
//   harm          optional: every tick, injure() the body with a chosen
//                 INJURY_* kind, or damage the host organ directly, up to a cap.
//   cure          a reagent (cured_by), a named surgery step (cure_surgery),
//                 or removal of the organ (the affliction leaves with it).

/// Surgery steps a GM may name as the cure for a custom affliction.
#define DQ_CUSTOM_SURGERY_BONE        "bone reinforcement"
#define DQ_CUSTOM_SURGERY_GROWTHS     "remove growths"
#define DQ_CUSTOM_SURGERY_VESSELS     "redirect blood vessels"
#define DQ_CUSTOM_SURGERY_EXTRACT     "extract object"
#define DQ_CUSTOM_SURGERY_GRAFT       "flesh graft"
#define DQ_CUSTOM_SURGERY_HOLES       "close holes"
#define DQ_CUSTOM_SURGERY_ULTRASOUND  "ultrasound"
#define DQ_CUSTOM_SURGERY_REOXYGENATE "reoxygenate tissue"

/// Per-tick cure strength of the cure reagent at a standard dose (the old
/// system removed 10 "unhealth" per tick while the reagent was present).
#define DQ_CUSTOM_CURE_RATE 10

/datum/affliction/custom
	name = "custom affliction"
	category = "Custom"
	clinical_description = "An unusual condition without an established clinical picture."
	biology = BIOLOGY_ALL
	// Severity is the issue's remaining health; it never climbs by itself.
	progression_rate = 0
	min_symptoms = 0
	max_symptoms = 0
	catalogued = FALSE

	/// Health-analyser level needed to see this (4 = never).
	var/advscan = SCANNABLE_BENEFICIAL
	/// Health-analyser level needed to reveal the cure.
	var/advscan_cure = SCANNABLE_BENEFICIAL
	/// Shown on the body scanner's findings.
	var/showscanner = FALSE

	/// INJURY_* dealt to the body each tick, or null for none.
	var/damage_kind
	/// Damage the host organ directly instead of the body.
	var/damage_organ = FALSE
	/// Amount per tick.
	var/damage_strength = 0
	/// Never push the harmed pool/organ past this.
	var/damage_max = 300

	/// Display name of the cure reagent (the ID lives in cured_by).
	var/cure_reagent_name
	/// DQ_CUSTOM_SURGERY_* that cures this, or null.
	var/cure_surgery

	/// Message relayed to the patient now and then.
	var/symptom_text
	/// Observable effect key (see handle_custom_symptoms()).
	var/symptom_affect

/datum/affliction/custom/tick()
	if(!owner || QDELETED(location) || location.owner != owner)
		return
	..()

/// GM afflictions don't progress or snowball on their own: they drain their
/// organ, respond to their cure (this tick's treatment, flat) and relay their
/// symptom.
/datum/affliction/custom/progress()
	if(damage_strength)
		apply_custom_damage()
	var/delta = pending_treatment
	pending_treatment = 0
	if(delta)
		adjust_severity(delta)
		if(severity <= 0)
			cure()
			return
	if(symptom_text && prob(1))
		to_chat(owner, span_danger("[symptom_text]"))
	if(symptom_affect)
		handle_custom_symptoms()

/// A detached custom affliction simply waits for the organ to come back.
/datum/affliction/custom/tick_offline()
	return

/datum/affliction/custom/proc/apply_custom_damage()
	if(damage_organ)
		if(istype(location, /obj/item/organ/external))
			var/obj/item/organ/external/E = location
			if(E.get_trauma() + E.get_burn() < damage_max)
				owner.injure(INJURY_BLUNT, damage_strength, E.organ_tag, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
		else if(location.damage < damage_max)
			owner.injure(INJURY_BLUNT, min(damage_strength, damage_max - location.damage), location, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
		return
	if(!damage_kind)
		return
	if(owner.injury_load(injury_category(damage_kind)) >= damage_max)
		return
	owner.injure(damage_kind, damage_strength, flags = INJURE_SILENT)

/datum/affliction/custom/proc/handle_custom_symptoms()
	var/mob/living/carbon/human/H = owner
	if(!istype(H))
		return
	switch(symptom_affect)
		if("vomit")
			if(prob(5))
				H.vomit(10)
		if("temporary weakness")
			if(prob(5))
				H.AdjustWeakened(5)
		if("permanent weakness")
			H.SetWeakened(max(H.weakened, 10))
		if("temporary sleeping")
			if(prob(5))
				H.AdjustSleeping(5)
		if("permanent sleeping")
			H.SetSleeping(max(H.sleeping + 10, 10))
		if("jittery")
			if(H.get_jittery() < 100)
				H.make_jittery(100)
		if("paralysed")
			H.SetParalysis(max(H.paralysis, 10))
		if("cough")
			if(prob(3))
				H.emote("cough")
		if("confusion")
			H.SetConfused(max(H.confused, 10))

/// Human-readable cure hint for scanners.
/datum/affliction/custom/proc/cure_hint()
	if(cure_reagent_name)
		return "Suggested treatment: Prescription of [cure_reagent_name]."
	if(cure_surgery)
		return "Required surgery: [cure_surgery]."
	return "[location ? capitalize(location.name) : "The affected organ"] may require surgical removal or transplantation."

/// Custom afflictions on `O` (in a body or detached), optionally only those
/// cured by `surgery`.
/proc/dq_custom_afflictions_on(obj/item/organ/O, surgery = null)
	. = list()
	if(!O)
		return
	for(var/datum/affliction/custom/A in O.afflictions_here())
		if(!surgery || A.cure_surgery == surgery)
			. += A

/// Every custom affliction on a mob.
/proc/dq_custom_afflictions_of(mob/living/M)
	. = list()
	for(var/datum/affliction/custom/A in M?.body?.afflictions)
		. += A


// --- GM setup -----------------------------------------------------------------------

/mob/living/carbon/human/proc/custom_medical_issue(mob/user)
	var/static/list/external_organ_surgeries = list(DQ_CUSTOM_SURGERY_BONE, DQ_CUSTOM_SURGERY_GROWTHS, DQ_CUSTOM_SURGERY_VESSELS, DQ_CUSTOM_SURGERY_EXTRACT, DQ_CUSTOM_SURGERY_GRAFT)
	var/static/list/internal_organ_surgeries = list(DQ_CUSTOM_SURGERY_GROWTHS, DQ_CUSTOM_SURGERY_VESSELS, DQ_CUSTOM_SURGERY_HOLES, DQ_CUSTOM_SURGERY_ULTRASOUND, DQ_CUSTOM_SURGERY_REOXYGENATE)
	var/static/list/possible_symptoms = list("vomit", "temporary weakness", "permanent weakness", "temporary sleeping", "permanent sleeping", "jittery", "paralysed", "cough", "confusion", "None")

	var/issue_name = tgui_input_text(user, "What would you like to call this medical issue?", "Name")
	if(!issue_name)
		return
	issue_name = sanitize(issue_name)
	var/list/organ_options = list()
	for(var/obj/item/organ/E in organs)
		organ_options |= E
	for(var/obj/item/organ/I in internal_organs)
		organ_options |= I
	var/obj/item/organ/issue_organ = tgui_input_list(user, "Which organ should this issue be attached to?", "Affect organ", organ_options)
	if(!issue_organ)
		return

	var/damage = tgui_alert(user, "Should this apply damage?", "Damage", list("Yes", "No", "Cancel"))
	if(!damage || damage == "Cancel")
		return
	var/damage_organ
	var/damage_value
	var/damage_max
	var/damage_kind
	if(damage == "Yes")
		damage_organ = tgui_alert(user, "Should this damage the organ or body?", "Damage", list("Organ", "Body"))
		if(!damage_organ)
			return
		var/damage_value_pre = tgui_input_number(user, "How much damage should this apply per processing. Low values are recommended, automatically divided by 10.", "Damage", 1)
		damage_value = max(0, damage_value_pre) / 10
		damage_max = tgui_input_number(user, "What is the maximum amount of damage this issue can apply? It will not damage above this value.", "Damage", 300)
		if(damage_organ == "Body")
			var/list/kinds = list()
			for(var/kind in 1 to INJURY_KIND_COUNT)
				kinds[injury_kind_name(kind)] = kind
			var/kind_name = tgui_input_list(user, "What kind of harm should this do to the body?", "Damage", kinds, injury_kind_name(INJURY_BLUNT))
			if(!kind_name)
				return
			damage_kind = kinds[kind_name]

	var/cure_q = tgui_alert(user, "Should this be cured by a reagent, surgery or organ removal only? Note that organ removal will always be an option if it's not a vital body part.", "Cure", list("Reagent", "Surgery", "Removal", "Cancel"))
	if(!cure_q || cure_q == "Cancel")
		return
	var/datum/reagent/cure_reagent_type
	var/cure_surgery
	if(cure_q == "Reagent")
		cure_reagent_type = tgui_input_list(user, "Which reagent should be the cure?", "Cure", subtypesof(/datum/reagent))
		if(!cure_reagent_type)
			return
	if(cure_q == "Surgery")
		cure_surgery = tgui_input_list(user, "Which surgery step should cure it?", "Cure", istype(issue_organ, /obj/item/organ/internal) ? internal_organ_surgeries : external_organ_surgeries)
		if(!cure_surgery)
			return

	var/symptom_text = tgui_input_text(user, "What text should be displayed to the affected patient about their symptoms?", "Symptoms")
	var/symptom_affect = tgui_input_list(user, "What observable symptom should they display?", "Symptoms", possible_symptoms)
	if(!symptom_affect)
		return

	var/scanner_show = tgui_alert(user, "Should this show on body scanners?", "Diagnosis", list("Yes", "No", "Cancel"))
	if(!scanner_show || scanner_show == "Cancel")
		return

	var/scanner_strength = tgui_input_number(user, "What level of health analyser is needed to see this? 0 for standard, 1 for improved, 2 for advanced, 3 for phasic and 4 for impossible.", "Diagnosis", 0)
	var/advscan_cure = tgui_input_number(user, "What level of health analyser is required to display the cure? 0 for standard, 1 for improved, 2 for advanced, 3 for phasic and 4 for impossible.", "Diagnosis", 0)

	// Every prompt above can sleep; the patient or organ may be gone now.
	if(QDELETED(src) || !body || QDELETED(issue_organ) || issue_organ.owner != src)
		to_chat(user, span_warning("The patient or the chosen organ is no longer available."))
		return

	var/datum/affliction/custom/A = new()
	A.name = issue_name
	A.advscan = scanner_strength
	A.advscan_cure = advscan_cure
	A.showscanner = (scanner_show == "Yes")
	if(damage == "Yes")
		A.damage_organ = (damage_organ == "Organ")
		A.damage_kind = damage_kind
		A.damage_strength = damage_value
		A.damage_max = damage_max
	if(cure_reagent_type)
		A.cure_reagent_name = initial(cure_reagent_type.name)
		A.cured_by = list()
		A.cured_by[initial(cure_reagent_type.id)] = DQ_CUSTOM_CURE_RATE
	A.cure_surgery = cure_surgery
	if(symptom_text)
		A.symptom_text = sanitize(symptom_text)
	if(symptom_affect != "None")
		A.symptom_affect = symptom_affect
	body.add_affliction(A, issue_organ)
	A.set_severity(AFFLICTION_SEVERITY_TERMINAL)

	to_chat(user, "[issue_name] applied to [issue_organ] inside of [src]!")
	log_admin("[key_name(user)] applied custom affliction '[issue_name]' to [key_name(src)] ([issue_organ]).")
	if(damage == "Yes")
		to_chat(user, "[issue_name] will damage the [damage_organ] with a strength of [damage_value], up to a maximum of [damage_max].")
	if(cure_reagent_type)
		to_chat(user, "[issue_name] can be cured with [A.cure_reagent_name].")
	else if(cure_surgery)
		to_chat(user, "[issue_name] can be cured via the [cure_surgery] surgery.")
	else
		to_chat(user, "[issue_name] can only be cured by amputation or removal of \the [issue_organ]!")

/mob/living/carbon/human/proc/clear_medical_issue(mob/user)
	var/list/all_issues = dq_custom_afflictions_of(src)
	if(!length(all_issues))
		to_chat(user, "No custom medical issues found in [src]!")
		return
	var/broad = tgui_alert(user, "Would you like to clear all custom medical issues or a specific one?", "Damage", list("All", "One", "Cancel"))
	if(!broad || broad == "Cancel")
		return

	if(broad == "All")
		for(var/datum/affliction/custom/A as anything in dq_custom_afflictions_of(src))
			to_chat(user, "[A.name] removed from [A.location] in [src].")
			A.cure()
		return

	var/datum/affliction/custom/one_issue = tgui_input_list(user, "Which issue would you like to remove?", "Symptoms", all_issues)
	if(!one_issue || QDELETED(one_issue) || one_issue.owner != src)
		return
	to_chat(user, "[one_issue.name] removed from [one_issue.location] in [src].")
	one_issue.cure()


///////////////////////////////////////////////////////////////
//////////////Custom affliction surgeries//////////////////////
///////////////////////////////////////////////////////////////
// Each step cures the custom afflictions that name it. External steps treat
// afflictions on the limb itself; internal steps treat afflictions on the
// organs inside the limb.

/datum/surgery_step/medical_issue
	can_infect = 1
	blood_level = 1
	min_duration = 50
	max_duration = 60
	/// DQ_CUSTOM_SURGERY_* this step performs.
	var/cure_key
	/// Treat afflictions on the internal organs of the limb, not the limb.
	var/internal_target = FALSE
	/// "reinforce the bone" — the verb phrase for messages.
	var/action_text = "operate"
	/// "reinforced the bone" — the completed phrase.
	var/done_text = "operated"

/// Custom afflictions this step can cure at `affected`.
/datum/surgery_step/medical_issue/proc/curable_afflictions(obj/item/organ/external/affected)
	. = list()
	if(!affected || !cure_key)
		return
	if(!internal_target)
		return dq_custom_afflictions_on(affected, cure_key)
	for(var/obj/item/organ/internal/I in affected.internal_organs)
		. += dq_custom_afflictions_on(I, cure_key)

/datum/surgery_step/medical_issue/can_use(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	if(!ishuman(target))
		return FALSE
	var/obj/item/organ/external/affected = target.get_organ(target_zone)
	if(!affected) //happens if we try to target an organ that was amputated.
		return FALSE
	if(coverage_check(user, target, affected, tool))
		return FALSE
	if(!length(curable_afflictions(affected)))
		return FALSE
	return (affected.robotic < ORGAN_ROBOT) && affected.open >= FLESH_RETRACTED

/datum/surgery_step/medical_issue/begin_step(mob/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	var/obj/item/organ/external/affected = target.get_organ(target_zone)
	user.visible_message(span_notice("[user] is beginning to [action_text] in [target]'s [affected.name] with \the [tool]."), \
		span_notice("You are beginning to [action_text] in [target]'s [affected.name] with \the [tool]."))
	user.balloon_alert_visible("begins to [action_text].", "beginning to [action_text].")
	target.custom_pain("The pain in your [affected.name] is going to make you pass out!", 50)
	..()

/datum/surgery_step/medical_issue/end_step(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	var/obj/item/organ/external/affected = target.get_organ(target_zone)
	var/list/curable = curable_afflictions(affected)
	if(!length(curable))
		return
	user.visible_message(span_notice("[user] [done_text] in [target]'s [affected.name] with \the [tool]."), \
		span_notice("You [done_text] in [target]'s [affected.name] with \the [tool]."))
	user.balloon_alert_visible("[done_text].", "[done_text].")
	for(var/datum/affliction/custom/A as anything in curable)
		A.cure()

/datum/surgery_step/medical_issue/fail_step(mob/living/user, mob/living/carbon/human/target, target_zone, obj/item/tool)
	var/obj/item/organ/external/affected = target.get_organ(target_zone)
	user.visible_message(span_danger("[user]'s hand slips, damaging the tissue in [target]'s [affected.name] with \the [tool]!"), \
		span_danger("Your hand slips, damaging the tissue in [target]'s [affected.name] with \the [tool]!"))
	user.balloon_alert_visible("slips, damaging the tissue.", "your hand slips, damaging the tissue")
	target.injure(INJURY_BLUNT, 5, target_zone, tool)

// --- External (the limb itself) ---

//Bone-gel
/datum/surgery_step/medical_issue/strengthen_bone
	surgery_name = "Reinforce Bone"
	allowed_tools = list(
		/obj/item/surgical/bonegel = 100
	)
	allowed_procs = list(IS_SCREWDRIVER = 75)
	cure_key = DQ_CUSTOM_SURGERY_BONE
	action_text = "reinforce the bone"
	done_text = "reinforced the bone"

//scalpel
/datum/surgery_step/medical_issue/remove_growth
	surgery_name = "Remove Growth"
	allowed_tools = list(
		/obj/item/surgical/scalpel = 100
	)
	cure_key = DQ_CUSTOM_SURGERY_GROWTHS
	action_text = "remove growths"
	done_text = "removed the growths"

//fixovein
/datum/surgery_step/medical_issue/redirect_vessels
	surgery_name = "Redirect Blood Vessels"
	allowed_tools = list(
		/obj/item/surgical/FixOVein = 100
	)
	cure_key = DQ_CUSTOM_SURGERY_VESSELS
	action_text = "redirect blood vessels"
	done_text = "redirected blood vessels"

//hemostat
/datum/surgery_step/medical_issue/extract_object
	surgery_name = "Extract Object"
	allowed_tools = list(
		/obj/item/surgical/hemostat = 100
	)
	cure_key = DQ_CUSTOM_SURGERY_EXTRACT
	action_text = "remove objects"
	done_text = "removed the objects"

//brute kit
/datum/surgery_step/medical_issue/flesh_graft
	surgery_name = "Graft Flesh"
	allowed_tools = list(
		/obj/item/stack/medical/advanced/bruise_pack = 100
	)
	cure_key = DQ_CUSTOM_SURGERY_GRAFT
	action_text = "graft flesh"
	done_text = "grafted the flesh"

// --- Internal (organs inside the limb) ---

//scalpel
/datum/surgery_step/medical_issue/remove_growth_internal
	surgery_name = "Remove Growth on Organ"
	allowed_tools = list(
		/obj/item/surgical/scalpel = 100
	)
	cure_key = DQ_CUSTOM_SURGERY_GROWTHS
	internal_target = TRUE
	action_text = "remove growths"
	done_text = "removed the growths"

//fixovein
/datum/surgery_step/medical_issue/redirect_vessels_internal
	surgery_name = "Redirect Blood Vessels"
	allowed_tools = list(
		/obj/item/surgical/FixOVein = 100
	)
	cure_key = DQ_CUSTOM_SURGERY_VESSELS
	internal_target = TRUE
	action_text = "redirect blood vessels"
	done_text = "redirected blood vessels"

//cautery
/datum/surgery_step/medical_issue/close_holes
	surgery_name = "Close Holes"
	allowed_tools = list(
		/obj/item/surgical/cautery = 100
	)
	cure_key = DQ_CUSTOM_SURGERY_HOLES
	internal_target = TRUE
	action_text = "close holes"
	done_text = "closed the holes"

//autopsy scanner
/datum/surgery_step/medical_issue/ultrasound
	surgery_name = "Ultrasound"
	allowed_tools = list(
		/obj/item/autopsy_scanner = 100
	)
	cure_key = DQ_CUSTOM_SURGERY_ULTRASOUND
	internal_target = TRUE
	action_text = "break up material using ultrasound"
	done_text = "broke up material with ultrasound"

//bioregen
/datum/surgery_step/medical_issue/reoxygenate_tissue
	surgery_name = "Reoxygenate Tissue"
	allowed_tools = list(
		/obj/item/surgical/bioregen = 100
	)
	cure_key = DQ_CUSTOM_SURGERY_REOXYGENATE
	internal_target = TRUE
	action_text = "reoxygenate tissue"
	done_text = "reoxygenated tissue"
