// Surgery framework.
//
// A procedure is a sequence of steps on one limb:
//   access  (incise, retract, saw, pry; unscrew and open a panel)
//   operate (repair, resect, set, remove, insert, implant)
//   close   (set the bone layer, cauterize; secure the panel)
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
// Outcome: success_chance() = tool quality x surface x surgeon x patient.
// A failed step calls complicate(), which injures the patient with a specific
// complication (a cut vessel bleeds, a nicked organ gets a lesion).
// Sterility: surgeon germs spread to the limb, a dirty surface seeds germs,
// and an open incision keeps gathering germs by its sterility until closed.
//
// Synthetic and nanoform limbs use the same steps with repair tags (plating,
// wiring, system restore, panel closure); a step's `part_biology` defaults to
// the biologies its treatment tags work on.

/obj
	///How clean an object is for surgery purposes. Cleaner = less chance of infection.
	var/surgery_cleanliness = 0 // Used for tables/etc which can have surgery done of them.

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

/datum/surgical_step
	// Base types set abstract_type to their own path; they are not registered.
	abstract_type = /datum/surgical_step
	/// Shown in the step picker and the operating computer.
	var/name = "surgical step"
	var/phase = SURGERY_PHASE_OPERATE
	/// Higher priority steps are offered first.
	var/priority = 0

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
			return clamp(allowed_tools[tool_type] + tool.material_tool_quality_bonus, 0, 100)
	for(var/quality in allowed_tool_qualities)
		if(tool.has_tool_quality(quality))
			return clamp(allowed_tool_qualities[quality] + tool.material_tool_quality_bonus, 0, 100)
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
		for(var/obj/item/organ/internal/I as anything in part.internal_organs)
			if(I.owner == target)
				. += I

/// Covered by a spacesuit or helmet?
/datum/surgical_step/proc/coverage_check(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part)
	if(part.organ_tag == BP_HEAD)
		return istype(target.get_equipped_item(SLOT_ID_HEAD), /obj/item/clothing/head/helmet/space)
	return istype(target.get_equipped_item(SLOT_ID_SUIT), /obj/item/clothing/suit/space)

// --- Target selection ---------------------------------------------------------------

/// What the step works on: the part, or (organ scope) one organ in it,
/// chosen by the surgeon when several need it. Null = cancelled.
/datum/surgical_step/proc/choose_target(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	if(scope != SURGERY_SCOPE_ORGAN)
		return part
	var/list/choices = list()
	for(var/obj/item/organ/internal/I as anything in treatment_locations(target, part))
		if(location_needs_treatment(target, I))
			choices[I.name] = I
	if(!length(choices))
		return null
	if(length(choices) == 1)
		return choices[choices[1]]
	var/choice = tgui_input_list(user, "Which organ do you want to work on?", name, choices)
	return choice ? choices[choice] : null

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
	. *= clamp(user.factor(BF_MOTOR_CONTROL), 0, 1)
	if(user == target)
		. *= SURGERY_SELF_MULT

/// Surface multiplier from the surface's cleanliness (operating table 100,
/// roller bed / table 50-75, floor up to 25).
/proc/surgery_surface_mult(cleanliness)
	return SURGERY_FLOOR_SURFACE_MULT + (1 - SURGERY_FLOOR_SURFACE_MULT) * clamp(cleanliness, 0, 100) / 100

/// Patient multiplier: a conscious patient who feels the step flinches. Pain
/// relief (BF_ANALGESIA) and sedation (BF_SEDATION) take the step's pain off;
/// unconscious or pain-immune patients hold still. Only parts that feel pain
/// count: a prosthetic panel doesn't hurt to open.
/datum/surgical_step/proc/patient_mult(mob/living/carbon/human/target, obj/item/organ/external/part)
	if(!pain || target.stat != CONSCIOUS)
		return 1
	if(!(target.body.biology_of(part) & BIOLOGY_ORGANIC) || !target.dq_feels_pain())
		return 1
	if(target.factor(BF_PAIN_IMMUNITY))
		return 1
	var/felt = pain - target.factor(BF_ANALGESIA) - target.factor(BF_SEDATION)
	if(felt <= 0)
		return 1
	return 1 - SURGERY_PAIN_PENALTY * clamp(felt / pain, 0, 1)

/// Chance (0-100) this step succeeds.
/datum/surgical_step/proc/success_chance(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, cleanliness)
	. = tool_quality(tool)
	. *= surgery_surface_mult(cleanliness)
	. *= surgeon_skill(user, target)
	if(part)
		. *= patient_mult(target, part)
	. = clamp(round(., 1), 0, 100)

// --- Effects --------------------------------------------------------------------------

/// Last chance to back out of a drastic step. FALSE = the surgeon stopped.
/datum/surgical_step/proc/confirm(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool)
	return TRUE

/// Starting messages, pain and germs.
/datum/surgical_step/proc/begin(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	var/what = work_target ? "[work_target]" : "body"
	user.visible_message(span_filter_notice("[user] starts [begin_text] [target]'s [what] with \the [tool]."), \
		span_filter_notice("You start [begin_text] [target]'s [what] with \the [tool]."))
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
	user.visible_message(span_notice("[user] [end_text] [target]'s [what] with \the [tool]."), \
		span_notice("You finish [begin_text] [target]'s [what] with \the [tool]."))
	user.balloon_alert_visible("[end_text] [target]'s [what]", "finished [begin_text] \the [what]")

/// A failed step: a specific complication, created as an injury.
/datum/surgical_step/proc/complicate(mob/living/user, mob/living/carbon/human/target, obj/item/organ/external/part, obj/item/tool, atom/work_target)
	var/what = work_target ? "[work_target]" : "body"
	user.visible_message(span_danger("[user]'s hand [fail_text] [target]'s [what] with \the [tool]!"), \
		span_danger("Your hand [fail_text] [target]'s [what] with \the [tool]!"))
	user.balloon_alert_visible("[fail_text] [target]'s [what]", "your hand [fail_text] \the [what]")
	if(!complication_amount)
		return
	var/injury_target = work_target || part
	if(!injury_target)
		return
	target.injure(complication_kind, complication_amount, injury_target, tool, affliction = complication_affliction, flags = INJURE_IGNORE_RESISTANCE)
	log_game("SURGERY: [key_name(user)] failed [name] on [key_name(target)] ([injury_target]): [injury_kind_name(complication_kind)] x[complication_amount] [complication_affliction || ""]")

// --- Running a step -------------------------------------------------------------------

/// Steps `tool` can do on `target` at `zone` right now: name -> step.
/proc/available_surgical_steps(mob/living/user, mob/living/carbon/human/target, zone, obj/item/tool)
	. = list()
	for(var/datum/surgical_step/S as anything in surgical_steps())
		if(!S.tool_quality(tool))
			continue
		var/result = S.can_use(user, target, zone, tool)
		if(!result || result == SURGERY_REFUSED)
			continue
		if(!(S.name in .))
			.[S.name] = S

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

/// Attack-chain entry: try to operate on `M` with this item. TRUE when the
/// attack was consumed by surgery.
/obj/item/proc/do_surgery(mob/living/carbon/M, mob/living/user)
	if(!can_do_surgery(M, user) || !ishuman(M))
		return FALSE
	if(user.a_intent == I_HURT)
		return FALSE
	var/mob/living/carbon/human/target = M
	if(user.action_blocked(ACTION_BLOCK_SURGERY))
		to_chat(user, span_warning("Your hands and head aren't steady enough to operate right now."))
		return TRUE
	var/zone = user.zone_sel?.selecting
	if(!zone)
		return FALSE
	if(zone in target.surgery_zones_in_progress)
		to_chat(user, span_warning("You can't operate on this area while surgery is already in progress."))
		return TRUE
	var/cleanliness = target.get_surgery_cleanliness(user)
	if(isnull(cleanliness)) // standing up
		return FALSE
	cleanliness = clamp(cleanliness + material_surgery_cleanliness_bonus, 0, 100)

	var/list/available = available_surgical_steps(user, target, zone, src)
	if(!length(available))
		return FALSE

	if(target == user)
		to_chat(user, span_critical("You focus on attempting to perform surgery upon yourself."))
		if(!do_after(user, 3 SECONDS, target = target))
			return FALSE

	var/datum/surgical_step/step
	if(length(available) > 1)
		var/choice = tgui_input_list(user, "Select which surgery step you wish to perform", "Surgery Select", available)
		if(!choice)
			return TRUE
		step = available[choice]
	else
		step = available[available[1]]
	// Re-validate: the list and the patient may have changed while choosing.
	if(!step || step.can_use(user, target, zone, src) != TRUE)
		return TRUE
	run_surgical_step(step, user, target, zone, cleanliness)
	return TRUE

/// Perform `step` with this tool: choose the target, wait, roll, perform or
/// complicate. Returns TRUE on success.
/obj/item/proc/run_surgical_step(datum/surgical_step/step, mob/living/user, mob/living/carbon/human/target, zone, cleanliness)
	var/obj/item/organ/external/part = target.get_organ(zone)
	var/atom/work_target = part ? step.choose_target(user, target, part, src) : null
	if(part && !work_target)
		return FALSE
	if(!step.confirm(user, target, part, src))
		return FALSE
	LAZYADD(target.surgery_zones_in_progress, zone)
	step.begin(user, target, part, src, work_target)

	var/chance = step.success_chance(user, target, part, src, cleanliness)
	var/success = TRUE
	var/delay = step.duration * (2 - cleanliness / 100) * toolspeed
	if(!do_after(user, delay, target, target_zone = zone, max_distance = reach))
		success = FALSE
		to_chat(user, span_warning("You must remain close to and keep focused on your patient to conduct surgery."))
		user.balloon_alert(user, "you must remain close to and keep focused on your patient")
	else if(part && !step.target_still_valid(target, part, work_target))
		LAZYREMOVE(target.surgery_zones_in_progress, zone)
		return FALSE
	else if(!prob(chance))
		success = FALSE

	if(success)
		step.perform(user, target, part, src, work_target)
		step.finish_message(user, target, part, src, work_target)
		SEND_SIGNAL(src, COMSIG_MATERIAL_SURGERY, target, zone, TRUE)
		if(user != target && department_for_mob(user) == DEPARTMENT_MEDICAL)
			charge_mob_for_department_service(target, DEPARTMENT_MEDICAL, 5, "Surgical care: [step.name]", user.real_name)
	else
		step.complicate(user, target, part, src, work_target)
		SEND_SIGNAL(src, COMSIG_MATERIAL_SURGERY, target, zone, FALSE)
		user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	log_game("SURGERY: [key_name(user)] [success ? "completed" : "failed"] [step.name] on [key_name(target)] at [zone] (chance [chance]%, surface [cleanliness])")

	// A dirty surface seeds the site with germs.
	part = target.get_organ(zone)
	if(part && step.infection_risk && prob(100 - cleanliness))
		part.adjust_germ_level(rand(10, 20))

	LAZYREMOVE(target.surgery_zones_in_progress, zone)
	target.update_surgery()
	return success

/proc/spread_germs_to_organ(obj/item/organ/external/E, mob/living/carbon/human/user)
	if(!istype(user) || !istype(E))
		return
	var/germ_level = user.germ_level
	if(user.get_equipped_item(SLOT_ID_GLOVES))
		germ_level = user.get_equipped_item(SLOT_ID_GLOVES).germ_level
	E.germ_level = max(germ_level, E.germ_level)
