// Surgery steps as ops (doc/rewrite/body_migration.md, slice 5).
//
// Every /datum/surgical_step is one op on the patient, "surgery_<step>": the surgeon's held tool, a help-style stance, and
// the step's own state checks over the limb (depth, biology, coverage, something to treat) as the op's match. The op asks
// the most urgent organ when several need the step, asks for confirmation on a drastic one (amputation, a cavity implant), claims the
// patient while it waits, and on completion rolls the step's chance: perform() on success, complicate() on a slip. The step
// datums stay the data (tools, depths, treatments, texts); this file is how a person does them.

MSG_DEF_SELF(surgery/unsteady, "Your hands and head aren't steady enough to operate right now.")

/// Surgery comes first on a patient who can be operated on, as it did in the old hit chain: ahead of the hit, vore and the tool's
/// own uses on a mob.
#define SURGERY_OP_PRIORITY 1000

/// The step a surgery op performs, by its op key.
GLOBAL_LIST_EMPTY(surgery_op_steps)

/// The op key of a step type: "surgery_" and the type path under /datum/surgical_step.
/proc/surgery_op_key(step_type)
	return "surgery_[replacetext(copytext("[step_type]", length("[/datum/surgical_step]") + 2), "/", "_")]"

/// One op per concrete surgical step, for the human's CAPABILITIES block.
/proc/surgery_ops()
	. = list()
	// Every step has its own tier: the step's priority first, then declaration order, so a click with a tool that several steps take
	// runs the one the old step picker listed first (the rest stay in the menu).
	var/order = 0
	for(var/step_type in subtypesof(/datum/surgical_step))
		if(is_abstract(step_type))
			continue
		order++
		var/datum/surgical_step/S = step_type
		. += op(surgery_op_key(step_type), item(/obj/item), label(initial(S.name)), stance(I_HELP, I_DISARM, I_GRAB),
			priority(SURGERY_OP_PRIORITY + initial(S.priority) * 100 - order),
			when(TYPE_PROC_REF(/mob/living/carbon/human, surgery_offered)),
			needs(req(TYPE_PROC_REF(/mob/living/carbon/human, surgery_hands_steady), because = MSG(surgery/unsteady))),
			surgery_confirms(),
			claims(),
			begins(TYPE_PROC_REF(/mob/living/carbon/human, surgery_begins)),
			wait(TYPE_PROC_REF(/mob/living/carbon/human, surgery_wait)),
			on_interrupt(TYPE_PROC_REF(/mob/living/carbon/human, surgery_interrupted)),
			then(TYPE_PROC_REF(/mob/living/carbon/human, surgery_done)))

/// The drastic steps' confirmation: a yes/no whose "no" ends the op, asked only when the step has a question.
/proc/surgery_confirms()
	return part_make(/datum/entry/part/asks, list("type" = /datum/prompt/yes_no, "fields" = list("question" = computed(TYPE_PROC_REF(/mob/living/carbon/human, surgery_confirm_text)), "timeout" = 0),
		"step" = "confirm", "resume" = CAPTURE, "keeps" = WAIT_KEEPS_DEFAULT, "confirms" = TRUE, "when" = TYPE_PROC_REF(/mob/living/carbon/human, surgery_confirm_asked)))

/// The step prototype an op runs.
/proc/surgery_step_for_key(key)
	if(!length(GLOB.surgery_op_steps))
		for(var/datum/surgical_step/S as anything in surgical_steps())
			GLOB.surgery_op_steps[surgery_op_key(S.type)] = S
	return GLOB.surgery_op_steps[key]

/datum/body/humanoid
	/// REF(surgeon) -> list(zone, cleanliness, REF(work target), chance) of the step that surgeon has under way on this body. Refs, not
	/// entities: a step's record never keeps a surgeon or an organ alive.
	var/alist/surgery_records

/// The zone the surgeon is working on: their selected zone.
/proc/surgery_zone(mob/living/user)
	return hud_of(user)?.zone_sel?.selecting

// --- Match and Require --------------------------------------------------------------------------

/// The step can be done here and now with this tool: the patient lies on a surface (or operates on themself), and the limb's
/// state is what the step needs. A step that can't is not offered, so the click falls through to whatever else the tool does.
/mob/living/carbon/human/proc/surgery_offered(datum/act/op/A)
	var/datum/surgical_step/S = surgery_step_for_key(A.key)
	var/mob/living/user = A.actor
	var/obj/item/tool = A.held
	if(!S || !istype(user) || !istype(tool))
		return FALSE
	if(!can_operate(src, user, I_HELP) || !tool.can_do_surgery(src, user))
		return FALSE
	var/zone = surgery_zone(user)
	if(!zone || isnull(get_surgery_cleanliness(user)))
		return FALSE
	if(!S.tool_quality(tool))
		return FALSE
	return S.can_use(user, src, zone, tool) == TRUE

/mob/living/carbon/human/proc/surgery_hands_steady(datum/act/op/A)
	var/mob/living/user = A.actor
	return (istype(user) && !user.action_blocked(ACTION_BLOCK_SURGERY)) ? null : MSG(surgery/unsteady)

// --- The questions ------------------------------------------------------------------------------

/// What the step works on in the selected limb: the organ its tool use lands on, or null when it works on the limb itself. The
/// surgeon is never asked: the most urgent finding goes first (`ordered_target_choices()`), and the choice is logged.
/mob/living/carbon/human/proc/surgery_target_pick(datum/act/op/A, obj/item/organ/external/part)
	var/datum/surgical_step/S = surgery_step_for_key(A.key)
	if(!S || !part)
		return null
	var/list/choices = S.ordered_target_choices(A.actor, src, part, A.held)
	if(!length(choices))
		return null
	var/picked = choices[1]
	log_game("SURGERY: [key_name(A.actor)] [S.name] on [key_name(src)] [part] works on [picked] first (of [english_list(choices)])")
	return choices[picked]

/mob/living/carbon/human/proc/surgery_confirm_text(datum/act/op/A)
	var/datum/surgical_step/S = surgery_step_for_key(A.key)
	var/obj/item/organ/external/part = get_organ(surgery_zone(A.actor))
	return (S && part) ? S.confirm_text(A.actor, src, part, A.held) : null

/mob/living/carbon/human/proc/surgery_confirm_asked(datum/act/op/A)
	return !!surgery_confirm_text(A)

// --- Doing it -----------------------------------------------------------------------------------

/// The step starts: what it works on is settled, the surgeon is seen to begin, the patient feels it, germs and blood transfer.
/mob/living/carbon/human/proc/surgery_begins(datum/act/op/A)
	var/datum/surgical_step/S = surgery_step_for_key(A.key)
	var/mob/living/user = A.actor
	var/obj/item/tool = A.held
	var/zone = surgery_zone(user)
	var/obj/item/organ/external/part = get_organ(zone)
	var/atom/work_target = part
	var/atom/picked = surgery_target_pick(A, part)
	if(picked)
		work_target = picked
	var/cleanliness = clamp(get_surgery_cleanliness(user) + material_build_view(tool).surgery_cleanliness_bonus, 0, 100)
	if(user == src)
		to_chat(user, span_critical("You focus on attempting to perform surgery upon yourself."))
	var/datum/body/humanoid/B = body
	ALAZYSET(B.surgery_records, handle_of(user), list(zone, cleanliness, handle_of(work_target), S.success_chance(user, src, part, tool, cleanliness)))
	S.begin(user, src, part, tool, work_target)
	return null

/// How long the step takes: its duration on this surface at this tool's speed, plus three seconds of focus on yourself.
/mob/living/carbon/human/proc/surgery_wait(datum/act/op/A)
	var/datum/surgical_step/S = surgery_step_for_key(A.key)
	var/list/record = surgery_record(A.actor)
	var/cleanliness = record ? record[2] : 0
	. = S.duration * (2 - cleanliness / 100) * tooling_of(A.held).speed
	if(A.actor == src)
		. += 3 SECONDS

/mob/living/carbon/human/proc/surgery_record(mob/living/user)
	var/datum/body/humanoid/B = body
	return istype(B) ? ALAZYACCESS(B.surgery_records, handle_of(user)) : null

/mob/living/carbon/human/proc/surgery_record_end(mob/living/user)
	var/datum/body/humanoid/B = body
	if(istype(B))
		LAZYREMOVE(B.surgery_records, entity_handle_of(user))

/// An interrupted step is abandoned, not botched: no complication roll, and the target may be gone (audit D16).
/mob/living/carbon/human/proc/surgery_interrupted(datum/act/op/A)
	var/mob/living/user = A.actor
	if(user)
		to_chat(user, span_warning("You must remain close to and keep focused on your patient to conduct surgery."))
		user.balloon_alert(user, "you must remain close to and keep focused on your patient")
	log_game("SURGERY: [key_name(user)] interrupted [A.key] on [key_name(src)]; no complication.")
	surgery_record_end(user)

/// The step's time is up: roll its chance, then perform or complicate.
/mob/living/carbon/human/proc/surgery_done(datum/act/op/A)
	var/datum/surgical_step/S = surgery_step_for_key(A.key)
	var/mob/living/user = A.actor
	var/list/record = surgery_record(user)
	surgery_record_end(user)
	if(!S || !record)
		return
	var/zone = record[1]
	var/obj/item/organ/external/part = get_organ(zone)
	var/atom/work_target = handle_get(record[3])
	if(part && !S.target_still_valid(src, part, work_target))
		return
	// The patient's state is checked as the step lands: a patient who still feels it flinches (felt_pain()), whatever the roll.
	var/felt = part ? S.felt_pain(src, part) : 0
	surgical_step_ended(prob(record[4]), A.held, S, user, zone, record[2], part, work_target, record[4], felt)
