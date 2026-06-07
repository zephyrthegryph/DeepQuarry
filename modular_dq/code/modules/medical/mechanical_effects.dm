// Mechanical effects framework for medical conditions.
//
// Conditions can declare effects that go beyond "damage and symptoms" —
// slowdown, accuracy penalties, drop-held-item probability, blocked
// verbs, spontaneous emotes. The framework aggregates these across
// active conditions and exposes per-mob query procs.
//
// Effect keys (all optional, all summed across active conditions):
//
//   slowdown                  added to movement_delay
//   accuracy_penalty          subtracted from ranged accuracy
//   drop_held_prob            per-tick % chance to drop held items
//   blocked_verbs             list of verb names that can't be used
//   spontaneous_emotes        list; one is picked per tick at emote_prob
//   spontaneous_emote_prob    % chance per tick to fire an emote
//   block_typing              if any condition sets this, mob can't chat
//   block_hold_arm            arm zone name; mob can't hold items there

/// Aggregate the OD upside (positive effects from overdosed chems)
/// across the mob's active conditions, scaled by per-condition severity.
/// Each contributing condition declares `od_boost = list(key = strength)`
/// where `strength` is the value at severity 100; the proc scales by
/// `severity / 100` so a mild OD (severity 30) contributes 30% of the
/// authored strength.
///
/// Sum is *not* capped here — callers may apply their own ceilings.
/// Currently only OD-style scaling conditions populate od_boost.
/mob/living/carbon/human/proc/dq_od_boost_value(key)
	. = 0
	for(var/datum/medical_issue/condition/C in get_all_conditions())
		if(!C.od_boost)
			continue
		if(isnull(C.od_boost[key]))
			continue
		. += C.od_boost[key] * (C.severity / 100)


/// Per-key cap for aggregate mechanical-effect values. A patient with
/// four cascading conditions shouldn't have their movement multiplied
/// by 4× — the system would feel punishing rather than dangerous.
/// Caps apply across all active conditions on the mob. Keys not present
/// here aren't capped (defensive — new effects authored later opt in
/// explicitly by adding a line here).
GLOBAL_LIST_INIT(dq_mechanical_caps, list(
	"slowdown"          = 2.5,
	"accuracy_penalty"  = 50,
	"drop_held_prob"    = 25,
))

// Per-Life-tick cache of the conditions list. Each of the five public
// mechanical_effects helpers below previously walked
// get_all_conditions() (which itself iterates every organ) independently,
// so a mob with multiple polytrauma conditions paid 5× the walk every
// Life tick. Now they all read the cached list rebuilt at most once per
// world.time stamp.
/mob/living/carbon/human
	var/list/_dq_mechanical_conditions_cache
	var/_dq_mechanical_conditions_cache_time = -1

/mob/living/carbon/human/proc/_dq_mechanical_conditions()
	if(_dq_mechanical_conditions_cache_time == world.time)
		return _dq_mechanical_conditions_cache
	_dq_mechanical_conditions_cache = get_all_conditions()
	_dq_mechanical_conditions_cache_time = world.time
	return _dq_mechanical_conditions_cache

/// Sum a single mechanical-effects key across the mob's active
/// conditions, capped at the per-key ceiling in `dq_mechanical_caps`.
/// Numeric effects sum; lists merge.
/mob/living/carbon/human/proc/dq_mechanical_value(key)
	. = 0
	for(var/datum/medical_issue/condition/C in _dq_mechanical_conditions())
		if(C.mechanical_effects && !isnull(C.mechanical_effects[key]))
			. += C.mechanical_effects[key]
	var/cap = GLOB.dq_mechanical_caps[key]
	if(!isnull(cap) && . > cap)
		. = cap

/mob/living/carbon/human/proc/dq_mechanical_flag(key)
	for(var/datum/medical_issue/condition/C in _dq_mechanical_conditions())
		if(C.mechanical_effects && C.mechanical_effects[key])
			return TRUE
	return FALSE

/mob/living/carbon/human/proc/dq_mechanical_list(key)
	. = list()
	for(var/datum/medical_issue/condition/C in _dq_mechanical_conditions())
		if(C.mechanical_effects && islist(C.mechanical_effects[key]))
			for(var/v in C.mechanical_effects[key])
				. |= v

/// Returns TRUE if any active condition blocks this verb name.
/mob/living/carbon/human/proc/dq_verb_blocked(verb_name)
	for(var/datum/medical_issue/condition/C in _dq_mechanical_conditions())
		if(C.mechanical_effects)
			var/list/blocked = C.mechanical_effects["blocked_verbs"]
			if(islist(blocked) && (verb_name in blocked))
				return TRUE
	return FALSE

/// Returns TRUE if an item held in the given hand-zone (BP_L_ARM /
/// BP_R_ARM) must be dropped because of a condition. Used by the
/// per-tick drop check.
/mob/living/carbon/human/proc/dq_arm_disabled(zone)
	for(var/datum/medical_issue/condition/C in _dq_mechanical_conditions())
		if(C.mechanical_effects)
			var/disabled_arm = C.mechanical_effects["block_hold_arm"]
			if(disabled_arm == zone)
				return TRUE
	return FALSE

/// Each tick, the condition's `tick_condition()` calls this to apply
/// stochastic effects (drop-item, spontaneous emote). Continuous
/// effects (slowdown, accuracy) are pulled by callers instead.
/datum/medical_issue/condition/proc/tick_mechanical_effects()
	if(!mechanical_effects || !owner)
		return
	// Drop-held probability
	var/drop_prob = mechanical_effects["drop_held_prob"]
	if(drop_prob && prob(drop_prob))
		dq_drop_random_held(owner)
	// Spontaneous emote
	var/list/emotes = mechanical_effects["spontaneous_emotes"]
	if(islist(emotes) && length(emotes))
		var/eprob = mechanical_effects["spontaneous_emote_prob"] || 2
		if(prob(eprob))
			owner.emote(pick(emotes))

/proc/dq_drop_random_held(mob/living/carbon/human/H)
	if(!H)
		return
	var/list/candidates = list()
	for(var/obj/item/I in list(H.l_hand, H.r_hand))
		if(I)
			candidates += I
	if(!length(candidates))
		return
	var/obj/item/picked = pick(candidates)
	H.drop_from_inventory(picked)
	to_chat(H, span_warning("Your fingers slip — you drop \the [picked]."))


// --- Integration: condition base proc ---
//
// The base /datum/medical_issue/condition declares `mechanical_effects`
// as a generic list field and calls tick_mechanical_effects() each
// tick. Subtypes override the field with their content.

/datum/medical_issue/condition
	/// list, keyed by mechanical-effect name. Aggregated across active
	/// conditions on the same mob via dq_mechanical_*() procs.
	var/list/mechanical_effects


// --- Hook procs used by upstream callers ---

/// Returns the slowdown contribution from all active conditions on a
/// human. Added to movement_delay() at the call site. Subtracts any
/// "speed" boost from active OD conditions (hyperzine, etc.) so a
/// stim-overdosed patient actually moves faster — capped at 1.0 so a
/// patient can't end up with negative slowdown (movement still has a
/// floor).
/mob/living/carbon/human/proc/dq_condition_slowdown()
	var/slow = dq_mechanical_value("slowdown")
	var/boost = dq_od_boost_value("speed")
	return max(-1.0, slow - boost)
