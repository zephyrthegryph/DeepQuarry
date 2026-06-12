// /datum/ai_brain — the coordinator. Replaces /datum/ai_holder for any mob
// with use_modern_ai = TRUE.
//
// Lean by design — under 10 instance vars, no behavioural code on the brain
// itself. All decisions are delegated to /datum/ai_behavior and
// /datum/target_selector singletons. State that can't be class-level lives in
// the world model (per-tick perception) or behavior_state (per-mob cooldowns).
//
// Duck-typed compatible with SSai/SSaifast: exposes `holder`, `busy`,
// `handle_strategicals()`, `handle_tactics()`, `process_flags`, `set_stance`.
// SSai sleeps mobs by calling set_stance(STANCE_IDLE) — we accept the call as
// a no-op since the brain has no stance enum.

#define DQAI_PROCESSING       (1<<0)
#define DQAI_FASTPROCESSING   (1<<1)

#define DQAI_START_PROCESSING(B) if (!(B.process_flags & DQAI_PROCESSING)) {B.process_flags |= DQAI_PROCESSING; SSai.processing += B}
#define DQAI_STOP_PROCESSING(B)  if (B.process_flags & DQAI_PROCESSING) {B.process_flags &= ~DQAI_PROCESSING; SSai.processing -= B}
#define DQAI_START_FASTPROCESSING(B) if (!(B.process_flags & DQAI_FASTPROCESSING)) {B.process_flags |= DQAI_FASTPROCESSING; SSaifast.processing += B}
#define DQAI_STOP_FASTPROCESSING(B)  if (B.process_flags & DQAI_FASTPROCESSING) {B.process_flags &= ~DQAI_FASTPROCESSING; SSaifast.processing -= B}

/datum/ai_brain
	// --- SSai duck-typed surface ---
	var/mob/living/holder = null    // SSai reads this. Same name as ai_holder.
	var/busy = FALSE                // SSai reads this. Set TRUE while a behavior locks reselection.
	var/process_flags = 0           // bitmask of DQAI_PROCESSING / FASTPROCESSING.

	// --- Configuration ---
	var/intelligence = AI_NORMAL    // Tiered AI level, mirroring legacy holder.
	var/vision_range = 7
	var/autopilot = FALSE           // If TRUE, brain ticks even when a player is in the mob.

	// --- Cached perception. `model` not `world` — `world` is a BYOND global. ---
	var/datum/world_model/model = null

	// --- Targeting ---
	var/mob/living/primary_threat = null     // single "current enemy" slot
	var/list/target_selector_chain = null    // list of typepaths, queried in order

	// --- Active action ---
	var/active_behavior_type = null   // typepath of currently-running behavior
	var/atom/active_target = null
	var/atom/active_source = null     // null for innate, else the item/modifier granting it
	var/selection_dirty = TRUE

	// --- Behavior aggregation ---
	var/list/effective_behaviors = null  // typepath => source_atom_or_null

	// --- Per-behavior state ---
	var/list/behavior_state = null       // typepath => list("cooldown" = world.time, "charges" = N)

	// --- Personal relationships. Lazylist. ---
	var/list/personal = null             // weakref => list("disp", "expires")

	// --- Signal subscriptions ---
	var/list/subscribed_signals = null   // signal_type => list(behavior_typepath, ...)

	// --- Tactical state (read by behaviors) ---
	var/last_attack_at = 0           // world.time of the most recent successful attack tick
	var/last_juke_at = 0             // last world.time evasive_juke fired
	var/turf/home_turf = null        // for guard / return_home behaviors
	var/datum/weakref/leader_ref = null  // for follow_leader / cooperative AI
	/// world.time when primary_threat first left view(). Used to mirror legacy
	/// ai_holder lose_target_timeout: the mob keeps pursuing for
	/// DQ_LOSE_THREAT_TIMEOUT deciseconds before dropping the target.
	var/lose_threat_at = 0
	/// world.time of the last event-driven react_now() re-selection. Debounces a
	/// burst of same-tick events down to a single re-pick (and stops synchronous
	/// re-entry, since behaviors don't sleep so all re-entry is same-tick).
	var/last_react_tick = 0

/datum/ai_brain/New(mob/living/owner)
	if(!owner)
		stack_trace("ai_brain instantiated with no owner")
		qdel(src)
		return
	holder = owner
	model = new /datum/world_model(owner)
	target_selector_chain = list(/datum/target_selector/closest)
	home_turf = get_turf(owner)
	manage_processing(DQAI_PROCESSING | DQAI_FASTPROCESSING)
	RegisterSignal(holder, COMSIG_MOB_STATCHANGE, PROC_REF(on_stat_change))
	// Lazily add the player-castable-moves dispatcher verb on login — avoids
	// bloating the verbs list of every wild simple_mob in the round.
	RegisterSignal(holder, COMSIG_MOB_LOGIN, PROC_REF(on_holder_login))
	if(holder.client)
		on_holder_login(holder)
	rebuild_behaviors()
	return ..()

/datum/ai_brain/Destroy()
	if(active_behavior_type)
		var/datum/ai_behavior/B = dq_get_behavior(active_behavior_type)
		B.stop(src, active_target, active_source, DQ_BEHAVIOR_STOP_QDEL)
	if(holder)
		UnregisterSignal(holder, COMSIG_MOB_STATCHANGE)
		UnregisterSignal(holder, COMSIG_MOB_LOGIN)
	manage_processing(0)
	QDEL_NULL(model)
	holder = null
	primary_threat = null
	active_target = null
	active_source = null
	effective_behaviors = null
	behavior_state = null
	personal = null
	subscribed_signals = null
	return ..()

/datum/ai_brain/proc/get_owner()
	return holder

/datum/ai_brain/proc/get_leader()
	return leader_ref?.resolve()

/datum/ai_brain/proc/set_leader(mob/leader)
	leader_ref = leader ? WEAKREF(leader) : null

// ---------------------------------------------------------------------------
// SSai-compatible surface.
// ---------------------------------------------------------------------------

/datum/ai_brain/proc/manage_processing(desired)
	if(desired & DQAI_PROCESSING)
		DQAI_START_PROCESSING(src)
	else
		DQAI_STOP_PROCESSING(src)
	if(desired & DQAI_FASTPROCESSING)
		DQAI_START_FASTPROCESSING(src)
	else
		DQAI_STOP_FASTPROCESSING(src)

/// SSai calls this when sleeping the mob; accept gracefully. Brain has no
/// stance enum — sleeping just halts behavior selection naturally.
/datum/ai_brain/proc/set_stance(_stance)
	return

/// Strategic tick. Slow — 2s.
/datum/ai_brain/proc/handle_strategicals()
	if(QDELETED(holder) || holder.stat >= DEAD)
		qdel(src)
		return
	if(holder.client && !autopilot)
		return
	rebuild_behaviors()
	model.update_perception(src)
	expire_personal()
	update_primary_threat()
	selection_dirty = TRUE

/// Tactical tick. Fast — 250ms.
/datum/ai_brain/proc/handle_tactics()
	if(QDELETED(holder) || holder.stat >= DEAD)
		return
	if(holder.client && !autopilot)
		return
	if(busy)
		return

	if(active_behavior_type)
		var/datum/ai_behavior/B = dq_get_behavior(active_behavior_type)
		var/result = B.tick(src, active_target, active_source)
		switch(result)
			if(DQ_BEHAVIOR_CONTINUE)
				return
			if(DQ_BEHAVIOR_DONE)
				stop_active(DQ_BEHAVIOR_STOP_COMPLETED)
			if(DQ_BEHAVIOR_INTERRUPTED)
				stop_active(DQ_BEHAVIOR_STOP_INTERRUPTED)
			if(DQ_BEHAVIOR_FAILED)
				stop_active(DQ_BEHAVIOR_STOP_FAILED)

	if(!selection_dirty && active_behavior_type)
		return

	pick_and_run()

// ---------------------------------------------------------------------------
// Behavior aggregation.
// ---------------------------------------------------------------------------

/datum/ai_brain/proc/rebuild_behaviors()
	if(!holder)
		return
	var/list/old = effective_behaviors
	effective_behaviors = list()

	// Innate behaviors via the mob's getter — falls back to the default factory
	// for simple_mobs that haven't been hand-tuned yet.
	var/list/innate = holder.get_ai_behaviors()
	if(!innate && istype(holder, /mob/living/simple_mob))
		innate = dq_default_behavior_list_for(holder)
	if(innate)
		for(var/btype as anything in innate)
			effective_behaviors[btype] = null

	// Equipment-granted (held items).
	for(var/obj/item/I as anything in holder.get_all_held_items())
		var/list/granted = I.get_dq_granted_behaviors()
		if(granted)
			for(var/btype as anything in granted)
				effective_behaviors[btype] = I

	// Modifier-granted (statuses, buffs).
	for(var/datum/modifier/M in holder.modifiers)
		var/list/granted = M.get_dq_granted_behaviors()
		if(granted)
			for(var/btype as anything in granted)
				effective_behaviors[btype] = M

	// Inject behaviors implied by legacy-compat flags so callers can flip
	// brain.returns_home = TRUE on a mob even after spawn and have it work.
	if(mauling && !effective_behaviors[/datum/ai_behavior/maul_unconscious])
		effective_behaviors[/datum/ai_behavior/maul_unconscious] = null
	if(returns_home && !effective_behaviors[/datum/ai_behavior/return_home])
		effective_behaviors[/datum/ai_behavior/return_home] = null

	resync_behavior_signals(old, effective_behaviors)

/// Maintains signal subscriptions: behaviors that listen to events get their
/// eval_triggers registered on the holder, with one shared dispatch proc.
/datum/ai_brain/proc/resync_behavior_signals(list/old_set, list/new_set)
	if(!holder)
		return
	LAZYINITLIST(subscribed_signals)
	for(var/btype in new_set)
		if(old_set && (btype in old_set))
			continue
		var/datum/ai_behavior/B = dq_get_behavior(btype)
		if(!B.eval_triggers)
			continue
		for(var/sig in B.eval_triggers)
			LAZYADD(subscribed_signals[sig], btype)
	if(old_set)
		for(var/btype in old_set)
			if(btype in new_set)
				continue
			var/datum/ai_behavior/B = dq_get_behavior(btype)
			if(!B.eval_triggers)
				continue
			for(var/sig in B.eval_triggers)
				LAZYREMOVE(subscribed_signals[sig], btype)
	UNSETEMPTY(subscribed_signals)

// ---------------------------------------------------------------------------
// Behavior selection.
// ---------------------------------------------------------------------------

/datum/ai_brain/proc/pick_and_run()
	selection_dirty = FALSE
	if(!effective_behaviors || !length(effective_behaviors))
		return

	var/best_score = 0
	var/best_class = -INFINITY
	var/best_type = null
	var/atom/best_target = null
	var/atom/best_source = null

	for(var/btype as anything in effective_behaviors)
		var/source = effective_behaviors[btype]
		var/datum/ai_behavior/B = dq_get_behavior(btype)
		if(B.requires_held_source && !source)
			continue
		if(!B.no_threat_required && !primary_threat && B.priority_class >= DQ_BEHAVIOR_PRIORITY_NORMAL)
			continue
		if(!B.applicable_to(holder))
			continue
		if(!B.is_off_cooldown(src, source))
			continue
		var/list/result = B.evaluate(src, source)
		if(!result)
			continue
		var/score = result["score"]
		if(score <= 0)
			continue
		if(B.priority_class > best_class || (B.priority_class == best_class && score > best_score))
			best_class = B.priority_class
			best_score = score
			best_type = btype
			best_target = result["target"]
			best_source = source

	if(!best_type)
		return

	if(best_type == active_behavior_type && active_behavior_type)
		// Same behavior, possibly new target. Retargeting in-place is correct
		// for tick-driven behaviors (approach_threat reads `target` each tick).
		// Re-face the new target so the mob's sprite reorients immediately
		// instead of waiting for the next step.
		if(active_target != best_target)
			active_target = best_target
			if(holder && best_target)
				holder.face_atom(best_target)
		return

	run_behavior(best_type, best_target, best_source)

/datum/ai_brain/proc/run_behavior(btype, atom/target, atom/source)
	if(active_behavior_type)
		stop_active(DQ_BEHAVIOR_STOP_INTERRUPTED)
	active_behavior_type = btype
	active_target = target
	active_source = source
	var/datum/ai_behavior/B = dq_get_behavior(btype)
	var/result = B.start(src, target, source)
	if(result == DQ_BEHAVIOR_DONE)
		stop_active(DQ_BEHAVIOR_STOP_COMPLETED)
	else if(result == DQ_BEHAVIOR_FAILED)
		stop_active(DQ_BEHAVIOR_STOP_FAILED)

/datum/ai_brain/proc/stop_active(reason)
	if(!active_behavior_type)
		return
	var/datum/ai_behavior/B = dq_get_behavior(active_behavior_type)
	B.stop(src, active_target, active_source, reason)
	active_behavior_type = null
	active_target = null
	active_source = null
	// Defensive: if a behavior's start() runtimed before clearing busy, the
	// brain would lock up. stop_active is the funnel for every termination,
	// so always release the lock here regardless of blocks_reselection.
	busy = FALSE
	// Force the next tick to re-pick rather than wait for the slow tick to
	// flip selection_dirty.
	selection_dirty = TRUE

/datum/ai_brain/proc/invalidate_selection()
	selection_dirty = TRUE

/// Re-decide and act THIS instant instead of waiting up to a tactical tick (~250ms). Combat is
/// sub-second, so reactions (retaliating to a hit, dodging an incoming swing) must be event-driven
/// or the mob is always a beat behind. handle_tactics() keeps its own guards (busy / dead / client),
/// and selection_dirty stays set so a busy mob still re-picks on its next tick.
/datum/ai_brain/proc/react_now()
	selection_dirty = TRUE
	// Collapse a burst of same-tick events into one re-selection. Set the stamp
	// BEFORE handle_tactics so a synchronous re-entrant react_now (a behavior that
	// deals damage notifying through this same brain) is debounced out — behaviors
	// don't sleep, so all re-entry lands in this same tick. selection_dirty stays
	// set, so anything skipped is picked up on the next tactical tick.
	if(last_react_tick == world.time)
		return
	last_react_tick = world.time
	handle_tactics()

// ---------------------------------------------------------------------------
// Targeting.
// ---------------------------------------------------------------------------

/datum/ai_brain/proc/update_primary_threat()
	if(!model || !length(model.visible_hostiles))
		if(primary_threat)
			// Mirror legacy ai_holder lose_target_timeout: hold the target for
			// DQ_LOSE_THREAT_TIMEOUT after it leaves view before giving up.
			// This prevents caves-are-dark from dropping the target the instant
			// the player steps one tile out of the narrow view() cone.
			if(!lose_threat_at)
				lose_threat_at = world.time
				return  // Start the grace timer; don't drop yet.
			if(world.time < lose_threat_at + DQ_LOSE_THREAT_TIMEOUT)
				return  // Still within the grace period.
			// Grace period expired — drop the target.
			lose_threat_at = 0
			var/old = primary_threat
			primary_threat = null
			SEND_SIGNAL(holder, COMSIG_DQAI_TARGET_LOST, old)
		return
	// Target is visible again — reset the grace timer.
	lose_threat_at = 0
	var/new_threat = null
	for(var/typepath as anything in target_selector_chain)
		var/datum/target_selector/S = dq_get_selector(typepath)
		new_threat = S.select(src, model.visible_hostiles)
		if(new_threat)
			break
	if(new_threat != primary_threat)
		var/old = primary_threat
		primary_threat = new_threat
		SEND_SIGNAL(holder, COMSIG_DQAI_TARGET_CHANGED, new_threat, old)

// ---------------------------------------------------------------------------
// Dispositions.
// ---------------------------------------------------------------------------

/datum/ai_brain/proc/disposition_to(mob/other)
	if(!other || other == holder)
		return DQ_DISPOSITION_ALLY
	if(personal)
		var/ref = WEAKREF(other)
		var/list/entry = personal[ref]
		if(entry)
			if(entry["expires"] && entry["expires"] < world.time)
				personal -= ref
				UNSETEMPTY(personal)
			else
				return entry["disp"]
	// A shared non-null faction string means teammates, registry or not. The
	// faction_data tables describe CROSS-faction stances; without this, mobs whose
	// faction isn't enumerated (most wildlife) fall through to the default data,
	// whose null faction_key never matches, so packmates resolve NEUTRAL instead of
	// ALLY — which silently kills pack cohesion and call_for_help (visible_friendlies).
	if(holder.faction && other.faction == holder.faction)
		return DQ_DISPOSITION_ALLY
	var/datum/faction_data/data = dq_faction_data_for(holder.faction)
	var/result
	if(other.client)
		result = data.player_disposition
	else
		var/other_faction = other.faction
		result = data.disposition_to_faction(other_faction)
	// Fallback for mobs whose faction string isn't in the registry: honor the
	// per-mob ai_attack_on_sight flag so unenumerated factions still aggress
	// on strangers as expected. Faction-mates and explicit ALLY/FRIENDLY/WARY
	// entries from the table are preserved.
	if(result == DQ_DISPOSITION_NEUTRAL && istype(holder, /mob/living/simple_mob))
		var/mob/living/simple_mob/SM = holder
		if(SM.ai_attack_on_sight && holder.faction != other.faction)
			// Quarry-spawned fauna of different species coexist rather than tearing
			// the layer's ecosystem apart: stay NEUTRAL toward each other. Same
			// species is ALLY (handled above), and players aren't fauna, so they're
			// still engaged on sight.
			var/mob/living/simple_mob/other_sm = other
			if(SM.quarry_fauna && istype(other_sm) && other_sm.quarry_fauna)
				return DQ_DISPOSITION_NEUTRAL
			result = DQ_DISPOSITION_HOSTILE
	return result

/datum/ai_brain/proc/add_personal(mob/other, disposition, duration = DQ_PERSONAL_DEFAULT_DURATION, reason = null)
	if(!other)
		return
	LAZYINITLIST(personal)
	personal[WEAKREF(other)] = list(
		"disp" = disposition,
		"expires" = duration ? world.time + duration : 0,
		"reason" = reason,
	)
	selection_dirty = TRUE

/datum/ai_brain/proc/expire_personal()
	if(!personal)
		return
	var/now = world.time
	// Iterate over a copy of the keys so modifying `personal` during the loop
	// doesn't skip entries.
	for(var/ref as anything in personal.Copy())
		var/list/entry = personal[ref]
		if(entry && entry["expires"] && entry["expires"] < now)
			personal -= ref
	UNSETEMPTY(personal)

// ---------------------------------------------------------------------------
// Behavior state (cooldowns, charges).
// ---------------------------------------------------------------------------

/datum/ai_brain/proc/cooldown_until(btype, atom/source)
	if(source)
		return 0  // item-granted: source manages its own cooldown
	if(!behavior_state)
		return 0
	var/list/entry = behavior_state[btype]
	if(!entry)
		return 0
	return entry["cooldown"] || 0

/datum/ai_brain/proc/set_cooldown(btype, atom/source, duration)
	if(source)
		return
	LAZYINITLIST(behavior_state)
	if(!behavior_state[btype])
		behavior_state[btype] = list("cooldown" = 0, "charges" = null)
	behavior_state[btype]["cooldown"] = world.time + duration

/datum/ai_brain/proc/consume_charge(btype, atom/source)
	if(source)
		return
	LAZYINITLIST(behavior_state)
	if(!behavior_state[btype])
		return
	var/list/entry = behavior_state[btype]
	if(!isnull(entry["charges"]))
		entry["charges"] -= 1

// ---------------------------------------------------------------------------
// Signal handlers.
// ---------------------------------------------------------------------------

/datum/ai_brain/proc/on_stat_change(mob, old_stat, new_stat)
	SIGNAL_HANDLER
	if(new_stat >= DEAD)
		manage_processing(0)
		stop_active(DQ_BEHAVIOR_STOP_INTERRUPTED)
	else if(old_stat >= DEAD)
		manage_processing(DQAI_PROCESSING | DQAI_FASTPROCESSING)

/// Called by /mob/living/dq_notify_damage when the mob takes a hit.
/datum/ai_brain/proc/notify_damage(amount, damagetype, atom/attacker)
	if(!model || !holder)
		return
	model.record_damage(amount, damagetype, attacker)
	if(ismob(attacker) && attacker != holder)
		add_personal(attacker, DQ_DISPOSITION_HOSTILE, DQ_PERSONAL_DEFAULT_DURATION, "hit me")
		if(!primary_threat)
			primary_threat = attacker // target the attacker NOW so react_now() can act this instant
	SEND_SIGNAL(holder, COMSIG_DQAI_DAMAGE_TAKEN, amount, damagetype, attacker)
	dispatch_behavior_signal(COMSIG_DQAI_DAMAGE_TAKEN, amount, damagetype, attacker)
	if(holder.maxHealth && holder.health / holder.maxHealth <= DQ_LOW_HP_THRESHOLD)
		dispatch_behavior_signal(COMSIG_DQAI_LOW_HEALTH, holder.health / holder.maxHealth)
	react_now() // retaliate immediately instead of on the next tactical tick

/// Forwards a behavior signal to every subscribed behavior. `args` after
/// sig_type are passed through verbatim.
/// Cancel the active behavior IFF it opted into being interrupted by sig_type
/// (interruptible_by). Called by a reaction behavior the moment it COMMITS — so an
/// elite's flinch-cancellable heavy is yanked only when the mob actually dodges/braces,
/// not for free on every passing swing. Returns TRUE if it interrupted something.
/datum/ai_brain/proc/interrupt_if_opted_in(sig_type)
	if(!active_behavior_type)
		return FALSE
	var/datum/ai_behavior/active = dq_get_behavior(active_behavior_type)
	if(active.interruptible_by && (sig_type in active.interruptible_by))
		stop_active(DQ_BEHAVIOR_STOP_INTERRUPTED)
		return TRUE
	return FALSE

/datum/ai_brain/proc/dispatch_behavior_signal(sig_type)
	if(!subscribed_signals || !subscribed_signals[sig_type])
		return
	var/list/tail = args.Copy(2)
	for(var/btype in subscribed_signals[sig_type])
		var/datum/ai_behavior/B = dq_get_behavior(btype)
		B.on_signal(arglist(list(src, sig_type) + tail))
