// /datum/ai_brain — the coordinator. Replaces /datum/ai_holder for any mob
// with use_modern_ai = TRUE.
//
// Lean by design — under 10 instance vars, no behavioural code on the brain
// itself. All decisions are delegated to /datum/ai_behavior and
// /datum/target_selector singletons. State that can't be class-level lives in
// the world model (per-tick perception) or behavior_state (per-mob cooldowns).
//
// Scheduled by two OM behaviours on the mob (scheduling.dm): a strategic loop (2 s) and a
// tactical loop (0.25 s, only while it has a combat target). They park by the mob's relevance
// and clock; a calm brain hibernates on mob chunks until something moves near it.

#define DQAI_START_PROCESSING(B) B.start_loop(DQAI_PROCESSING)
#define DQAI_STOP_PROCESSING(B) B.stop_loop(DQAI_PROCESSING)
#define DQAI_START_FASTPROCESSING(B) B.start_loop(DQAI_FASTPROCESSING)
#define DQAI_STOP_FASTPROCESSING(B) B.stop_loop(DQAI_FASTPROCESSING)

/datum/ai_brain
	// --- Scheduling ---
	var/mob/living/holder = null    // the mob this brain drives; its OM behaviours run the loops.
	var/process_flags = 0           // loops asked for: DQAI_PROCESSING / DQAI_FASTPROCESSING.

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
	var/tmp/atom/active_target
	var/tmp/atom/active_source	// null for innate, else the item/modifier granting it
	var/selection_dirty = TRUE

	// --- Behavior aggregation ---
	var/list/effective_behaviors = null  // typepath => ref text of its source atom (see behavior_source()) or null
	/// The source atoms effective_behaviors names (a relation list: a deleted source leaves it).
	var/list/behavior_sources = null

	// --- Per-behavior state ---
	var/list/behavior_state = null       // typepath => list("cooldown" = world.time, "charges" = N)

	// --- Personal relationships. Lazylist. ---
	var/list/personal = null             // ref text of the mob => list("disp", "expires"); valid only while the mob is in personal_mobs
	/// The mobs personal names (a relation list: a deleted mob leaves it, and its entry goes stale).
	var/list/personal_mobs = null

	// --- Behavior trigger subscriptions ---
	var/list/subscribed_signals = null   // DQAI_TRIGGER_* => list(behavior_typepath, ...)

	// --- Tactical state (read by behaviors) ---
	EXPIRY_DECLARE(last_attack_at) // world.time of the most recent successful attack tick
	var/last_juke_at = 0             // last world.time evasive_juke fired
	var/tmp/turf/home_turf	// for guard / return_home behaviors
	var/mob/leader = null  // for follow_leader / cooperative AI (a relation view)
	/// world.time when primary_threat first left view(). Used to mirror legacy
	/// ai_holder lose_target_timeout: the mob keeps pursuing for
	/// DQ_LOSE_THREAT_TIMEOUT deciseconds before dropping the target.
	EXPIRY_DECLARE(lose_threat_at)
	/// Dependency-driven strategic scheduling. Events set this to zero; a calm
	/// brain uses a long discovery cadence while combat stays responsive.
	EXPIRY_DECLARE(next_strategic_at)
	var/idle_strategic_interval = 10 SECONDS
	/// While hibernating: the chunks it watches (watch_mob_chunks()).
	var/tmp/list/react_sleep_tokens

CAPABILITIES(/datum/ai_brain)
	ref_many(nameof(behavior_sources))
	ref_many(nameof(personal_mobs))
	owns_one(nameof(model), /datum/world_model)

/datum/ai_brain/New(mob/living/owner)
	if(!owner)
		stack_trace("ai_brain instantiated with no owner")
		spent(src)
		return
	rel_set(src, nameof(holder), owner)
	rel_set(src, nameof(model), new /datum/world_model(owner))
	target_selector_chain = list(/datum/target_selector/closest)
	rel_set(src, nameof(home_turf), get_turf(owner))
	manage_processing(DQAI_PROCESSING)
	observe(holder, /datum/notice/mob_statchange, src, then(PROC_REF(on_stat_change)))
	observe(holder, /datum/notice/living_injured, src, then(PROC_REF(on_holder_injured)))
	// Lazily add the player-castable-moves dispatcher verb on login — avoids
	// bloating the verbs list of every wild simple_mob in the round.
	observe(holder, /datum/notice/mob_login, src, then(PROC_REF(on_holder_login_event)))
	if(holder.client)
		on_holder_login(holder)
	rebuild_behaviors()
	return ..()


// effective_behaviors maps behaviour type -> the ref text of its source atom (or null): the brain owns no source.
// The atom itself is in behavior_sources, so a deleted source reads null through behavior_source().

/// A running behaviour is stopped (it ends ai_busy on holder) and the loops and chunk sleep are
/// cancelled while holder is still set; phase 4 then clears holder and holder.ai_brain.
/datum/ai_brain/lifecycle_prerelease()
	cancel_chunk_sleep()
	if(active_behavior_type)
		var/datum/ai_behavior/B = dq_get_behavior(active_behavior_type)
		B.stop(src, active_target(), active_source(), DQ_BEHAVIOR_STOP_QDEL)
	manage_processing(0)
	return ..()

/datum/ai_brain/proc/get_owner()
	RETURN_TYPE(/mob/living)
	return holder

/datum/ai_brain/proc/get_leader()
	return leader

/datum/ai_brain/proc/set_leader(mob/new_leader)
	rel_set(src, nameof(leader), new_leader)

/// The atom granting behaviour `btype`, or null (innate, or the source was deleted).
/datum/ai_brain/proc/behavior_source(btype)
	var/key = effective_behaviors?[btype]
	if(!key)
		return null
	var/atom/A = locate(key)
	return (A in behavior_sources) ? A : null

/// The personal-disposition entry for `other`, or null. Stale entries (a deleted mob) are dropped.
/datum/ai_brain/proc/personal_entry(mob/other)
	if(!personal || !other)
		return null
	var/key = ref(other)
	var/list/entry = personal[key]
	if(entry && !(other in personal_mobs))
		personal -= key
		UNSETEMPTY(personal)
		return null
	return entry

// ---------------------------------------------------------------------------
// Loop scheduling (scheduling.dm).
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

/// Legacy stance setter; accepted as a no-op. The brain has no stance enum.
/datum/ai_brain/proc/set_stance(_stance)
	return

/// Strategic tick. Slow — 2s in combat, idle_strategic_interval when calm.
/datum/ai_brain/proc/handle_strategicals()
	if(QDELETED(holder) || holder.stat >= DEAD)
		// Never qdel from the subsystem tick: the holder's Destroy (or a
		// revive via on_stat_change) owns the brain's lifetime. Just stop
		// ticking; on_stat_change re-arms processing if the mob comes back.
		dqai_log("[holder] brain: strategic tick on dead/deleted holder, sleeping")
		manage_processing(0)
		return
	if(holder.client && !autopilot)
		return
	rebuild_behaviors()
	model.update_perception(src)
	expire_personal()
	update_primary_threat()
	selection_dirty = TRUE
	if(primary_threat)
		// Combat: the quarter-second tactical loop owns behavior selection.
		EXPIRY_SET(src, next_strategic_at, 2 SECONDS, CLOCK_WORLD)
		sync_fast_processing()
		return
	// Calm: this is the ONLY place no-threat behaviors (wander, idle speak,
	// walk_to_destination, return_home, follow_leader, scavenge, ...) get
	// selected. The tactical loop is combat-scoped, so running pick_and_run
	// here keeps idle cost at the strategic cadence rather than per-250ms.
	var/idle_pending = pick_and_run()
	if(active_behavior_type)
		// A tick-driven idle behavior is running: let the fast loop drive it
		// until it finishes (sync_fast_processing drops us again on DONE).
		EXPIRY_SET(src, next_strategic_at, 2 SECONDS, CLOCK_WORLD)
		sync_fast_processing()
		return
	EXPIRY_SET(src, next_strategic_at, idle_strategic_interval, CLOCK_WORLD)
	sync_fast_processing()
	// Only hibernate when nothing idle wants to run and no one-shot walk is
	// queued. A brain with an idle behavior scoring > 0 (or cooling down
	// toward one) stays on the slow cadence so it actually gets to act.
	if(!idle_pending && !destination())
		hibernate_calm()

/// Tactical tick. Fast — 250ms. Runs while a threat exists OR while a
/// tick-driven behavior (combat or idle) is active; see sync_fast_processing.
/datum/ai_brain/proc/handle_tactics()
	if(QDELETED(holder) || holder.stat >= DEAD)
		manage_processing(0)
		return
	if(holder.client && !autopilot)
		return
	if(is_busy())
		return

	if(active_behavior_type)
		var/datum/ai_behavior/B = dq_get_behavior(active_behavior_type)
		var/result = B.tick(src, active_target(), active_source())
		switch(result)
			if(DQ_BEHAVIOR_CONTINUE)
				return
			if(DQ_BEHAVIOR_DONE)
				stop_active(DQ_BEHAVIOR_STOP_COMPLETED)
			if(DQ_BEHAVIOR_INTERRUPTED)
				stop_active(DQ_BEHAVIOR_STOP_INTERRUPTED)
			if(DQ_BEHAVIOR_FAILED)
				stop_active(DQ_BEHAVIOR_STOP_FAILED)

	if(!primary_threat)
		// Calm: idle selection lives on the strategic cadence (handle_strategicals),
		// never here — that is what keeps wandering mobs off the 250ms loop.
		// If the idle behavior just finished, ask for a prompt re-pick on the
		// next 2s SSai tick instead of waiting out idle_strategic_interval.
		if(!active_behavior_type)
			next_strategic_at = 0
		sync_fast_processing()
		return

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
	rel_clear(src, nameof(behavior_sources))

	// Innate behaviors via the mob's getter — falls back to the default factory
	// for simple_mobs that haven't been hand-tuned yet.
	var/list/innate = TYPE_TABLE_GET(holder, get_ai_behaviors)
	if(!innate && istype(holder, /mob/living/simple_mob))
		innate = dq_default_behavior_list_for(holder)
	if(innate)
		for(var/btype as anything in innate)
			effective_behaviors[btype] = null

	// Equipment-granted (held items).
	for(var/obj/item/I as anything in holder.get_all_held_items())
		var/list/granted = TYPE_TABLE_GET(I, item_granted_behaviors)
		if(granted)
			var/source_ref = ref(I) // effective_behaviors keeps the ref text only; the source itself is behavior_sources
			for(var/btype as anything in granted)
				rel_add(src, nameof(behavior_sources), I)
				effective_behaviors[btype] = source_ref

	// Modifier-granted (statuses, buffs).
	for(var/effect_type in holder.body_effects())
		var/list/granted = body_effect_def(effect_type).get_dq_granted_behaviors()
		if(granted)
			for(var/btype as anything in granted)
				rel_add(src, nameof(behavior_sources), holder)
				effective_behaviors[btype] = ref(holder)

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

/// Evaluates every eligible behavior and runs the winner. Returns TRUE if any
/// behavior scored > 0 or is merely cooling down toward eligibility (callers
/// use this to decide whether a calm brain may hibernate), FALSE otherwise.
/datum/ai_brain/proc/pick_and_run()
	selection_dirty = FALSE
	if(!effective_behaviors || !length(effective_behaviors))
		return FALSE

	var/best_score = 0
	var/best_class = -INFINITY
	var/best_type = null
	var/atom/best_target = null
	var/atom/best_source = null
	var/any_pending = FALSE

	for(var/btype as anything in effective_behaviors)
		var/source = behavior_source(btype)
		var/datum/ai_behavior/B = dq_get_behavior(btype)
		if(B.requires_held_source && !source)
			continue
		if(!B.no_threat_required && !primary_threat && B.priority_class >= DQ_BEHAVIOR_PRIORITY_NORMAL)
			continue
		if(!B.applicable_to(holder))
			continue
		if(!B.is_off_cooldown(src, source))
			// It wants to run later — don't let the brain hibernate past it.
			any_pending = TRUE
			continue
		var/list/result = B.evaluate(src, source)
		if(!result)
			continue
		var/score = result["score"]
		if(score <= 0)
			continue
		any_pending = TRUE
		if(B.priority_class > best_class || (B.priority_class == best_class && score > best_score))
			best_class = B.priority_class
			best_score = score
			best_type = btype
			best_target = result["target"]
			best_source = source

	if(!best_type)
		return any_pending

	if(best_type == active_behavior_type && active_behavior_type)
		// Same behavior, possibly new target. Retargeting in-place is correct
		// for tick-driven behaviors (approach_threat reads `target` each tick).
		// Re-face the new target so the mob's sprite reorients immediately
		// instead of waiting for the next step.
		if(active_target() != best_target)
			rel_set(src, nameof(active_target), best_target)
			if(holder && best_target)
				holder.face_atom(best_target)
		return TRUE

	run_behavior(best_type, best_target, best_source)
	return TRUE

/datum/ai_brain/proc/run_behavior(btype, atom/target, atom/source)
	if(active_behavior_type)
		stop_active(DQ_BEHAVIOR_STOP_INTERRUPTED)
	active_behavior_type = btype
	rel_set(src, nameof(active_target), target)
	rel_set(src, nameof(active_source), source)
	var/datum/ai_behavior/B = dq_get_behavior(btype)
	trace("start [btype] on [target]")
	var/result = B.start(src, target, source)
	if(result == DQ_BEHAVIOR_DONE)
		stop_active(DQ_BEHAVIOR_STOP_COMPLETED)
	else if(result == DQ_BEHAVIOR_FAILED)
		stop_active(DQ_BEHAVIOR_STOP_FAILED)

/datum/ai_brain/proc/stop_active(reason)
	if(!active_behavior_type)
		return
	var/datum/ai_behavior/B = dq_get_behavior(active_behavior_type)
	trace("stop [active_behavior_type] (reason [reason])")
	B.stop(src, active_target(), active_source(), reason)
	active_behavior_type = null
	rel_clear(src, nameof(active_target))
	rel_clear(src, nameof(active_source))
	// Defensive: if a behavior's start() runtimed before releasing its hold, the
	// brain would lock up. stop_active is the funnel for every termination,
	// so always release the hold here regardless of blocks_reselection.
	holder?.ai_busy_end()
	// Force the next tick to re-pick rather than wait for the slow tick to
	// flip selection_dirty.
	selection_dirty = TRUE

/datum/ai_brain/proc/invalidate_selection()
	selection_dirty = TRUE
	next_strategic_at = 0
	wake_from_chunks()
	sync_fast_processing()

/// Keeps the quarter-second tactical loop limited to brains that have a combat
/// target or a tick-driven behavior in flight (an idle walk still needs to step).
/// Calm brains with nothing active never sit on the fast loop.
/datum/ai_brain/proc/sync_fast_processing()
	var/should_process_fast = (primary_threat || active_behavior_type) && holder && !QDELETED(holder) && holder.stat < DEAD && (!holder.client || autopilot)
	if(should_process_fast)
		DQAI_START_FASTPROCESSING(src)
	else
		DQAI_STOP_FASTPROCESSING(src)

// ---------------------------------------------------------------------------
// Targeting.
// ---------------------------------------------------------------------------

/datum/ai_brain/proc/update_primary_threat()
	// A threat that no longer exists in the world (deleted, or pulled out of
	// the map into nullspace) gets dropped at once — no grace timer, since
	// there is nothing to pursue and stale refs would keep behaviors chasing it.
	if(primary_threat && (QDELETED(primary_threat) || !primary_threat.loc))
		dqai_log("[holder] brain: dropping vanished threat [primary_threat]")
		drop_primary_threat()
		return
	if(!model || !length(model.visible_hostiles))
		if(primary_threat)
			// Mirror legacy ai_holder lose_target_timeout: hold the target for
			// DQ_LOSE_THREAT_TIMEOUT after it leaves view before giving up.
			// This prevents caves-are-dark from dropping the target the instant
			// the player steps one tile out of the narrow view() cone.
			if(!lose_threat_at)
				EXPIRY_STAMP(src, lose_threat_at, CLOCK_WORLD)
				return  // Start the grace timer; don't drop yet.
			if(BEFORE(src, lose_threat_at + DQ_LOSE_THREAT_TIMEOUT, CLOCK_WORLD))
				return  // Still within the grace period.
			// Grace period expired — drop the target.
			drop_primary_threat()
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
		rel_set(src, nameof(primary_threat), new_threat)
		sync_fast_processing()

/// Shared "we no longer have a threat" path: clears the slot, signals, stops
/// whatever combat behavior was chasing it and leaves the fast loop.
/datum/ai_brain/proc/drop_primary_threat()
	lose_threat_at = 0
	rel_clear(src, nameof(primary_threat))
	if(active_behavior_type)
		stop_active(DQ_BEHAVIOR_STOP_INTERRUPTED)
	sync_fast_processing()

/// TRUE if being struck by `attacker` should make us hostile to them. Same-faction
/// mobs and table-declared allies don't feud over friendly fire / splash damage;
/// an explicit personal grudge (already HOSTILE) always counts.
/datum/ai_brain/proc/should_retaliate_against(mob/attacker)
	if(!attacker || !holder || attacker == holder)
		return FALSE
	var/list/grudge = personal_entry(attacker)
	if(grudge && grudge["disp"] <= DQ_DISPOSITION_HOSTILE)
		return TRUE
	if(holder.faction && attacker.faction == holder.faction)
		dqai_log("[holder] brain: ignoring hit from faction-mate [attacker]")
		return FALSE
	if(disposition_to(attacker) >= DQ_DISPOSITION_ALLY)
		dqai_log("[holder] brain: ignoring hit from ally [attacker]")
		return FALSE
	return TRUE

// ---------------------------------------------------------------------------
// Dispositions.
// ---------------------------------------------------------------------------

/datum/ai_brain/proc/disposition_to(mob/other)
	if(!other || other == holder)
		return DQ_DISPOSITION_ALLY
	var/list/entry = personal_entry(other)
	if(entry)
		if(entry["expires"] && ELAPSED_SINCE(src, entry["expires"], CLOCK_WORLD) > 0)
			personal -= ref(other)
			UNSETEMPTY(personal)
			rel_remove(src, nameof(personal_mobs), other)
		else
			return entry["disp"]
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
			result = DQ_DISPOSITION_HOSTILE
	return result

/datum/ai_brain/proc/add_personal(mob/other, disposition, duration = DQ_PERSONAL_DEFAULT_DURATION, reason = null)
	if(!other)
		return
	LAZYINITLIST(personal)
	rel_add(src, nameof(personal_mobs), other)
	personal[ref(other)] = list(
		"disp" = disposition,
		"expires" = duration ? world.time + duration : 0,
		"reason" = reason,
	)
	selection_dirty = TRUE

/datum/ai_brain/proc/expire_personal()
	if(!personal)
		return
	var/now = world.time
	// Collect expired keys into a reused temp and subtract once, rather than
	// Copy()ing the whole assoc list every strategic tick. Iterating the live
	// list while only reading is safe; mutation happens after the loop.
	var/list/expired
	for(var/ref in personal)
		var/list/entry = personal[ref]
		var/mob/M = locate(ref)
		if(!(M in personal_mobs)) // the mob was deleted: its entry is stale
			LAZYADD(expired, ref)
		else if(entry && entry["expires"] && entry["expires"] < now)
			LAZYADD(expired, ref)
			rel_remove(src, nameof(personal_mobs), M)
	if(expired)
		personal -= expired
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
	behavior_state[btype]["cooldown"] = EXPIRY_AT(null, CLOCK_WORLD, 0) + duration

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
// Event handlers.
// ---------------------------------------------------------------------------

/datum/ai_brain/proc/on_stat_change(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/mob_statchange/event = A
	var/old_stat = event.old_stat
	var/new_stat = event.new_stat
	if(new_stat >= DEAD)
		manage_processing(0)
		stop_active(DQ_BEHAVIOR_STOP_INTERRUPTED)
	else if(old_stat >= DEAD)
		manage_processing(DQAI_PROCESSING)

/// Called by /mob/living/dq_notify_damage when the mob takes a hit.
/datum/ai_brain/proc/notify_damage(amount, injury_kind, atom/attacker)
	if(!model || !holder)
		return
	model.record_damage(amount, injury_kind, attacker)
	if(ismob(attacker) && attacker != holder && should_retaliate_against(attacker))
		add_personal(attacker, DQ_DISPOSITION_HOSTILE, DQ_PERSONAL_DEFAULT_DURATION, "hit me")
		if(!primary_threat)
			rel_set(src, nameof(primary_threat), attacker)
	PUBLISH_LEGACY(holder, /datum/notice/dqai_damage_taken, amount, injury_kind, attacker)
	dispatch_behavior_signal(DQAI_TRIGGER_DAMAGE_TAKEN, amount, injury_kind, attacker)
	var/wellness = holder.vitality()
	if(wellness <= DQ_LOW_HP_THRESHOLD)
		dispatch_behavior_signal(DQAI_TRIGGER_LOW_HEALTH, wellness)
	invalidate_selection()

/// Forwards a behavior signal to every subscribed behavior. `args` after
/// sig_type are passed through verbatim.
/datum/ai_brain/proc/dispatch_behavior_signal(sig_type)
	if(!subscribed_signals || !subscribed_signals[sig_type])
		return
	var/list/tail = args.Copy(2)
	for(var/btype in subscribed_signals[sig_type])
		var/datum/ai_behavior/B = dq_get_behavior(btype)
		B.on_signal(arglist(list(src, sig_type) + tail))

/// The loops check this: TRUE while a task claims the brain's mob -- an ability's wind-up, a timed
/// action, or a behavior that blocks reselection (code/datums/om/task.dm, task_busy()).
/datum/ai_brain/proc/is_busy()
	return holder ? task_busy(holder) : FALSE

/// An AI mob starts an ability whose later steps are timers: a hold task claims the mob, so its
/// brain stops choosing, until ai_busy_end() or `cap` runs out. No-op without an AI.
/mob/living/proc/ai_busy_begin(cap = 1 MINUTE)
	if(!ai_brain)
		return
	return task_hold_busy(src, cap)

/// Ends the hold ai_busy_begin() started (a timed action's own claim ends with its task).
/mob/living/proc/ai_busy_end()
	var/datum/task/T = task_claiming(src)
	if(istype(T, /datum/task/hold))
		task_cancel(T, "done")

/// the active_target this refers to (a relation view: null once it is deleted).
/datum/ai_brain/proc/active_target() as /atom
	return active_target

/// null for innate, else the item/modifier granting it (a relation view: null once it is deleted).
/datum/ai_brain/proc/active_source() as /atom
	return active_source

/// for guard / return_home behaviors (a relation view: null once it is deleted).
/datum/ai_brain/proc/home_turf() as /turf
	return home_turf
