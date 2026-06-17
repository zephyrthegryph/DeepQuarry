// Predation — a vore-capable predator's staged grapple→devour sequence.
//
// Instead of a random "pounce and instantly swallow" on a melee hit, a predator that
// wants to eat edible prey commits to a readable, escapable sequence that mirrors the
// player grab→vore flow:
//
//   TACKLE    — a telegraphed lunge. Land it and the prey is knocked down; the prey
//               can dodge or block it like any heavy (then the predator is off-balance).
//   PIN       — the predator holds the prey down. The prey STRUGGLES (Resist) to wrench
//               free; the grip is weakest here, so this is the real escape window.
//   REINFORCE — the predator sinks in a reinforced grip. The grip roughly doubles, so
//               struggling out now is much harder.
//   DEVOUR    — committed: the prey is swallowed into the predator's selected belly.
//
// At any held stage, beating the predator off with a quick combo (DQ_COMBO_GRAPPLE_BREAK
// hits in a row) makes it bail and stagger, freeing the prey. Predation only fires when
// the predator both CAN and WANTS to eat the target (will_eat — honours vore prefs), so
// non-consenting players just get the normal read-and-react melee kit.
//
// Because a blocks_reselection behavior's tick() never runs (the brain skips a busy
// brain), the held stages are driven by the grapple datum's own pulse timer, not the AI
// tick. Struggle and combo-break are event-driven (Resist input / damage), so they react
// instantly even while the predator is committed.

/mob/living
	/// The predator currently committed to grappling this mob — set when a predator commits
	/// its tackle, cleared when that grapple ends or whiffs. Stops two predators pinning or
	/// swallowing the same prey at the same time (one grab per victim).
	var/mob/living/dq_grapple_claimant

/// TRUE when `owner` shouldn't keep attacking `threat`: another predator already has it grabbed
/// to eat (claimed), or it's already been swallowed (no longer standing on a turf). Used to gate
/// the melee/heavy/maul/predation behaviors so the pack doesn't wail on a pinned or devoured victim.
/proc/dq_prey_locked_by_other(mob/living/owner, atom/threat)
	if(!isliving(threat))
		return FALSE
	var/mob/living/L = threat
	if(L.dq_grapple_claimant && L.dq_grapple_claimant != owner && !QDELETED(L.dq_grapple_claimant))
		return TRUE
	if(istype(L.loc, /obj/belly)) // already swallowed — inside a belly, nothing to hit
		return TRUE
	return FALSE

// ---------------------------------------------------------------------------
// /datum/dq_predation — the live grapple. Drives a REAL /obj/item/grab as the hold,
// so the prey escapes through the same Resist → handle_resist path as any grab (no
// bespoke struggle counter), and the grip reads on the HUD/visuals like a player grab.
// The datum is the coordinator: it owns the stage timing + pulse (NPC-held grabs don't
// self-process), upgrades the grab as it escalates, and ends the owning behavior.
// Referenced from the predator's brain (`grapple`); cleared + qdel'd on devour/escape/abort.
// ---------------------------------------------------------------------------
/datum/dq_predation
	var/mob/living/simple_mob/predator
	var/mob/living/prey
	/// The actual hold. The player breaks free by Resisting it (handle_resist), same as
	/// any grab — escape is hardest once it's upgraded to a neck-lock at REINFORCE.
	var/obj/item/grab/grab
	var/stage = DQ_PREDATION_PIN
	/// world.time the current held stage escalates.
	var/stage_until = 0
	/// Repeating pulse that holds the prey down + advances stages.
	var/pulse_timer = null

/datum/dq_predation/New(mob/living/simple_mob/pred, mob/living/quarry)
	predator = pred
	prey = quarry
	pred.ai_brain?.grapple = src

/datum/dq_predation/Destroy()
	if(pulse_timer)
		deltimer(pulse_timer)
		pulse_timer = null
	if(grab && !QDELETED(grab)) // free the prey if we're torn down mid-hold
		qdel(grab)
	grab = null
	// Release the prey's grapple claim (defensive — the behavior's stop() normally does it).
	if(prey && prey.dq_grapple_claimant == predator)
		prey.dq_grapple_claimant = null
	// Sever the brain backref. Never qdel the mobs — we don't own them.
	if(predator?.ai_brain?.grapple == src)
		predator.ai_brain.grapple = null
	predator = null
	prey = null
	return ..()

/// Begin the held phase: seize the prey with a real aggressive grab + pin, then pulse.
/// Returns FALSE (and ends) if the grab couldn't be established.
/datum/dq_predation/proc/begin()
	grab = predator.dq_grab(prey, GRAB_AGGRESSIVE)
	if(QDELETED(grab))
		finish(DQ_BEHAVIOR_STOP_FAILED)
		return
	grab.apply_pinning(prey, predator) // force_down + lying, the predator on top
	stage = DQ_PREDATION_PIN
	stage_until = world.time + DQ_PREDATION_PIN_HOLD
	dqai_pdbg(predator, "GRAPPLE", "BEGIN — pin established (grab=[grab.state]), hold [DQ_PREDATION_PIN_HOLD/10]s", prey)
	prey.visible_message(span_danger("\The [predator] slams \the [prey] to the ground and pins them!"))
	playsound(prey, 'sound/weapons/thudswoosh.ogg', 50, 1, -1)
	pulse()

/// TRUE while both ends are alive, adjacent, and able to continue.
/datum/dq_predation/proc/is_valid()
	if(QDELETED(predator) || QDELETED(prey))
		return FALSE
	if(predator.stat >= DEAD || prey.stat >= DEAD)
		return FALSE
	if(!predator.Adjacent(prey))
		return FALSE
	return TRUE

/// One pulse: keep the prey pinned, drive the (non-self-processing) grab's positioning,
/// check for an escape/abort, advance on the timer, then reschedule. The grapple's
/// heartbeat — the AI tick is busy-blocked while the behavior holds reselection.
/datum/dq_predation/proc/pulse()
	pulse_timer = null
	if(QDELETED(src))
		return
	if(!is_valid())
		finish(DQ_BEHAVIOR_STOP_FAILED)
		return
	// The prey Resisted free — the grab broke itself out of grabbed_by. Let them go.
	if(QDELETED(grab) || !(grab in prey.grabbed_by))
		escaped()
		return
	// Beaten off: a quick combo from the prey while we're committed makes us bail + stagger.
	if(predator.ai_brain?.combo_hits >= DQ_COMBO_GRAPPLE_BREAK)
		dqai_pdbg(predator, "GRAPPLE", "BEATEN OFF — prey landed [predator.ai_brain.combo_hits] combo hits, bailing", prey)
		break_free("\The [predator] is beaten off \the [prey] and reels back!")
		return
	prey.Weaken(2)            // keep them down between pulses
	predator.face_atom(prey)
	grab.adjust_position()    // NPC-held grabs don't self-process; drive the hold visuals
	if(world.time >= stage_until)
		advance()
		if(QDELETED(src))
			return
	pulse_timer = addtimer(CALLBACK(src, PROC_REF(pulse)), DQ_PREDATION_PULSE, TIMER_STOPPABLE)

/// Stage timer elapsed — tighten the grip (upgrade the grab), then commit.
/datum/dq_predation/proc/advance()
	switch(stage)
		if(DQ_PREDATION_PIN)
			stage = DQ_PREDATION_REINFORCE
			if(grab && !QDELETED(grab))
				grab.state = GRAB_NECK // a neck-lock: far harder to Resist out of (see handle_resist)
				grab.adjust_position()
			stage_until = world.time + DQ_PREDATION_REINFORCE_HOLD
			dqai_pdbg(predator, "GRAPPLE", "REINFORCE — neck-lock sunk in, hold [DQ_PREDATION_REINFORCE_HOLD/10]s before devour", prey)
			predator.visible_message(span_danger("\The [predator] sinks in a reinforced grip — \the [prey] can barely move!"))
			playsound(prey, 'sound/vore/sunesound/prey/struggle_03.ogg', 45, 1, -1)
		if(DQ_PREDATION_REINFORCE)
			devour()

/// The prey Resisted out of the grab. Free + a brief stagger on the predator; end.
/datum/dq_predation/proc/escaped()
	dqai_pdbg(predator, "GRAPPLE", "ESCAPED — prey resisted out of the grab at stage [stage]", prey)
	grab = null // already broken out of grabbed_by
	break_free(null)

/// Stagger the predator (an opening to punish) and end the sequence.
/datum/dq_predation/proc/break_free(message)
	if(message && !QDELETED(predator))
		predator.visible_message(span_warning("[message]"))
	if(!QDELETED(predator))
		// Off-balance recovery: the prey gets a guaranteed window to act.
		var/recovery = clamp(predator.get_attack_speed() * 2, 5, 20)
		predator.setClickCooldown(recovery)
		predator.melee_locked_until = max(predator.melee_locked_until, world.time + recovery)
	finish(DQ_BEHAVIOR_STOP_INTERRUPTED)

/// Commit the swallow via the established simple_mob vore path, then end.
/datum/dq_predation/proc/devour()
	var/mob/living/simple_mob/SM = predator
	var/mob/living/quarry = prey
	if(QDELETED(SM) || QDELETED(quarry) || !SM.Adjacent(quarry) || !SM.will_eat(quarry))
		finish(DQ_BEHAVIOR_STOP_FAILED)
		return
	stage = DQ_PREDATION_DEVOUR
	dqai_pdbg(SM, "GRAPPLE", "DEVOUR — committing the swallow after the full grapple sequence", quarry)
	SM.visible_message(span_danger("\The [SM] gulps \the [quarry] down!"))
	// Release the grab so the prey's belly resist (not our grip) governs them once inside,
	// then swallow on LIVE refs BEFORE tearing the coordinator down (no use-after-qdel).
	if(grab && !QDELETED(grab))
		qdel(grab)
	grab = null
	// EatTarget blocks for the swallow (do_after, ~swallowTime) and returns the prey on success, a
	// falsy value if it failed (the prey wriggled out). The grab is already gone, so a failed swallow
	// just means they got away — end as FAILED rather than mis-reporting a completed devour (which
	// would burn the long success cooldown as if we'd actually eaten them).
	var/swallowed = SM.EatTarget(quarry) // animal_nom → feed_grabbed_to_self → perform_the_nom, the player-fed path
	finish(swallowed ? DQ_BEHAVIOR_STOP_COMPLETED : DQ_BEHAVIOR_STOP_FAILED)

/// Tear down: set the predator's cooldown, end the owning behavior, and qdel.
/datum/dq_predation/proc/finish(reason)
	var/mob/living/simple_mob/SM = predator
	var/datum/ai_brain/brain = SM?.ai_brain
	if(brain)
		brain.set_cooldown(/datum/ai_behavior/predation, null, DQ_PREDATION_COOLDOWN)
	qdel(src) // nulls brain.grapple, so stop_active's safety qdel below no-ops
	brain?.stop_active(reason)

// ---------------------------------------------------------------------------
// /datum/ai_behavior/predation — the entry: scores the grab and runs the telegraphed
// tackle. Once the prey is pinned, the grapple datum's pulse owns the sequence; this
// behavior just stays committed (blocks_reselection) until the grapple ends.
// ---------------------------------------------------------------------------
/datum/ai_behavior/predation
	name = "predation"
	desc = "Tackle, pin, and devour edible prey."
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	min_range = 0
	max_range = 1
	blocks_reselection = TRUE
	requires_adjacent = TRUE       // central gate: must be in reach to grab
	blocked_by_melee_lock = TRUE   // central gate: can't initiate a grab while off-balance

/datum/ai_behavior/predation/applicable_to(mob/living/owner)
	if(!istype(owner, /mob/living/simple_mob))
		return FALSE
	var/mob/living/simple_mob/SM = owner
	return SM.vore_active

/datum/ai_behavior/predation/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/SM = brain.get_owner()
	if(!istype(SM))
		return null
	var/mob/living/threat = brain.primary_threat
	if(!isliving(threat))
		return null
	if(!is_off_cooldown(brain, source))
		return null
	// Adjacency, off-balance lock, and target-validity (incl. the one-predator-per-prey claim,
	// caught even within the same tick) are enforced centrally in pick_and_run.
	// Only when we both CAN and WANT to eat them — honours the target's vore prefs.
	if(!SM.will_eat(threat))
		return null
	// Predation is a finisher, not an opener: commit the grab once the prey is genuinely worn
	// down. A fresh, standing fighter gets the read-and-react melee kit instead.
	if(!dq_prey_worn_down(threat))
		return null
	// Above telegraphed_strike (70): a predator that can grab prefers to commit to one,
	// but it's gated behind a long cooldown so the fight breathes between attempts.
	return DQAI_RESULT(85, threat)

// --- Ambush-eater pounce -----------------------------------------------------
// A predation variant for dedicated ambush eaters (scrubble, fluffball, …): it grabs on
// CONTACT rather than waiting for the prey to be worn down. Still the full escapable grapple
// (telegraphed tackle → pin → reinforce → devour, breakable via Resist / a combo), just not
// gated on exhaustion — that's these mobs' whole identity. Used in place of the legacy instant
// PounceTarget+EatTarget so the swallow is readable and counterable.
/datum/ai_behavior/predation/pounce

/datum/ai_behavior/predation/pounce/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/SM = brain.get_owner()
	if(!istype(SM))
		return null
	var/mob/living/threat = brain.primary_threat
	if(!isliving(threat))
		return null
	if(!is_off_cooldown(brain, source))
		return null
	// Adjacency, off-balance lock and target-validity (the one-grab-per-prey claim) are central.
	if(!SM.will_eat(threat))
		return null
	return DQAI_RESULT(85, threat)

/// TRUE when `prey` is too exhausted to fight off a grab — low on stamina or freshly
/// collapsed. NPCs never tire (they hold at max stamina), so this only ever trips on a
/// worn-down player.
/proc/dq_prey_exhausted(mob/living/prey)
	if(!isliving(prey))
		return FALSE
	if(prey.stamina_collapsed)
		return TRUE
	return prey.max_stamina > 0 && prey.stamina <= prey.max_stamina * DQ_PREDATION_STAMINA_FRAC

/// TRUE when `prey` is worn down enough to commit the grab-and-devour: gassed (exhausted),
/// staggered wide open, or knocked out. The shared "now go for the throat" trigger — predation's
/// own gate AND a harasser's "stop biting, it's pin time" check read this, so both agree on the
/// moment. A mere momentary knockdown (lying but conscious, full stamina) is deliberately NOT
/// enough: a single stun shouldn't instantly pin a fresh fighter.
/proc/dq_prey_worn_down(mob/living/prey)
	if(!isliving(prey))
		return FALSE
	return dq_prey_exhausted(prey) || prey.is_stagger_broken() || prey.stat != CONSCIOUS

/datum/ai_behavior/predation/start(datum/ai_brain/brain, atom/target, atom/source)
	. = ..()
	if(. == DQ_BEHAVIOR_FAILED)
		return
	var/mob/living/simple_mob/SM = brain.get_owner()
	var/mob/living/prey = target
	if(!istype(SM) || !isliving(prey))
		return DQ_BEHAVIOR_FAILED
	// Already committed to a tackle or holding a grapple → don't open a second. Guards re-entry
	// (a predation that was stopped and immediately re-selected mid-windup would otherwise stack
	// a second telegraph + grab on the same prey).
	if(brain.grapple || brain.tackle_timer)
		return DQ_BEHAVIOR_FAILED
	// Claim the prey for the whole tackle→grapple so no second predator pins/eats them too.
	prey.dq_grapple_claimant = SM
	// Telegraphed tackle — readable + dodgeable/blockable exactly like a heavy. Mark the prey's
	// own tile (not a guessed "front" tile, which misfires when the prey is diagonal) so the
	// warning shows where the grab is actually going; step off it during the windup to dodge.
	SM.face_atom(prey)
	var/windup = SM.telegraph_windup
	var/turf/struck = get_turf(prey)
	if(struck)
		dq_telegraph(struck, windup, DQ_TELEGRAPH_GRAB) // a tackle — can't be parried, dodge it
	SM.do_windup_animation(prey, windup)
	dqai_pdbg(SM, "GRAPPLE", "TACKLE telegraph ([windup/10]s) — prey exhausted=[dq_prey_exhausted(prey)] staggered=[prey.is_stagger_broken()] lying=[prey.lying] stat=[prey.stat]", prey)
	SM.visible_message(
		span_danger("\The [SM] lunges to tackle \the [prey]!"),
		blind_message = span_warning("You hear something lunge!"),
	)
	// Stored on the brain (stoppable) so stop() can cancel it — a bare addtimer would survive an
	// interruption and still spawn a grab.
	brain.tackle_timer = addtimer(CALLBACK(src, PROC_REF(resolve_tackle), brain, prey, struck), windup, TIMER_STOPPABLE)
	return DQ_BEHAVIOR_CONTINUE

/// The lunge lands (or whiffs). On a hit, knock the prey down and open the grapple.
/datum/ai_behavior/predation/proc/resolve_tackle(datum/ai_brain/brain, mob/living/prey, turf/struck)
	if(QDELETED(brain))
		return
	brain.tackle_timer = null // this is that timer firing — it's spent
	if(brain.active_behavior_type != type || brain.grapple)
		return // flinched / interrupted mid-windup, or a grapple is already live — never double up
	var/mob/living/simple_mob/SM = brain.holder
	if(!istype(SM) || QDELETED(SM))
		return
	// Whiff only if the prey broke away (no longer adjacent) or stopped being edible — the
	// telegraph is the window to get out of reach. We DON'T require the prey to be on the
	// exact struck tile: a diagonally-adjacent prey would otherwise whiff every time.
	if(QDELETED(prey) || prey.stat >= DEAD || !SM.Adjacent(prey) || !SM.will_eat(prey))
		var/recovery = clamp(SM.get_attack_speed() * 2, 5, 20)
		SM.setClickCooldown(recovery)
		SM.melee_locked_until = max(SM.melee_locked_until, world.time + recovery)
		dqai_pdbg(SM, "GRAPPLE", "TACKLE whiffed — prey out of reach / no longer edible, off-balance", prey)
		SM.visible_message(span_warning("\The [SM] overshoots its tackle and stumbles!"))
		brain.set_cooldown(type, null, DQ_PREDATION_COOLDOWN)
		brain.stop_active(DQ_BEHAVIOR_STOP_COMPLETED)
		return
	// Takedown. Establish the grapple, which takes over from here on its own pulse.
	dqai_pdbg(SM, "GRAPPLE", "TACKLE landed — opening grapple", prey)
	prey.Weaken(3)
	brain.combo_hits = 0 // fresh grapple; start the beat-off counter clean
	var/datum/dq_predation/grip = new(SM, prey)
	grip.begin()

/datum/ai_behavior/predation/stop(datum/ai_brain/brain, atom/target, atom/source, reason)
	// Cancel a still-pending tackle windup so its resolve never fires after we've stopped — the
	// orphan-timer guard that prevents the double-pin when predation is re-selected mid-windup.
	if(brain?.tackle_timer)
		dqai_pdbg(brain.holder, "GRAPPLE", "predation stopped mid-tackle (reason=[reason]) — cancelling the pending lunge so it can't open a stray grab", target)
		deltimer(brain.tackle_timer)
		brain.tackle_timer = null
	// Safety net: if the behavior is torn down by anything other than the grapple's own
	// finish() (e.g. the predator dies mid-tackle), free a dangling grapple too.
	if(brain?.grapple)
		qdel(brain.grapple)
	// Release our claim on the prey so another predator can engage once we're done.
	if(isliving(target))
		var/mob/living/prey = target
		if(prey.dq_grapple_claimant == brain?.holder)
			prey.dq_grapple_claimant = null
	return ..()
