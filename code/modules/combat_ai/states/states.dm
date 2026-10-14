// Brain states (doc/rewrite/ai_packs.md B4): calm, alert, engaged, fleeing, regroup. The brain's `ai_state` is a TRACKED var holding a state capability;
// modes() grants that capability to the brain and revokes the previous one, so a state's every(), on_notice() and after_in_state() entries exist exactly
// while the brain is in it. A state declares:
//   - which tactics may run in it (allows());
//   - how soon a pack with a member in it perceives again (perceive_window()): calm 5 s and event-only, alert and fleeing 1 s, engaged 1 s while a player
//     can see it and 2 s off screen, regroup 1 s;
//   - its own way out: alert and regroup settle to calm on a timer (after_in_state()) once nothing hostile is known; every state re-assesses when the
//     pack has told the brain something new (the ai_perceived notice).
// The state is derived from facts the brain already has (a target, a fleeing tactic running, hostiles known): assess_state() reads them and sets the
// state; nothing keeps a separate "in combat" boolean. A faction or species may swap the set by overriding state_set().
//
// Transitions are traced (brain.trace and the pack's trace).

/// The brain was told something by its pack's perception: its state is re-assessed.
ACTION(ai_perceive, FIXED, notice = /datum/notice/ai_perceived)

/// How long an alert lasts after the fight is over and nothing hostile is known.
#define AI_ALERT_LINGER (10 SECONDS)
/// The longest a flight lasts before the brain regroups.
#define AI_FLEE_LIMIT (15 SECONDS)
/// How long a regrouping brain heads for its pack before it settles.
#define AI_REGROUP_LIMIT (10 SECONDS)

/datum/capability/ai_state
	/// For traces.
	var/state_name = "state"
	/// Deciseconds the pack waits between perceptions while a member is in this state.
	var/perceive_window = PACK_PERCEIVE_ACTIVE

/// May `B` run in this state? Calm and alert take what a brain with no target ran before; engaged everything.
/datum/capability/ai_state/proc/allows(datum/ai_behavior/B)
	return TRUE

/// The coalesce window of a pack with a member of this state (the member `brain` is passed for the relevance read).
/datum/capability/ai_state/proc/window(datum/ai_brain/brain)
	return perceive_window

/// The ai_perceived handler of every state: re-assess.
/datum/capability/ai_state/proc/assess(datum/act/A)
	var/datum/ai_brain/brain = A.holder
	if(istype(brain) && !QDELETED(brain))
		brain.assess_state()

/// A state's own timer ran out: settle to calm unless something hostile is still there.
/datum/capability/ai_state/proc/settle(datum/act/A)
	var/datum/ai_brain/brain = A.holder
	if(istype(brain) && !QDELETED(brain))
		brain.settle_state()

CAPABILITY_TYPE(ai_state_calm, CAP_AI_STATE_CALM, /datum/capability/ai_state/calm, key = NONE)
/datum/capability/ai_state/calm
	state_name = "calm"
	perceive_window = PACK_PERCEIVE_CALM

/datum/capability/ai_state/calm/entries()
	return list(on_notice(/datum/notice/ai_perceived, then(CAP_PROC(assess))))

/datum/capability/ai_state/calm/allows(datum/ai_behavior/B)
	return B.no_threat_required || B.priority_class < DQ_BEHAVIOR_PRIORITY_NORMAL

CAPABILITY_TYPE(ai_state_alert, CAP_AI_STATE_ALERT, /datum/capability/ai_state/alert, key = NONE)
/datum/capability/ai_state/alert
	state_name = "alert"
	perceive_window = PACK_PERCEIVE_ACTIVE

/datum/capability/ai_state/alert/entries()
	return list(
		on_notice(/datum/notice/ai_perceived, then(CAP_PROC(assess))),
		after_in_state(AI_ALERT_LINGER, then(CAP_PROC(settle))))

/datum/capability/ai_state/alert/allows(datum/ai_behavior/B)
	return B.no_threat_required || B.priority_class < DQ_BEHAVIOR_PRIORITY_NORMAL

CAPABILITY_TYPE(ai_state_engaged, CAP_AI_STATE_ENGAGED, /datum/capability/ai_state/engaged, key = NONE)
/datum/capability/ai_state/engaged
	state_name = "engaged"
	perceive_window = PACK_PERCEIVE_ACTIVE

/datum/capability/ai_state/engaged/entries()
	return list(on_notice(/datum/notice/ai_perceived, then(CAP_PROC(assess))))

/// One second while any member of the pack is on a player's screen, two otherwise.
/datum/capability/ai_state/engaged/window(datum/ai_brain/brain)
	return brain?.pack && brain.pack.pack_relevance() >= RELEVANCE_VISIBLE ? PACK_PERCEIVE_ACTIVE : PACK_PERCEIVE_OFFSCREEN

CAPABILITY_TYPE(ai_state_fleeing, CAP_AI_STATE_FLEEING, /datum/capability/ai_state/fleeing, key = NONE)
/datum/capability/ai_state/fleeing
	state_name = "fleeing"
	perceive_window = PACK_PERCEIVE_ACTIVE

/datum/capability/ai_state/fleeing/entries()
	return list(
		on_notice(/datum/notice/ai_perceived, then(CAP_PROC(assess))),
		after_in_state(AI_FLEE_LIMIT, then(CAP_PROC(settle))))

/// A fleeing brain only runs what flees or interrupts.
/datum/capability/ai_state/fleeing/allows(datum/ai_behavior/B)
	return B.flees || B.priority_class >= DQ_BEHAVIOR_PRIORITY_INTERRUPT

CAPABILITY_TYPE(ai_state_regroup, CAP_AI_STATE_REGROUP, /datum/capability/ai_state/regroup, key = NONE)
/datum/capability/ai_state/regroup
	state_name = "regroup"
	perceive_window = PACK_PERCEIVE_ACTIVE

/datum/capability/ai_state/regroup/entries()
	return list(
		on_notice(/datum/notice/ai_perceived, then(CAP_PROC(assess))),
		after_in_state(AI_REGROUP_LIMIT, then(CAP_PROC(settle))))

/// A regrouping brain heads back to its pack: the idle follow and home tactics, and anything that interrupts.
/datum/capability/ai_state/regroup/allows(datum/ai_behavior/B)
	return B.no_threat_required || B.priority_class >= DQ_BEHAVIOR_PRIORITY_INTERRUPT

/// The flyweight of a state type (its allows() and window() are read by the brain and its pack; the engine owns the granted activation).
/proc/dq_ai_state_def(state_type)
	var/static/list/defs = list()
	var/datum/capability/ai_state/def = defs[state_type]
	if(!def)
		def = new state_type
		defs[state_type] = def
	return def

/datum/ai_behavior
	/// TRUE for a tactic whose job is to get away (flee, retreat, hit and run): a brain running one is fleeing.
	var/flees = FALSE

/datum/ai_behavior/flee_low_hp
	flees = TRUE

/datum/ai_behavior/pack_retreat
	flees = TRUE

/datum/ai_behavior/hit_and_run
	flees = TRUE

TRACKED(/datum/ai_brain, ai_state)

/datum/ai_brain
	/// The state capability the brain is in (modes(nameof(ai_state)) grants it): a faction or species may start in another.
	var/ai_state = /datum/capability/ai_state/calm

/// The five states, by what they are called in the traces and tests: the brain's faction may supply its own set (faction_data.states).
/datum/ai_brain/proc/state_set()
	var/datum/faction_data/data = dq_faction_data_for(holder?.faction)
	if(data.states)
		return data.states
	return list(
		"calm" = /datum/capability/ai_state/calm,
		"alert" = /datum/capability/ai_state/alert,
		"engaged" = /datum/capability/ai_state/engaged,
		"fleeing" = /datum/capability/ai_state/fleeing,
		"regroup" = /datum/capability/ai_state/regroup)

/// The state's definition (the flyweight).
/datum/ai_brain/proc/state_def()
	return dq_ai_state_def(ai_state)

/// May this brain run `B` in its state?
/datum/ai_brain/proc/state_allows(datum/ai_behavior/B)
	var/datum/capability/ai_state/S = state_def()
	return S.allows(B)

/// The coalesce window this brain asks of its pack.
/datum/ai_brain/proc/state_window()
	var/datum/capability/ai_state/S = state_def()
	return S.window(src)

/// The state the brain's facts call for: fleeing while a fleeing tactic runs; engaged with a target; regrouping after a flight when the pack has company;
/// alert while a hostile is known or a fight just ended; else calm. Alert and regroup leave by their own timers.
/datum/ai_brain/proc/assess_state()
	var/list/states = state_set()
	var/datum/ai_behavior/B = active_behavior_type ? dq_get_behavior(active_behavior_type) : null
	var/want = states["calm"]
	if(B?.flees)
		want = states["fleeing"]
	else if(primary_threat)
		want = states["engaged"]
	else if(ai_state == states["fleeing"] && length(pack?.members) > 1)
		want = states["regroup"]
	else if(length(model?.visible_hostiles) || ai_state == states["engaged"] || ai_state == states["fleeing"])
		want = states["alert"]
	else if(ai_state == states["alert"] || ai_state == states["regroup"])
		want = ai_state
	enter_state(want)

/// A state's timer ran out: calm unless a target or a hostile is still known (then the facts decide).
/datum/ai_brain/proc/settle_state()
	var/list/states = state_set()
	if(primary_threat || length(model?.visible_hostiles) || active_behavior_type && dq_get_behavior(active_behavior_type).flees)
		assess_state()
		return
	enter_state(states["calm"])

/// Sets the state (through the tracked setter, so modes() swaps the capability) and traces the change.
/datum/ai_brain/proc/enter_state(state_type)
	if(ai_state == state_type)
		return
	var/datum/capability/ai_state/old = dq_ai_state_def(ai_state)
	var/datum/capability/ai_state/new_state = dq_ai_state_def(state_type)
	trace("state [old.state_name] -> [new_state.state_name]")
	pack?.trace("[holder] [old.state_name] -> [new_state.state_name]")
	set_ai_state(state_type)
