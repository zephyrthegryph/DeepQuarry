// Surgery framework.
//
// There are no fixed procedures. The only fixed bookends are access (incise, retract, saw, pry; unscrew and open a panel) and
// close (set the bone layer, cauterize; secure the panel). Between them the opened limb shows its findings (findings.dm): every
// affliction, foreign body, crooked bone or growth in it that a step answers to. The surgeon picks the step that fits each
// finding, in any order:
//   operate (repair, resect, set, re-break, remove, extract, insert, implant)
//
// Access state is the limb's /datum/affliction/surgical_incision
// (incision.dm): it bleeds and gathers germs until it is closed, and its
// depth is the only thing that says how far a limb is open.
//
// Every step that heals is a TREATMENT: it names TREAT_* mechanisms and an
// amount (`treatments`), and perform() hands them to mend() on the limb, the
// limb's region, or one chosen organ. Nothing here writes organ damage or
// deletes afflictions. A condition that needs surgery declares the surgical
// tag in its treated_by, and the matching step starts to offer itself for it
// (is_needed()). Closing an incision is the same thing: the incision is
// treated by TREAT_SURGICAL_CLOSURE / TREAT_PANEL_CLOSURE / TREAT_BONE_SETTING.
//
// Outcome: success_chance() = tool quality x surface x surgeon. A failed step calls complicate(), which injures the patient
// with a specific complication (a cut vessel bleeds, a nicked organ gets a lesion). The patient's state is not a die roll:
// a patient who feels the step flinches (flinch(), felt_pain()), the open site bleeds as the patient's blood clots
// (STAT_BLEEDING), and it gathers germs by how sterile the surface, the surgeon's hands and the patient's skin were when it
// was opened.
//
// Synthetic and nanoform limbs use the same steps with repair tags (plating,
// wiring, system restore, panel closure); a step's `part_biology` defaults to
// the biologies its treatment tags work on.

GLOBAL_LIST_EMPTY(surgical_steps)
GLOBAL_PROTECT(surgical_steps)

/// Every step prototype, highest priority first. Built on first use.
/proc/surgical_steps()
	if(length(GLOB.surgical_steps))
		return GLOB.surgical_steps
	var/list/steps = list()
	for(var/step_type in subtypesof(/datum/surgical_step))
		if(is_abstract(step_type))
			continue
		steps += new step_type()
	sortTim(steps, GLOBAL_PROC_REF(cmp_surgical_step_priority))
	GLOB.surgical_steps = steps
	return steps

/proc/cmp_surgical_step_priority(datum/surgical_step/a, datum/surgical_step/b)
	return b.priority - a.priority

/// The registered prototype of `step_type`.
/proc/surgical_step(step_type)
	for(var/datum/surgical_step/S as anything in surgical_steps())
		if(S.type == step_type)
			return S
	return null

LIFECYCLE_KEEP_UNLESS_FORCED(/datum/surgical_step)
/datum/surgical_step
	// Base types set abstract_type to their own path; they are not registered.
	abstract_type = /datum/surgical_step
	/// Shown in the step picker and the operating computer.
	var/name = "surgical step"
	var/phase = SURGERY_PHASE_OPERATE
	/// Higher priority steps are offered first.
	var/priority = 0
	/// A finding step: the opened limb lists what this step answers to (findings(), findings.dm) and the medical book has an
	/// entry for it.
	var/finds = FALSE
	/// One sentence for the medical book: what the step is for.
	var/about = ""
	/// The medical book's group for the step.
	var/book_category = "Special"
	/// Afflictions the step answers to beyond those that list one of its treatment tags (a step with no tag of its own).
	var/list/extra_treats

	/// typepath -> quality (0-100).
	var/list/allowed_tools
	/// TOOL_* quality -> quality (0-100), for improvised tools.
	var/list/allowed_tool_qualities
	/// Typepaths that match allowed_tools but have their own, better step.
	var/list/excluded_tools

	/// Biologies of the limb this step works on. Null: the biologies every
	/// treatment tag in `treatments` works on (set in New()).
	var/part_biology
	/// Zones this step applies to (null = any limb).
	var/list/zones
	/// Access depth window the limb must be in.
	var/min_depth = SURGERY_DEPTH_CLOSED
	var/max_depth = BONE_RETRACTED
	/// Needs the limb's full access depth (bone retracted on encased limbs,
	/// flesh retracted elsewhere).
	var/needs_full_access = FALSE
	/// Works on a missing limb (attachment steps).
	var/needs_missing_part = FALSE

	/// Treatment mechanisms delivered on success: TREAT_* -> amount.
	var/list/treatments
	/// Where the treatments land (SURGERY_SCOPE_*).
	var/scope = SURGERY_SCOPE_PART

	var/duration = 4 SECONDS
	/// How much the step hurts (patient pain; with no analgesia a conscious
	/// patient flinches in proportion).
	var/pain = 40
	/// Carries germs from the surgeon and the surface into the wound.
	var/infection_risk = TRUE
	/// Blood on the surgeon: 1 hands, 2 whole body.
	var/blood_level = 1

	/// Complication on failure: injury kind, amount and optional affliction
	/// (a lesion typepath when the step works on an organ).
	var/complication_kind = INJURY_CUT
	var/complication_amount = 10
	var/complication_affliction

	// Messages: "[user] starts [begin_text] [target]'s [part] with \the [tool]."
	var/begin_text = "operating on"
	var/end_text = "operates on"
	var/fail_text = "slips, cutting into"
	var/pain_text = "Something sharp digs into your %PART%!"

/datum/surgical_step/New()
	..()
	if(isnull(part_biology))
		if(length(treatments))
			part_biology = NONE
			for(var/tag in treatments)
				part_biology |= treatment_tag_biology(tag)
		else
			part_biology = BIOLOGY_ORGANIC

// --- Tools -------------------------------------------------------------------------

/// How well `tool` suits this step (0 = not at all).
/datum/surgical_step/proc/tool_quality(obj/item/tool)
	if(!tool)
		return 0
	for(var/tool_type in excluded_tools)
		if(istype(tool, tool_type))
			return 0
	for(var/tool_type in allowed_tools)
		if(istype(tool, tool_type))
			return clamp(allowed_tools[tool_type] + material_build_view(tool).tool_quality_bonus, 0, 100)
	for(var/quality in allowed_tool_qualities)
		if(tool.has_tool_quality(quality))
			return clamp(allowed_tool_qualities[quality] + material_build_view(tool).tool_quality_bonus, 0, 100)
	return 0

// --- Validity -------------------------------------------------------------------------

/// Can this step run? TRUE, FALSE, or SURGERY_REFUSED (it told the user why).
/datum/surgical_step/proc/can_use(mob/living/user, mob/living/carbon/human/target, zone, obj/item/tool)
	if(!ishuman(target) || !target.body)
		return FALSE
	if(zones && !(zone in zones))
		return FALSE
	var/obj/item/organ/external/part = target.get_organ(zone)
	if(needs_missing_part)
		return part ? FALSE : TRUE
	if(!part || part.is_stump() || (part.status & ORGAN_DESTROYED))
		return FALSE
	if(!(target.body.biology_of(part) & part_biology))
		return FALSE
	var/depth = part.surgical_depth()
	if(depth < min_depth || depth > max_depth)
		return FALSE
	if(needs_full_access && depth < part.surgical_full_access())
		return FALSE
	if(coverage_check(user, target, part))
		return FALSE
	return is_needed(user, target, part, tool)

/// Is there something for this step to do here? Treatment steps are needed
/// when an affliction in scope is treated by one of their mechanisms.
/datum/surgical_step/proc/is_needed(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	if(!length(treatments))
		return TRUE
	for(var/location in treatment_locations(target, part))
		if(location_needs_treatment(target, location))
			return TRUE
	return FALSE

/// Does anything at `location` respond to this step's treatments?
/datum/surgical_step/proc/location_needs_treatment(mob/living/carbon/human/target, location)
	var/location_biology = target.body.biology_of(location)
	for(var/datum/affliction/A as anything in target.body.afflictions_at(location))
		// The open site answers to its own steps (clamp, set, close), which
		// ask it directly.
		if(istype(A, /datum/affliction/surgical_incision))
			continue
		for(var/tag in treatments)
			if(A.treatment_rate(tag) && (treatment_tag_biology(tag) & location_biology))
				return TRUE
	return FALSE

/// The locations this step's treatments can reach on `part`.
/datum/surgical_step/proc/treatment_locations(mob/living/carbon/human/target, obj/item/organ/external/part)
	. = list()
	if(scope != SURGERY_SCOPE_ORGAN)
		. += part
	if(scope != SURGERY_SCOPE_PART)
		for(var/obj/item/organ/internal/I as anything in part.held_organs())
			if(I.owner == target)
				. += I

/// Covered by a spacesuit or helmet?
/datum/surgical_step/proc/coverage_check(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part)
	if(part.organ_tag == BP_HEAD)
		return istype(target.get_equipped_item(SLOT_ID_HEAD), /obj/item/clothing/head/helmet/space)
	return istype(target.get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/space)

// --- Target selection ---------------------------------------------------------------

/// What the step can work on in `part`, as name -> organ: null when it works on the part itself (one entry: no question).
/// Organ-scope steps list the organs that need them.
/datum/surgical_step/proc/target_choices(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	if(scope != SURGERY_SCOPE_ORGAN)
		return null
	. = list()
	for(var/obj/item/organ/internal/I as anything in treatment_locations(target, part))
		if(location_needs_treatment(target, I))
			.[I.name] = I

/// How urgent `location` is for this step: the worst severity of the afflictions there that its treatments answer to.
/datum/surgical_step/proc/target_urgency(mob/living/carbon/human/target, atom/location)
	. = 0
	for(var/datum/affliction/A as anything in target.body.afflictions_at(location))
		if(istype(A, /datum/affliction/surgical_incision))
			continue
		for(var/tag in treatments)
			if(A.treatment_rate(tag))
				. = max(., A.severity)
				break

/// Is this location one of the step's findings (what the limb lists as the problem, rather than just a place the step can work)?
/datum/surgical_step/proc/target_is_finding(mob/living/carbon/human/target, obj/item/organ/external/part, atom/location)
	for(var/list/row as anything in findings(target, part, TRUE))
		if(row["where"] == location)
			return TRUE
	return FALSE

/// `target_choices()` in the order the step works through them: finding organs first, then by severity, then by name. The
/// first is what a tool use lands on; nobody is asked.
/datum/surgical_step/proc/ordered_target_choices(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	var/list/choices = target_choices(user, target, part, tool)
	if(length(choices) < 2)
		return choices
	var/list/names = list()
	var/list/rank = list()
	for(var/name in choices)
		var/atom/location = choices[name]
		names += name
		rank[name] = (target_is_finding(target, part, location) ? 1000 : 0) + target_urgency(target, location)
	for(var/i in 2 to length(names))
		var/j = i
		while(j > 1 && (rank[names[j]] > rank[names[j - 1]] || (rank[names[j]] == rank[names[j - 1]] && names[j] < names[j - 1])))
			names.Swap(j, j - 1)
			j--
	. = list()
	for(var/name in names)
		.[name] = choices[name]

/// Is the chosen target still valid after the step's delay?
/datum/surgical_step/proc/target_still_valid(mob/living/carbon/human/target, obj/item/organ/external/part, atom/work_target)
	if(QDELETED(part) || part.owner != target)
		return FALSE
	if(istype(work_target, /obj/item/organ) && work_target != part)
		var/obj/item/organ/O = work_target
		return !QDELETED(O) && O.owner == target
	return TRUE

// --- Outcome --------------------------------------------------------------------------

/// Skill multiplier for `user` on this step: training, steadiness, self-surgery.
/datum/surgical_step/proc/surgeon_skill(mob/living/user, mob/living/carbon/human/target)
	. = 1
	if(department_for_mob(user) != DEPARTMENT_MEDICAL)
		. *= SURGERY_UNTRAINED_MULT
	. *= clamp(user.motor_control, 0, 1)
	if(user == target)
		. *= SURGERY_SELF_MULT

/// Surface multiplier from the surface's cleanliness (operating table 100,
/// roller bed / table 50-75, floor up to 25).
/proc/surgery_surface_mult(cleanliness)
	return SURGERY_FLOOR_SURFACE_MULT + (1 - SURGERY_FLOOR_SURFACE_MULT) * clamp(cleanliness, 0, 100) / 100

/// How much of the step the patient feels (0 = nothing). A patient who is awake feels the step's pain less what pain relief
/// (STAT_ANALGESIA) and sedation (STAT_SEDATION) take off it; unconscious or pain-immune patients feel nothing, and neither
/// does a prosthetic part: a panel doesn't hurt to open. Anaesthesia, sleep and painkillers all just have to bring this to 0.
/datum/surgical_step/proc/felt_pain(mob/living/carbon/human/target, obj/item/organ/external/part)
	if(!pain || target.stat != CONSCIOUS)
		return 0
	if(!part || !(target.body.biology_of(part) & BIOLOGY_ORGANIC) || !target.dq_feels_pain())
		return 0
	if(target.pain_immunity)
		return 0
	return max(0, pain - target.analgesia - target.sedation)

/// Chance (0-100) this step succeeds: the tool, the surface and the surgeon. The patient is not part of it; a patient who feels
/// the step makes it flinch (flinch()).
/datum/surgical_step/proc/success_chance(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, cleanliness)
	. = tool_quality(tool)
	. *= surgery_surface_mult(cleanliness)
	. *= surgeon_skill(user, target)
	. = clamp(round(., 1), 0, 100)

/// A patient who feels the step moves under the blade: the step goes wrong the way a slip would, with the same complication.
/datum/surgical_step/proc/flinch(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target, felt)
	var/what = work_target ? "[work_target]" : "body"
	act_message(user, target, MSG_SELF(span_danger("%T% flinches as you work on [what] with %I%!")), \
		MSG_OTHERS(span_danger("%T% flinches as %U% works on [what] with %I%!")), \
		item = tool)
	user.balloon_alert_visible("[target] flinches", "[target] flinches")
	if(part?.organ_can_feel_pain())
		target.emote("scream")
	log_game("SURGERY: [key_name(target)] flinched under [key_name(user)] during [name] ([felt] pain felt, no relief)")
	complicate(user, target, part, tool, work_target)

/// The afflictions this step answers to, as typepaths: those that list one of its treatment tags, and the extras it names.
/datum/surgical_step/proc/treated_afflictions()
	. = list()
	for(var/affliction_type in extra_treats)
		. |= affliction_type
	for(var/affliction_type in GLOBAL_TABLE_GET(dq_catalogued_affliction_types))
		if(ispath(affliction_type, /datum/affliction/surgical_incision))
			continue
		var/datum/affliction/proto = dq_proto(affliction_type)
		for(var/tag in treatments)
			if(proto.treatment_rate(tag))
				. |= affliction_type
				break

/// What this step answers to in `part`, for the findings list: one row per finding (surgical_finding_row()). `full` is true
/// when the limb is open far enough to reach its organs. Base: every affliction in scope that responds to a treatment tag.
/datum/surgical_step/proc/findings(mob/living/carbon/human/target, obj/item/organ/external/part, full)
	. = list()
	if(!finds || !length(treatments))
		return
	for(var/location in treatment_locations(target, part))
		if(location != part && needs_full_access && !full)
			continue
		var/location_biology = target.body.biology_of(location)
		for(var/datum/affliction/A as anything in target.body.afflictions_at(location))
			if(istype(A, /datum/affliction/surgical_incision))
				continue
			for(var/tag in treatments)
				if(A.treatment_rate(tag) && (treatment_tag_biology(tag) & location_biology))
					. += list(surgical_finding_row(A.name, location, A, src))
					break

// --- Effects --------------------------------------------------------------------------

/// The question a drastic step asks before it starts (a "no" ends it), or null for none.
/datum/surgical_step/proc/confirm_text(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	return null

/// Starting messages, pain and germs.
/datum/surgical_step/proc/begin(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	var/what = work_target ? "[work_target]" : "body"
	act_message(user, target, MSG_SELF(span_filter_notice("You start [begin_text] %T%'s [what] with %I%.")), \
		MSG_OTHERS(span_filter_notice("%U% starts [begin_text] %T%'s [what] with %I%.")), \
		item = tool)
	user.balloon_alert_visible("starts [begin_text] [target]'s [what]", "[begin_text] \the [what]")
	if(pain && pain_text && part)
		target.custom_pain(replacetext(pain_text, "%PART%", part.name), pain)
	if(infection_risk && part)
		spread_germs_to_organ(part, user)
	if(ishuman(user) && prob(60))
		var/mob/living/carbon/human/H = user
		if(blood_level)
			H.bloody_hands(target, 0)
		if(blood_level > 1)
			H.bloody_body(target, 0)

/// The step's effect. Base: deliver `treatments` to the work target (or every
/// location in scope for region steps) through mend().
/datum/surgical_step/proc/perform(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	var/list/locations = (scope == SURGERY_SCOPE_REGION) ? treatment_locations(target, part) : list(work_target)
	for(var/location in locations)
		for(var/tag in treatments)
			var/treated = target.mend(tag, treatments[tag], location)
			log_game("SURGERY: [key_name(user)] [name] on [key_name(target)] ([location]): [tag] x[treatments[tag]] treated [treated]")

/// Completion messages.
/datum/surgical_step/proc/finish_message(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	var/what = work_target ? "[work_target]" : "body"
	act_message(user, target, MSG_SELF(span_notice("You finish [begin_text] %T%'s [what] with %I%.")), \
		MSG_OTHERS(span_notice("%U% [end_text] %T%'s [what] with %I%.")), \
		item = tool)
	user.balloon_alert_visible("[end_text] [target]'s [what]", "finished [begin_text] \the [what]")

/// A failed step: a specific complication, created as an injury.
/datum/surgical_step/proc/complicate(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	var/what = work_target ? "[work_target]" : "body"
	act_message(user, target, MSG_SELF(span_danger("Your hand [fail_text] %T%'s [what] with %I%!")), \
		MSG_OTHERS(span_danger("%U%'s hand [fail_text] %T%'s [what] with %I%!")), \
		item = tool)
	user.balloon_alert_visible("[fail_text] [target]'s [what]", "your hand [fail_text] \the [what]")
	if(!complication_amount)
		return
	var/injury_target = work_target || part
	if(!injury_target)
		return
	target.injure(complication_kind, complication_amount, injury_target, tool, affliction = complication_affliction, flags = INJURE_IGNORE_RESISTANCE)
	log_game("SURGERY: [key_name(user)] failed [name] on [key_name(target)] ([injury_target]): [injury_kind_name(complication_kind)] x[complication_amount] [complication_affliction || ""]")

// --- Running a step -------------------------------------------------------------------

/// Steps any tool could do next at `zone` (the operating computer).
/proc/next_surgical_steps(mob/living/user, mob/living/carbon/human/target, zone)
	. = list()
	for(var/datum/surgical_step/S as anything in surgical_steps())
		if(!length(S.allowed_tools))
			continue
		var/result = S.can_use(user, target, zone, null)
		if(result && result != SURGERY_REFUSED)
			. += S

/obj/item/proc/can_do_surgery(mob/living/carbon/M, mob/living/user)
	return TRUE

/// A tool used on a patient who can be operated on, before surgery and the attack: scanners and stethoscopes do their own thing
/// here. TRUE when it took the use.
/obj/item/proc/use_on_patient(mob/living/carbon/M, mob/living/user, stance = I_HELP)
	return FALSE

/// A surgical step with this tool finished on the patient's zone: whether it succeeded.
ACTION(material_surgery, mob/living/carbon/human/patient, zone, success, FIXED, notice = /datum/notice/material_surgery)

/mob/living/carbon/human/proc/surgical_step_ended(success, obj/item/tool, datum/surgical_step/step, mob/living/user, zone, cleanliness, obj/item/organ/external/part, atom/work_target, chance, felt = 0)
	if(felt > 0)
		success = FALSE // the patient felt it and flinched
	if(success)
		step.perform(user, src, part, tool, work_target)
		step.finish_message(user, src, part, tool, work_target)
		PUBLISH(tool, material_surgery, patient = src, zone = zone, success = TRUE)
		if(user != src && department_for_mob(user) == DEPARTMENT_MEDICAL)
			charge_mob_for_department_service(src, DEPARTMENT_MEDICAL, 5, "Surgical care: [step.name]", user.real_name)
	else
		if(felt > 0)
			step.flinch(user, src, part, tool, work_target, felt)
		else
			step.complicate(user, src, part, tool, work_target)
		PUBLISH(tool, material_surgery, patient = src, zone = zone, success = FALSE)
		user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	log_game("SURGERY: [key_name(user)] [success ? "completed" : (felt > 0 ? "flinched during" : "failed")] [step.name] on [key_name(src)] at [zone] (chance [chance]%, surface [cleanliness], pain felt [felt])")

	// A dirty surface seeds the site with germs.
	part = get_organ(zone)
	if(part && step.infection_risk && prob(100 - cleanliness))
		part.adjust_germ_level(rand(10, 20))


/// How sterile a site is when it is cut (0-100): the surface it is cut on, less what an unprepared surgeon (bare hands) and unscrubbed
/// skin (the limb's germs) cost it. It is the sterility the open incision gathers germs by until it is closed, so a patient who
/// was not prepped is the one who comes out of surgery with an infection.
/mob/living/carbon/human/proc/surgical_site_sterility(mob/living/user, obj/item/organ/external/part, cleanliness)
	. = isnull(cleanliness) ? 0 : cleanliness
	if(ishuman(user))
		var/mob/living/carbon/human/surgeon = user
		if(!surgeon.get_equipped_item(SLOT_ID_GLOVES))
			. -= SURGERY_NO_GLOVES_STERILITY
	if(part)
		. -= SURGERY_UNPREPPED_SKIN_STERILITY * clamp(part.germ_level / INFECTION_LEVEL_ONE, 0, 1)
	return clamp(., 0, 100)

/proc/spread_germs_to_organ(obj/item/organ/external/E, mob/living/carbon/human/user)
	if(!istype(user) || !istype(E))
		return
	var/germ_level = user.germs()
	if(user.get_equipped_item(SLOT_ID_GLOVES))
		germ_level = user.get_equipped_item(SLOT_ID_GLOVES).germs()
	E.germ_level = max(germ_level, E.germ_level)
