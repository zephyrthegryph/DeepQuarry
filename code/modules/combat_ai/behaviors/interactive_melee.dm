// Interactive melee behaviors — the NPC half of the player's read-and-react melee kit.
//
/// Tell this brain a telegraphed swing is winding up on its mob (called from the player's
/// begin_melee_swing). Routes to the behavior-signal dispatch so dodge/brace can react. Lives here
/// so callers in the mob tree don't need the combat_ai signal macro in scope.
/datum/ai_brain/proc/notify_incoming_attack(mob/attacker, windup)
	dispatch_behavior_signal(COMSIG_DQAI_INCOMING_ATTACK, attacker, windup)
	react_now() // a dodge/brace has to happen DURING the windup, not on the next tactical tick

// A simple_mob's plain melee_attack is a fast, low-damage poke. telegraphed_strike interrupts that
// rhythm with a readable HEAVY: the mob rears back with a tile telegraph + windup animation, then
// strikes the telegraphed tile. Because it resolves through the normal do_attack path, the player
// can PARRY it (full negate + the mob is opened), soft-BLOCK it (half), or DODGE by stepping off the
// tile during the windup — and whether it lands or whiffs, the mob is left in a recovery opening to
// punish. See the player side in code/modules/mob/living/melee_block.dm / melee_swing.dm.

/datum/ai_behavior/telegraphed_strike
	name = "telegraphed strike"
	desc = "A wound-up heavy blow the target can parry, dodge, or block."
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE // interrupts the poke rhythm while winding up
	target_kind = DQ_TARGET_MOB
	min_range = 0
	max_range = 1
	blocks_reselection = TRUE
	requires_adjacent = TRUE       // central gate: only when in melee reach
	blocked_by_melee_lock = TRUE   // central gate: can't wind up while off-balance
	/// Damage multiplier vs the mob's normal melee.
	var/damage_mult = 2

/datum/ai_behavior/telegraphed_strike/applicable_to(mob/living/owner)
	if(!istype(owner, /mob/living/simple_mob))
		return FALSE
	var/mob/living/simple_mob/SM = owner
	return SM.melee_damage_upper > 0

/datum/ai_behavior/telegraphed_strike/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/owner = brain.get_owner()
	var/mob/threat = brain.primary_threat
	if(!owner || !threat)
		return null
	if(!is_off_cooldown(brain, source))
		return null
	// Adjacency, off-balance lock, and target-validity are enforced centrally in pick_and_run.
	// Above plain melee (40) so it occasionally takes over; below INTERRUPT reactions.
	return DQAI_RESULT(70, threat)

/datum/ai_behavior/telegraphed_strike/start(datum/ai_brain/brain, atom/target, atom/source)
	. = ..()
	if(. == DQ_BEHAVIOR_FAILED)
		return
	var/mob/living/simple_mob/SM = brain.get_owner()
	if(!istype(SM))
		return DQ_BEHAVIOR_FAILED
	SM.face_atom(target)
	var/windup = SM.telegraph_windup
	// Mark the target's own tile (a guessed "front" tile misfires when the target is diagonal,
	// showing the warning on the wrong square). Dodge by stepping off it during the windup.
	var/turf/struck = get_turf(target)
	if(struck)
		dq_telegraph(struck, windup, DQ_TELEGRAPH_PARRY) // a heavy — parry or block it

	SM.do_windup_animation(target, windup)
	SM.visible_message(span_danger("\The [SM] rears back for a heavy blow!"), blind_message = span_warning("You hear something heavy wind up to strike."))
	addtimer(CALLBACK(src, PROC_REF(execute_strike), brain, struck), windup)
	return DQ_BEHAVIOR_CONTINUE

/datum/ai_behavior/telegraphed_strike/proc/execute_strike(datum/ai_brain/brain, turf/struck)
	if(QDELETED(brain))
		return
	// The windup timer can't be cancelled per-mob (the behavior is a shared
	// flyweight), so a flinched / interrupted / dead mob still gets here. If the
	// brain is no longer committed to THIS strike, the wind-up was cancelled —
	// don't land it.
	if(brain.active_behavior_type != type)
		return
	// Resolve the hit inside a guard so a thrown error in the damage path can NEVER skip the
	// stop_active() below — a behavior that fails to clear brain.busy would freeze the mob forever
	// (SSai skips busy brains) and leak the brain.
	var/mob/living/simple_mob/SM = brain.holder
	if(istype(SM) && !QDELETED(SM))
		try
			resolve_heavy(SM, struck)
		catch(var/exception/e)
			SM.heavy_strike_mult = 0 // never leak the heavy multiplier into later normal attacks
			logger.Log(LOG_CATEGORY_DEBUG, "telegraphed_strike resolve error: [e]")
	brain.stop_active(DQ_BEHAVIOR_STOP_COMPLETED) // ALWAYS clears busy

/datum/ai_behavior/telegraphed_strike/proc/resolve_heavy(mob/living/simple_mob/SM, turf/struck)
	var/landed = FALSE
	if(struck && SM.Adjacent(struck))
		var/datum/ai_brain/brain = SM.ai_brain
		for(var/mob/living/victim in struck)
			if(victim == SM)
				continue
			// Only land on something the mob is actually hostile to. A dense swarm packs
			// allies onto the tile between the mob and the player; without this guard the
			// heavy clobbers packmates, which reads as constant infighting (is_friendly_fire
			// blocks the grudge but not the damage). Players resolve to HOSTILE and still eat
			// it; ally / coexisting-fauna / neutral bystanders are spared. No brain → no
			// disposition data, so fall back to hitting whatever's there.
			if(brain && brain.disposition_to(victim) > DQ_DISPOSITION_HOSTILE)
				continue
			SM.heavy_strike_mult = damage_mult // read + cleared inside do_attack
			if(SM.do_attack(victim, struck)) // routes through check_shields → parry / soft-block / dodge
				landed = TRUE
			SM.heavy_strike_mult = 0

	// Recovery opening either way (a whiff is longer), bounded so slow mobs don't lock up for ages.
	var/recovery = clamp(landed ? SM.get_attack_speed() : (SM.get_attack_speed() * 2), 3, 15)
	SM.setClickCooldown(recovery)
	SM.melee_locked_until = max(SM.melee_locked_until, world.time + recovery)
	if(!landed)
		SM.visible_message(span_warning("\The [SM] overswings and staggers, off-balance!"))

/// Per-mob heavy cooldown (heavy_cooldown) instead of a flat datum cooldown.
/datum/ai_behavior/telegraphed_strike/stop(datum/ai_brain/brain, atom/target, atom/source, reason)
	if(blocks_reselection)
		brain.busy = FALSE
	var/mob/living/simple_mob/SM = brain?.holder
	// A flinched (INTERRUPTED) heavy is spent too — without a cooldown the mob would
	// re-wind instantly and could race its own stale windup timer.
	if((reason == DQ_BEHAVIOR_STOP_COMPLETED || reason == DQ_BEHAVIOR_STOP_INTERRUPTED) && istype(SM))
		brain.set_cooldown(type, source, SM.heavy_cooldown)
	else if(reason == DQ_BEHAVIOR_STOP_FAILED)
		brain.set_cooldown(type, source, DQ_BEHAVIOR_FAIL_COOLDOWN)
	return

// Flinch-cancellable heavy for agile elites: when the target winds up a swing of
// their own mid-telegraph, the mob yanks the blow back and can dodge/brace instead
// of eating it. Trash mobs use the committed base type and stay punishable. Add via
// get_ai_behaviors() on mobs that should read AND react.
/datum/ai_behavior/telegraphed_strike/flinch
	interruptible_by = list(COMSIG_DQAI_INCOMING_ATTACK)

// --- Sidestep dodge ---------------------------------------------------------
// Reacts to the player's telegraphed swing (COMSIG_DQAI_INCOMING_ATTACK, sent from begin_melee_swing
// to mobs in the swing tiles). Rolls once on the signal; if it commits, the mob steps out of the
// line before the swing resolves. Only slow swings are dodgeable (the AI tick is ~250ms), which keeps
// fast light pokes reliable and heavy telegraphs evadeable.

/datum/ai_behavior/sidestep_dodge
	name = "sidestep dodge"
	desc = "Step out of the way of a telegraphed incoming attack."
	priority_class = DQ_BEHAVIOR_PRIORITY_INTERRUPT
	target_kind = DQ_TARGET_MOB
	eval_triggers = list(COMSIG_DQAI_INCOMING_ATTACK)
	cooldown = 2 SECONDS

/datum/ai_behavior/sidestep_dodge/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob) && !owner.anchored

/datum/ai_behavior/sidestep_dodge/on_signal(datum/ai_brain/brain, sig_type, mob/attacker, windup_time)
	var/mob/living/simple_mob/SM = brain?.holder
	if(!istype(SM) || SM.anchored)
		return
	if(!is_off_cooldown(brain, null))
		return
	// Once the prey has strung together a combo on us, the next telegraphed swing is
	// read and dodged for certain — a mob that's been hit repeatedly stops eating them.
	var/comboed = brain.combo_hits >= DQ_COMBO_DODGE_THRESHOLD
	if(comboed)
		brain.combo_hits = 0 // spend the read
	else if(!prob(SM.dodge_chance))
		return
	// Only commit if there's actually somewhere to step. Otherwise leave the flag
	// clear so brace_guard can take over for a cornered mob (it checks this).
	if(!dq_find_sidestep_tile(SM, attacker || brain.primary_threat))
		return
	SM.incoming_attack_at = world.time + max(windup_time, 1) // commit: dodge before the swing lands
	// Committing to the dodge yanks back an in-progress flinch-cancellable heavy so
	// the dodge can run; a committed heavy is left alone (the mob eats the swing).
	brain.interrupt_if_opted_in(sig_type)
	brain.invalidate_selection()

/datum/ai_behavior/sidestep_dodge/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/SM = brain.get_owner()
	if(!istype(SM) || world.time >= SM.incoming_attack_at)
		return null
	if(!brain.primary_threat)
		return null
	if(!dodge_tile(SM, brain.primary_threat))
		return null
	return DQAI_RESULT(90, brain.primary_threat)

/datum/ai_behavior/sidestep_dodge/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/SM = brain.get_owner()
	if(!istype(SM))
		return DQ_BEHAVIOR_FAILED
	var/turf/escape = dodge_tile(SM, target)
	if(escape)
		step(SM, get_dir(SM, escape))
		SM.visible_message(span_warning("\The [SM] sidesteps!"))
	SM.incoming_attack_at = 0 // consumed
	return DQ_BEHAVIOR_DONE

/datum/ai_behavior/sidestep_dodge/proc/dodge_tile(mob/living/owner, atom/threat)
	return dq_find_sidestep_tile(owner, threat)

/// A free tile to sidestep into: prefer perpendicular to the threat, then directly
/// away. Shared by sidestep_dodge (where to step) and brace_guard (whether a dodge
/// is even possible, so a cornered mob braces instead).
/proc/dq_find_sidestep_tile(mob/living/owner, atom/threat)
	if(!owner || !threat)
		return null
	var/threat_dir = get_dir(owner, threat)
	for(var/try_dir in list(turn(threat_dir, 90), turn(threat_dir, -90), reverse_direction(threat_dir)))
		var/turf/T = get_step(owner, try_dir)
		if(T && !T.density && !(locate(/mob/living) in T))
			return T
	return null

// --- Back off ---------------------------------------------------------------
// On taking a hit, sometimes give ground a tile and circle instead of facetanking — gives the fight
// a pulse and lets the player breathe (and re-approach happens via approach_threat).

/datum/ai_behavior/back_off
	name = "back off"
	desc = "Give ground after taking a hit rather than trading blindly."
	priority_class = DQ_BEHAVIOR_PRIORITY_INTERRUPT
	target_kind = DQ_TARGET_MOB
	eval_triggers = list(COMSIG_DQAI_DAMAGE_TAKEN)
	cooldown = 3 SECONDS

/datum/ai_behavior/back_off/applicable_to(mob/living/owner)
	if(!istype(owner, /mob/living/simple_mob) || owner.anchored)
		return FALSE
	var/mob/living/simple_mob/SM = owner
	if(SM.quarry_fauna)
		return FALSE // swarm fauna commit to the attack rather than giving ground (they still telegraph heavies)
	return TRUE

/datum/ai_behavior/back_off/evaluate(datum/ai_brain/brain, atom/source)
	if(DQ_AI_RETREAT_DISABLED) // mobs hold their ground instead of giving ground after a hit
		return null
	var/mob/living/owner = brain.get_owner()
	var/mob/threat = brain.primary_threat
	if(!owner || !threat || !owner.Adjacent(threat))
		return null
	if(!is_off_cooldown(brain, source))
		return null
	if(!prob(40)) // not every hit — an occasional reset
		return null
	return DQAI_RESULT(60, threat)

/datum/ai_behavior/back_off/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(!owner)
		return DQ_BEHAVIOR_FAILED
	var/turf/away = get_step_away(owner, target)
	if(away && !away.density && !(locate(/mob/living) in away))
		if(dq_ai_step_to(owner, away)) // throttled — give ground at the AI move pace, not a sprint
			owner.visible_message(span_notice("\The [owner] gives ground, circling."))
	return DQ_BEHAVIOR_DONE

// --- Brace guard ------------------------------------------------------------
// Opt-in defense for tanky mobs that hold their ground instead of sidestepping. On a telegraphed
// incoming attack it braces to halve the next hit (the damage path reads incoming_block_at). It's
// the read the player answers with a shove (guard break via resolve_shove) or a feint. Not in the
// default kit — add via get_ai_behaviors() on mobs that should tank. The flag is set in on_signal;
// there's no selectable action, so evaluate() stays null.

/datum/ai_behavior/brace_guard
	name = "brace guard"
	desc = "Brace against a telegraphed attack to soften it."
	priority_class = DQ_BEHAVIOR_PRIORITY_INTERRUPT
	target_kind = DQ_TARGET_MOB
	eval_triggers = list(COMSIG_DQAI_INCOMING_ATTACK)
	cooldown = 2 SECONDS

/datum/ai_behavior/brace_guard/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob)

/datum/ai_behavior/brace_guard/on_signal(datum/ai_brain/brain, sig_type, mob/attacker, windup_time)
	var/mob/living/simple_mob/SM = brain?.holder
	if(!istype(SM))
		return
	if(!is_off_cooldown(brain, null))
		return
	if(SM.incoming_attack_at > world.time) // already committed to a sidestep this swing
		return
	// If this mob can sidestep and has room, let the dodge handle it — brace is the
	// fallback so a cornered (or non-agile) mob still reacts readably instead of
	// facetanking. A dedicated tank with no sidestep in its kit always braces.
	if((/datum/ai_behavior/sidestep_dodge in brain.effective_behaviors) && !SM.anchored && dq_find_sidestep_tile(SM, attacker || brain.primary_threat))
		return
	SM.incoming_block_at = world.time + max(windup_time, 1) // brace window until the swing lands
	SM.visible_message(span_warning("\The [SM] braces!"))
	brain.interrupt_if_opted_in(sig_type) // a committed brace also yanks back a flinch heavy
	brain.set_cooldown(type, null, cooldown)
