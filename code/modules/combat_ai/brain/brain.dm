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

	// Dispositions are standings (standings/standings.dm): grudges, effects and faction rows are rows on the mob, not a list on the brain.

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
	/// Tactics started so far (type => times): diagnostics for traces and the creature smoke tests.
	var/tmp/list/started_counts = null
	/// The interval the action loop was last armed with (action_interval()); poke_action_loop() re-arms a stretched one.
	var/tmp/armed_interval = 0
	/// world.time of the last behaviour selection (pick_and_run()); engaged brains re-select at least every DQ_ENGAGED_RECHECK.
	EXPIRY_DECLARE(last_pick_at)
	/// The op the active tactic is waiting on (act_waiting()), null when none.
	var/datum/op_result/waiting_op = null

CAPABILITIES(/datum/ai_brain)
	ref_many(nameof(behavior_sources))
	owns_one(nameof(model), /datum/world_model)
	ref_one(nameof(lord))
	ref_one(nameof(waiting_op))
	modes(nameof(ai_state))

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
	observe(holder, /datum/notice/mob_logout, src, then(PROC_REF(on_holder_logout_event)))
	observe(holder, /datum/notice/standing_changed, src, then(PROC_REF(standings_changed)))
	if(holder.client)
		on_holder_login(holder)
	rebuild_behaviors()
	EXPIRY_STAMP(src, born_at, CLOCK_WORLD)
	set_ai_state(state_set()["calm"])
	seek_pack()
	return ..()


// effective_behaviors maps behaviour type -> the ref text of its source atom (or null): the brain owns no source.
// The atom itself is in behavior_sources, so a deleted source reads null through behavior_source().

/// A running behaviour is stopped (it ends ai_busy on holder) and the loops and chunk sleep are
/// cancelled while holder is still set; phase 4 then clears holder and holder.ai_brain.
/datum/ai_brain/lifecycle_prerelease()
	leave_pack("brain deleted")
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
	// Following a mob that has a brain is swearing to it: the follower joins its pack as sworn (roles/roles.dm). A player or a brainless leader is only followed.
	if(!new_leader)
		unserve()
	else if(isliving(new_leader) && new_leader != holder)
		var/mob/living/lead = new_leader
		if(lead.ai_brain)
			serve(lead)

/// The atom granting behaviour `btype`, or null (innate, or the source was deleted).
/datum/ai_brain/proc/behavior_source(btype)
	var/key = effective_behaviors?[btype]
	if(!key)
		return null
	var/atom/A = locate(key)
	return (A in behavior_sources) ? A : null

// ---------------------------------------------------------------------------
// Loop scheduling (scheduling.dm).
// ---------------------------------------------------------------------------

/datum/ai_brain/proc/manage_processing(desired)
	if(desired & DQAI_PROCESSING)
		DQAI_START_PROCESSING(src)
	else
		DQAI_STOP_PROCESSING(src)

/// Legacy stance setter; accepted as a no-op. The brain has no stance enum.
/datum/ai_brain/proc/set_stance(_stance)
	return

/// Strategic tick. Slow — 2s in combat, idle_strategic_interval when calm.
/datum/ai_brain/proc/handle_strategicals()
	if(QDELETED(holder) || holder.stat >= DEAD)
		// Never qdel from the subsystem tick: the holder's Destroy (or a
		// revive via on_stat_change) owns the brain's lifetime. Just stop
		// ticking; on_stat_change re-arms processing if the mob comes back.
		dqai_log("[holder] brain: tick on dead/deleted holder, sleeping")
		manage_processing(0)
		return
	if(holder.client && !autopilot)
		return
	rebuild_behaviors()
	// Perception is the pack's: this is only the backstop for a pack nothing has stirred for a window.
	pack?.perceive_if_due()
	update_primary_threat()
	selection_dirty = TRUE
	if(primary_threat)
		// Combat: the quarter-second tactical loop owns behavior selection.
		EXPIRY_SET(src, next_strategic_at, 2 SECONDS, CLOCK_WORLD)
		sync_fast_processing()
		return
	// Calm: this is the place no-threat behaviors (wander, idle speak, walk_to_destination, return_home, follow_leader, scavenge, ...) get
	// selected, on the slow cadence rather than per action tick.
	var/idle_pending = pick_and_run()
	if(active_behavior_type)
		// A tick-driven idle behavior is running: the loop drives it until it finishes.
		EXPIRY_SET(src, next_strategic_at, 2 SECONDS, CLOCK_WORLD)
		return
	EXPIRY_SET(src, next_strategic_at, idle_strategic_interval, CLOCK_WORLD)
	// Only park when nothing idle wants to run and no one-shot walk is queued. A brain with an idle behavior scoring > 0 (or cooling down
	// toward one) stays on the slow cadence so it actually gets to act.
	if(!idle_pending && !destination())
		park_calm()

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
				// Still running: re-select only on an event (selection_dirty) or, engaged, once DQ_ENGAGED_RECHECK has passed.
				if(!primary_threat || (!selection_dirty && BEFORE(src, last_pick_at + DQ_ENGAGED_RECHECK, CLOCK_WORLD)))
					return
				if(!selection_dirty)
					trace("engaged recheck (minimum interval)")
				pick_and_run()
				return
			if(DQ_BEHAVIOR_DONE)
				stop_active(DQ_BEHAVIOR_STOP_COMPLETED)
			if(DQ_BEHAVIOR_INTERRUPTED)
				stop_active(DQ_BEHAVIOR_STOP_INTERRUPTED)
			if(DQ_BEHAVIOR_FAILED)
				stop_active(DQ_BEHAVIOR_STOP_FAILED)

	if(!primary_threat)
		// Calm: idle selection lives on the slow cadence (handle_strategicals), never here.
		// If the idle behavior just finished, ask for a prompt re-pick on the next slow run.
		if(!active_behavior_type)
			next_strategic_at = 0
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
	EXPIRY_STAMP(src, last_pick_at, CLOCK_WORLD)
	assess_state()
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
		if(!state_allows(B))
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
	LAZYINITLIST(started_counts)
	started_counts[btype] = (started_counts[btype] || 0) + 1
	trace("start [btype] on [target]")
	var/result = B.start(src, target, source)
	if(result == DQ_BEHAVIOR_DONE)
		stop_active(DQ_BEHAVIOR_STOP_COMPLETED)
	else if(result == DQ_BEHAVIOR_FAILED)
		stop_active(DQ_BEHAVIOR_STOP_FAILED)
	else
		assess_state() // a fleeing tactic running makes the brain fleeing

/datum/ai_brain/proc/stop_active(reason)
	if(!active_behavior_type)
		return
	var/datum/ai_behavior/B = dq_get_behavior(active_behavior_type)
	trace("stop [active_behavior_type] (reason [reason])")
	cancel_waiting_op()
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
	assess_state()

/datum/ai_brain/proc/invalidate_selection()
	selection_dirty = TRUE
	next_strategic_at = 0
	wake_loops()
	sync_fast_processing()
	poke_action_loop()

/// The action loop runs while the brain is awake (not parked), alive and not player-driven.
/datum/ai_brain/proc/sync_fast_processing()
	var/should_process_fast = (process_flags & DQAI_PROCESSING) && holder && !QDELETED(holder) && holder.stat < DEAD && (!holder.client || autopilot)
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
	// The pack hands each member the hostiles it may pick from (doctrine: spread or focus); a pack of one gets its own list.
	var/list/candidates = pack ? pack.targeting_candidates(src) : model.visible_hostiles
	for(var/typepath as anything in target_selector_chain)
		var/datum/target_selector/S = dq_get_selector(typepath)
		new_threat = S.select(src, candidates)
		if(new_threat)
			break
	if(new_threat != primary_threat)
		trace("target [new_threat || "none"] (was [primary_threat || "none"]) from [length(candidates)] candidate(s)")
		pack?.trace("[holder] assigned [new_threat || "no target"]")
		rel_set(src, nameof(primary_threat), new_threat)
		sync_fast_processing()
		assess_state()

/// Shared "we no longer have a threat" path: clears the slot, signals, stops
/// whatever combat behavior was chasing it and leaves the fast loop.
/datum/ai_brain/proc/drop_primary_threat()
	lose_threat_at = 0
	rel_clear(src, nameof(primary_threat))
	if(active_behavior_type)
		stop_active(DQ_BEHAVIOR_STOP_INTERRUPTED)
	sync_fast_processing()
	assess_state()

/// TRUE if being struck by `attacker` should make us hostile to them. Same-faction
/// mobs and table-declared allies don't feud over friendly fire / splash damage;
/// an explicit personal grudge (already HOSTILE) always counts.
/datum/ai_brain/proc/should_retaliate_against(mob/attacker)
	if(!attacker || !holder || attacker == holder)
		return FALSE
	var/grudge = grudge_value(attacker)
	if(!isnull(grudge) && dq_standing_disposition(grudge) <= DQ_DISPOSITION_HOSTILE)
		return TRUE
	if(holder.faction && attacker.faction == holder.faction)
		dqai_log("[holder] brain: ignoring hit from faction-mate [attacker]")
		return FALSE
	if(disposition_to(attacker) >= DQ_DISPOSITION_ALLY)
		dqai_log("[holder] brain: ignoring hit from ally [attacker]")
		return FALSE
	return TRUE

// ---------------------------------------------------------------------------
// Dispositions: standings/standings.dm (disposition_to(), add_personal(), grudge_value()).
// ---------------------------------------------------------------------------

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
		release_servants()
		unserve()
		leave_pack("died")
	else if(old_stat >= DEAD)
		manage_processing(DQAI_PROCESSING)
		seek_pack()

/// Called by /mob/living/dq_notify_damage when the mob takes a hit.
/datum/ai_brain/proc/notify_damage(amount, injury_kind, atom/attacker)
	if(!model || !holder)
		return
	model.record_damage(amount, injury_kind, attacker)
	stir_pack("member hurt")
	if(ismob(attacker) && attacker != holder && should_retaliate_against(attacker))
		add_personal(attacker, DQ_DISPOSITION_HOSTILE, DQ_GRUDGE_DURATION, "hit me")
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
	if(waits_on_op())
		return TRUE
	return holder ? (work_busy(holder) || task_busy(holder)) : FALSE

/// An AI mob starts an ability whose later steps are timers: a hold task claims the mob, so its
/// brain stops choosing, until ai_busy_end() or `cap` runs out. No-op without an AI.
/mob/living/proc/ai_busy_begin(cap = 1 MINUTE)
	if(!ai_brain)
		return
	return hold_busy(src, cap)

/// Ends the hold ai_busy_begin() started (a timed action's own claim ends with its task).
/mob/living/proc/ai_busy_end()
	release_busy(src)

/// the active_target this refers to (a relation view: null once it is deleted).
/datum/ai_brain/proc/active_target() as /atom
	return active_target

/// null for innate, else the item/modifier granting it (a relation view: null once it is deleted).
/datum/ai_brain/proc/active_source() as /atom
	return active_source

/// for guard / return_home behaviors (a relation view: null once it is deleted).
/datum/ai_brain/proc/home_turf() as /turf
	return home_turf
