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
GLOBAL_LIST_INIT(dq_custom_external_surgeries, list( \
	"bone reinforcement" = TREAT_BONE_SETTING, \
	"remove growths" = TREAT_RESECTION, \
	"redirect blood vessels" = TREAT_VESSEL_REPAIR, \
	"extract object" = TREAT_FOREIGN_BODY_REMOVAL, \
	"flesh graft" = TREAT_TISSUE_REPAIR, \
))

/// Surgical cures a GM may pick for a custom affliction on an internal organ.
GLOBAL_LIST_INIT(dq_custom_internal_surgeries, list( \
	"remove growths" = TREAT_RESECTION, \
	"redirect blood vessels" = TREAT_VESSEL_REPAIR, \
	"close holes" = TREAT_SURGICAL_REPAIR, \
	"ultrasound" = TREAT_LITHOTRIPSY, \
	"reoxygenate tissue" = TREAT_OXYGENATION, \
))

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
				H.status_adjust(STAT_WEAKENED, 5)
		if("permanent weakness")
			H.status_set(STAT_WEAKENED, max(H.status_units(STAT_WEAKENED), 10))
		if("temporary sleeping")
			if(prob(5))
				H.status_adjust(STAT_SLEEPING, 5)
		if("permanent sleeping")
			H.status_set(STAT_SLEEPING, max(H.status_units(STAT_SLEEPING) + 10, 10))
		if("jittery")
			if(H.status_units(STAT_JITTERY) < 100)
				H.status_adjust(STAT_JITTERY, 100)
		if("paralysed")
			H.status_set(STAT_PARALYZED, max(H.status_units(STAT_PARALYZED), 10))
		if("cough")
			if(prob(3))
				H.emote("cough")
		if("confusion")
			H.status_set(STAT_CONFUSED, max(H.status_units(STAT_CONFUSED), 10))

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
	return medical_custom_stage(user, list())

/mob/living/carbon/human/proc/medical_custom_stage(mob/user, list/medical_answers, obj/item/organ/selected_organ)
	var/static/list/possible_symptoms = list("vomit", "temporary weakness", "permanent weakness", "temporary sleeping", "permanent sleeping", "jittery", "paralysed", "cough", "confusion", "None")

	if(!("a1" in medical_answers))
		open_request(src, /datum/prompt/text/custom_medical_review, PROC_REF(medical_custom_answered), answerer = user, medical_operator = user, medical_answers = medical_answers, medical_key = "a1", medical_organ = selected_organ, question = "What would you like to call this medical issue?", title = "Name")
		return
	var/issue_name = medical_answers["a1"]
	if(isnull(issue_name))
		return
	if(!issue_name)
		return
	issue_name = sanitize(issue_name)
	var/list/organ_options = list()
	for(var/obj/item/organ/E in organs)
		organ_options |= E
	for(var/obj/item/organ/I in internal_organ_list())
		organ_options |= I
	if(!("a2" in medical_answers))
		open_request(src, /datum/prompt/choice/custom_medical_review, PROC_REF(medical_custom_answered), answerer = user, medical_operator = user, medical_answers = medical_answers, medical_key = "a2", medical_organ = selected_organ, question = "Which organ should this issue be attached to?", title = "Affect organ", choices = organ_options)
		return
	var/obj/item/organ/issue_organ = selected_organ
	if(isnull(issue_organ))
		return
	if(!issue_organ)
		return

	if(!("a3" in medical_answers))
		open_request(src, /datum/prompt/choice/custom_medical_review, PROC_REF(medical_custom_answered), answerer = user, medical_operator = user, medical_answers = medical_answers, medical_key = "a3", medical_organ = selected_organ, question = "Should this apply damage?", title = "Damage", choices = list("Yes", "No", "Cancel"), buttons = TRUE)
		return
	var/damage = medical_answers["a3"]
	if(isnull(damage))
		return
	if(!damage || damage == "Cancel")
		return
	var/damage_organ
	var/damage_value
	var/damage_max
	var/damage_kind
	if(damage == "Yes")
		if(!("a4" in medical_answers))
			open_request(src, /datum/prompt/choice/custom_medical_review, PROC_REF(medical_custom_answered), answerer = user, medical_operator = user, medical_answers = medical_answers, medical_key = "a4", medical_organ = selected_organ, question = "Should this damage the organ or body?", title = "Damage", choices = list("Organ", "Body"), buttons = TRUE)
			return
		var/_answer_a4 = medical_answers["a4"]
		if(isnull(_answer_a4))
			return
		damage_organ = _answer_a4
		if(!damage_organ)
			return
		if(!("a5" in medical_answers))
			open_request(src, /datum/prompt/number/custom_medical_review, PROC_REF(medical_custom_answered), answerer = user, medical_operator = user, medical_answers = medical_answers, medical_key = "a5", medical_organ = selected_organ, question = "How much damage should this apply per processing. Low values are recommended, automatically divided by 10.", title = "Damage", default = 1)
			return
		var/damage_value_pre = medical_answers["a5"]
		if(isnull(damage_value_pre))
			return
		damage_value = max(0, damage_value_pre) / 10
		if(!("a6" in medical_answers))
			open_request(src, /datum/prompt/number/custom_medical_review, PROC_REF(medical_custom_answered), answerer = user, medical_operator = user, medical_answers = medical_answers, medical_key = "a6", medical_organ = selected_organ, question = "What is the maximum amount of damage this issue can apply? It will not damage above this value.", title = "Damage", default = 300)
			return
		var/_answer_a6 = medical_answers["a6"]
		if(isnull(_answer_a6))
			return
		damage_max = _answer_a6
		if(damage_organ == "Body")
			var/list/kinds = list()
			for(var/kind in 1 to INJURY_KIND_COUNT)
				kinds[injury_kind_name(kind)] = kind
			if(!("a7" in medical_answers))
				open_request(src, /datum/prompt/choice/custom_medical_review, PROC_REF(medical_custom_answered), answerer = user, medical_operator = user, medical_answers = medical_answers, medical_key = "a7", medical_organ = selected_organ, question = "What kind of harm should this do to the body?", title = "Damage", choices = kinds, default = injury_kind_name(INJURY_BLUNT))
				return
			var/kind_name = medical_answers["a7"]
			if(isnull(kind_name))
				return
			if(!kind_name)
				return
			damage_kind = kinds[kind_name]

	if(!("a8" in medical_answers))
		open_request(src, /datum/prompt/choice/custom_medical_review, PROC_REF(medical_custom_answered), answerer = user, medical_operator = user, medical_answers = medical_answers, medical_key = "a8", medical_organ = selected_organ, question = "Should this be cured by a reagent, surgery or organ removal only? Note that organ removal will always be an option if it's not a vital body part.", title = "Cure", choices = list("Reagent", "Surgery", "Removal", "Cancel"), buttons = TRUE)
		return
	var/cure_q = medical_answers["a8"]
	if(isnull(cure_q))
		return
	if(!cure_q || cure_q == "Cancel")
		return
	var/datum/reagent/cure_reagent_type
	var/cure_surgery_name
	if(cure_q == "Reagent")
		if(!("a9" in medical_answers))
			open_request(src, /datum/prompt/choice/custom_medical_review, PROC_REF(medical_custom_answered), answerer = user, medical_operator = user, medical_answers = medical_answers, medical_key = "a9", medical_organ = selected_organ, question = "Which reagent should be the cure?", title = "Cure", choices = subtypesof(/datum/reagent))
			return
		var/_answer_a9 = medical_answers["a9"]
		if(isnull(_answer_a9))
			return
		cure_reagent_type = _answer_a9
		if(!cure_reagent_type)
			return
	if(cure_q == "Surgery")
		if(!("a10" in medical_answers))
			open_request(src, /datum/prompt/choice/custom_medical_review, PROC_REF(medical_custom_answered), answerer = user, medical_operator = user, medical_answers = medical_answers, medical_key = "a10", medical_organ = selected_organ, question = "Which surgery step should cure it?", title = "Cure", choices = istype(issue_organ, /obj/item/organ/internal) ? GLOB.dq_custom_internal_surgeries : GLOB.dq_custom_external_surgeries)
			return
		var/_answer_a10 = medical_answers["a10"]
		if(isnull(_answer_a10))
			return
		cure_surgery_name = _answer_a10
		if(!cure_surgery_name)
			return

	if(!("a11" in medical_answers))
		open_request(src, /datum/prompt/text/custom_medical_review, PROC_REF(medical_custom_answered), answerer = user, medical_operator = user, medical_answers = medical_answers, medical_key = "a11", medical_organ = selected_organ, question = "What text should be displayed to the affected patient about their symptoms?", title = "Symptoms")
		return
	var/symptom_text = medical_answers["a11"]
	if(isnull(symptom_text))
		return
	if(!("a12" in medical_answers))
		open_request(src, /datum/prompt/choice/custom_medical_review, PROC_REF(medical_custom_answered), answerer = user, medical_operator = user, medical_answers = medical_answers, medical_key = "a12", medical_organ = selected_organ, question = "What observable symptom should they display?", title = "Symptoms", choices = possible_symptoms)
		return
	var/symptom_affect = medical_answers["a12"]
	if(isnull(symptom_affect))
		return
	if(!symptom_affect)
		return

	if(!("a13" in medical_answers))
		open_request(src, /datum/prompt/choice/custom_medical_review, PROC_REF(medical_custom_answered), answerer = user, medical_operator = user, medical_answers = medical_answers, medical_key = "a13", medical_organ = selected_organ, question = "Should this show on body scanners?", title = "Diagnosis", choices = list("Yes", "No", "Cancel"), buttons = TRUE)
		return
	var/scanner_show = medical_answers["a13"]
	if(isnull(scanner_show))
		return
	if(!scanner_show || scanner_show == "Cancel")
		return

	if(!("a14" in medical_answers))
		open_request(src, /datum/prompt/number/custom_medical_review, PROC_REF(medical_custom_answered), answerer = user, medical_operator = user, medical_answers = medical_answers, medical_key = "a14", medical_organ = selected_organ, question = "What level of health analyser is needed to see this? 0 for standard, 1 for improved, 2 for advanced, 3 for phasic and 4 for impossible.", title = "Diagnosis", default = 0)
		return
	var/scanner_strength = medical_answers["a14"]
	if(isnull(scanner_strength))
		return
	if(!("a15" in medical_answers))
		open_request(src, /datum/prompt/number/custom_medical_review, PROC_REF(medical_custom_answered), answerer = user, medical_operator = user, medical_answers = medical_answers, medical_key = "a15", medical_organ = selected_organ, question = "What level of health analyser is required to display the cure? 0 for standard, 1 for improved, 2 for advanced, 3 for phasic and 4 for impossible.", title = "Diagnosis", default = 0)
		return
	var/advscan_cure = medical_answers["a15"]
	if(isnull(advscan_cure))
		return

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
		var/list/surgeries = istype(issue_organ, /obj/item/organ/internal) ? GLOB.dq_custom_internal_surgeries : GLOB.dq_custom_external_surgeries
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
	return medical_clear_stage(user, list())

/mob/living/carbon/human/proc/medical_clear_stage(mob/user, list/medical_answers, datum/affliction/custom/selected_issue)
	var/list/all_issues = dq_custom_afflictions_of(src)
	if(!length(all_issues))
		to_chat(user, "No custom medical issues found in [src]!")
		return
	if(!("a16" in medical_answers))
		open_request(src, /datum/prompt/choice/custom_medical_review, PROC_REF(medical_clear_answered), answerer = user, medical_operator = user, medical_answers = medical_answers, medical_key = "a16", medical_issue = selected_issue, question = "Would you like to clear all custom medical issues or a specific one?", title = "Damage", choices = list("All", "One", "Cancel"), buttons = TRUE)
		return
	var/broad = medical_answers["a16"]
	if(isnull(broad))
		return
	if(!broad || broad == "Cancel")
		return

	if(broad == "All")
		for(var/datum/affliction/custom/A as anything in dq_custom_afflictions_of(src))
			to_chat(user, "[A.name] removed from [A.location] in [src].")
			A.cure()
		return

	if(!("a17" in medical_answers))
		open_request(src, /datum/prompt/choice/custom_medical_review, PROC_REF(medical_clear_answered), answerer = user, medical_operator = user, medical_answers = medical_answers, medical_key = "a17", medical_issue = selected_issue, question = "Which issue would you like to remove?", title = "Symptoms", choices = all_issues)
		return
	var/datum/affliction/custom/one_issue = selected_issue
	if(isnull(one_issue))
		return
	if(!one_issue || QDELETED(one_issue) || one_issue.owner != src)
		return
	to_chat(user, "[one_issue.name] removed from [one_issue.location] in [src].")
	one_issue.cure()

/mob/living/carbon/human/proc/medical_custom_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = medical_custom_apply(A)
	SStgui.update_uis(src)

/mob/living/carbon/human/proc/medical_custom_apply(datum/act/request/A)
	if(istype(A.answer, /datum/prompt/choice/custom_medical_review))
		var/datum/prompt/choice/custom_medical_review/ask = A.answer
		if(ask.medical_key == "a2")
			var/obj/item/organ/chosen = ask.value
			rel_set(ask, nameof(ask.medical_organ), chosen)
			ask.medical_answers[ask.medical_key] = TRUE
		else
			ask.medical_answers[ask.medical_key] = ask.value
		return medical_custom_stage(ask.medical_operator, ask.medical_answers, ask.medical_organ)
	if(istype(A.answer, /datum/prompt/text/custom_medical_review))
		var/datum/prompt/text/custom_medical_review/ask = A.answer
		ask.medical_answers[ask.medical_key] = ask.value
		return medical_custom_stage(ask.medical_operator, ask.medical_answers, ask.medical_organ)
	if(istype(A.answer, /datum/prompt/number/custom_medical_review))
		var/datum/prompt/number/custom_medical_review/ask = A.answer
		ask.medical_answers[ask.medical_key] = ask.value
		return medical_custom_stage(ask.medical_operator, ask.medical_answers, ask.medical_organ)

/mob/living/carbon/human/proc/medical_clear_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = medical_clear_apply(A)
	SStgui.update_uis(src)

/mob/living/carbon/human/proc/medical_clear_apply(datum/act/request/A)
	if(istype(A.answer, /datum/prompt/choice/custom_medical_review))
		var/datum/prompt/choice/custom_medical_review/ask = A.answer
		if(ask.medical_key == "a17")
			var/datum/affliction/custom/chosen = ask.value
			rel_set(ask, nameof(ask.medical_issue), chosen)
			ask.medical_answers[ask.medical_key] = TRUE
		else
			ask.medical_answers[ask.medical_key] = ask.value
		return medical_clear_stage(ask.medical_operator, ask.medical_answers, ask.medical_issue)

/datum/prompt/text/custom_medical_review
	timeout = 0
	var/mob/medical_operator
	var/medical_operator_expected = FALSE
	var/obj/item/organ/medical_organ
	var/datum/affliction/custom/medical_issue
	var/list/medical_answers
	var/medical_key

CAPABILITIES(/datum/prompt/text/custom_medical_review)
	ref_one(nameof(medical_operator), /mob)
	ref_one(nameof(medical_organ), /obj/item/organ)
	ref_one(nameof(medical_issue), /datum/affliction/custom)

/datum/prompt/text/custom_medical_review/prepare(datum/act/A)
	. = ..()
	var/mob/captured_medical_operator = medical_operator
	medical_operator_expected = !isnull(captured_medical_operator)
	rel_clear(src, nameof(medical_operator))
	if(captured_medical_operator && !QDELETED(captured_medical_operator))
		rel_set(src, nameof(medical_operator), captured_medical_operator)
	var/obj/item/organ/captured_medical_organ = medical_organ
	rel_clear(src, nameof(medical_organ))
	if(captured_medical_organ && !QDELETED(captured_medical_organ))
		rel_set(src, nameof(medical_organ), captured_medical_organ)
	var/datum/affliction/custom/captured_medical_issue = medical_issue
	rel_clear(src, nameof(medical_issue))
	if(captured_medical_issue && !QDELETED(captured_medical_issue))
		rel_set(src, nameof(medical_issue), captured_medical_issue)

/datum/prompt/text/custom_medical_review/recheck_extra()
	if(medical_operator_expected && QDELETED(medical_operator))
		return "gone"

/datum/prompt/number/custom_medical_review
	timeout = 0
	min_value = null
	max_value = null
	step = null
	var/mob/medical_operator
	var/medical_operator_expected = FALSE
	var/obj/item/organ/medical_organ
	var/datum/affliction/custom/medical_issue
	var/list/medical_answers
	var/medical_key

CAPABILITIES(/datum/prompt/number/custom_medical_review)
	ref_one(nameof(medical_operator), /mob)
	ref_one(nameof(medical_organ), /obj/item/organ)
	ref_one(nameof(medical_issue), /datum/affliction/custom)

/datum/prompt/number/custom_medical_review/prepare(datum/act/A)
	. = ..()
	var/mob/captured_medical_operator = medical_operator
	medical_operator_expected = !isnull(captured_medical_operator)
	rel_clear(src, nameof(medical_operator))
	if(captured_medical_operator && !QDELETED(captured_medical_operator))
		rel_set(src, nameof(medical_operator), captured_medical_operator)
	var/obj/item/organ/captured_medical_organ = medical_organ
	rel_clear(src, nameof(medical_organ))
	if(captured_medical_organ && !QDELETED(captured_medical_organ))
		rel_set(src, nameof(medical_organ), captured_medical_organ)
	var/datum/affliction/custom/captured_medical_issue = medical_issue
	rel_clear(src, nameof(medical_issue))
	if(captured_medical_issue && !QDELETED(captured_medical_issue))
		rel_set(src, nameof(medical_issue), captured_medical_issue)

/datum/prompt/number/custom_medical_review/recheck_extra()
	if(medical_operator_expected && QDELETED(medical_operator))
		return "gone"

/datum/prompt/choice/custom_medical_review
	timeout = 0
	var/mob/medical_operator
	var/medical_operator_expected = FALSE
	var/obj/item/organ/medical_organ
	var/datum/affliction/custom/medical_issue
	var/list/medical_answers
	var/medical_key

CAPABILITIES(/datum/prompt/choice/custom_medical_review)
	ref_one(nameof(medical_operator), /mob)
	ref_one(nameof(medical_organ), /obj/item/organ)
	ref_one(nameof(medical_issue), /datum/affliction/custom)

/datum/prompt/choice/custom_medical_review/prepare(datum/act/A)
	. = ..()
	var/mob/captured_medical_operator = medical_operator
	medical_operator_expected = !isnull(captured_medical_operator)
	rel_clear(src, nameof(medical_operator))
	if(captured_medical_operator && !QDELETED(captured_medical_operator))
		rel_set(src, nameof(medical_operator), captured_medical_operator)
	var/obj/item/organ/captured_medical_organ = medical_organ
	rel_clear(src, nameof(medical_organ))
	if(captured_medical_organ && !QDELETED(captured_medical_organ))
		rel_set(src, nameof(medical_organ), captured_medical_organ)
	var/datum/affliction/custom/captured_medical_issue = medical_issue
	rel_clear(src, nameof(medical_issue))
	if(captured_medical_issue && !QDELETED(captured_medical_issue))
		rel_set(src, nameof(medical_issue), captured_medical_issue)

/datum/prompt/choice/custom_medical_review/recheck_extra()
	if(medical_operator_expected && QDELETED(medical_operator))
		return "gone"
	if(!isnull(value) && medical_key == "a2")
		var/obj/item/organ/chosen_organ = value
		if(!istype(chosen_organ) || QDELETED(chosen_organ))
			return "gone"
	if(!isnull(value) && medical_key == "a17")
		var/datum/affliction/custom/chosen_issue = value
		if(!istype(chosen_issue) || QDELETED(chosen_issue))
			return "gone"
