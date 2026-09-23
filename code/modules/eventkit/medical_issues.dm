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
//   cure          a reagent (cured_by), a surgical treatment mechanism
//                 (cure_surgery, a TREAT_* tag the matching surgical step
//                 delivers), or removal of the organ (the affliction leaves
//                 with it).

/// Surgical cures a GM may pick for a custom affliction on a limb: name -> TREAT_*.
/proc/dq_custom_external_surgeries()
	var/static/list/L = list(
		"bone reinforcement" = TREAT_BONE_SETTING,
		"remove growths" = TREAT_RESECTION,
		"redirect blood vessels" = TREAT_VESSEL_REPAIR,
		"extract object" = TREAT_FOREIGN_BODY_REMOVAL,
		"flesh graft" = TREAT_TISSUE_REPAIR,
	)
	return L

/// Surgical cures a GM may pick for a custom affliction on an internal organ.
/proc/dq_custom_internal_surgeries()
	var/static/list/L = list(
		"remove growths" = TREAT_RESECTION,
		"redirect blood vessels" = TREAT_VESSEL_REPAIR,
		"close holes" = TREAT_SURGICAL_REPAIR,
		"ultrasound" = TREAT_LITHOTRIPSY,
		"reoxygenate tissue" = TREAT_OXYGENATION,
	)
	return L

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
	/// TREAT_* mechanism of the surgical step that cures this, or null.
	var/cure_surgery
	/// What the GM called that surgery.
	var/cure_surgery_name

	/// Message relayed to the patient now and then.
	var/symptom_text
	/// Observable effect key (see handle_custom_symptoms()).
	var/symptom_affect

/// The surgical cure works only as a procedure: one completed step cures the
/// issue, and drugs sharing the mechanism do nothing.
/datum/affliction/custom/receive_tagged_treatment(tag, amount, continuous = FALSE)
	if(cure_surgery && tag == cure_surgery)
		if(continuous || amount <= 0)
			return 0
		cure()
		return amount
	return ..()

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
		return "Required surgery: [cure_surgery_name]."
	return "[location ? capitalize(location.name) : "The affected organ"] may require surgical removal or transplantation."

/// Custom afflictions on `O` (in a body or detached).
/proc/dq_custom_afflictions_on(obj/item/organ/O)
	. = list()
	if(!O)
		return
	for(var/datum/affliction/custom/A in O.afflictions_here())
		. += A

/// Every custom affliction on a mob.
/proc/dq_custom_afflictions_of(mob/living/M)
	. = list()
	for(var/datum/affliction/custom/A in M?.body?.afflictions)
		. += A


// --- GM setup -----------------------------------------------------------------------

/mob/living/carbon/human/proc/custom_medical_issue(mob/user)
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
	var/cure_surgery_name
	if(cure_q == "Reagent")
		cure_reagent_type = tgui_input_list(user, "Which reagent should be the cure?", "Cure", subtypesof(/datum/reagent))
		if(!cure_reagent_type)
			return
	if(cure_q == "Surgery")
		cure_surgery_name = tgui_input_list(user, "Which surgery step should cure it?", "Cure", istype(issue_organ, /obj/item/organ/internal) ? dq_custom_internal_surgeries() : dq_custom_external_surgeries())
		if(!cure_surgery_name)
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
	if(cure_surgery_name)
		var/list/surgeries = istype(issue_organ, /obj/item/organ/internal) ? dq_custom_internal_surgeries() : dq_custom_external_surgeries()
		A.cure_surgery = surgeries[cure_surgery_name]
		A.cure_surgery_name = cure_surgery_name
		A.treated_by = list()
		A.treated_by[A.cure_surgery] = 1
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
	else if(cure_surgery_name)
		to_chat(user, "[issue_name] can be cured via the [cure_surgery_name] surgery.")
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
