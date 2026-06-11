// Healbelly port — restores the bespoke "heal allies by eating them" AI that
// lived on /datum/ai_holder/simple_mob/healbelly and its /retaliate/dragon
// subtype (deleted from subtypes/vore/bigdragon.dm).
//
// In the legacy engine the healbelly holder overrode can_attack() so that
// allies became valid "targets," then melee_attack() swapped a_intent to HELP
// and PounceTarget()'d the ally into a healing belly (injecting a few medical
// chems on humans). The mob would also bark "Hey [name], hold still!" at hurt
// patients.
//
// In the modern brain, ALLY/FRIENDLY mobs land in the world model's
// visible_friendlies bucket (disposition_to() >= FRIENDLY), NOT in
// visible_hostiles. So the heal behavior reads visible_friendlies, picks the
// most-wounded patient, approaches, and on adjacency runs the HELP-path heal
// pounce. The bespoke confirmPatient / heal-pounce proc bodies move onto the
// mob (dq_confirm_patient / dq_heal_pounce) so the behavior is a thin adapter.
//
// The bigdragon/friendly variant additionally keeps the legacy "warn three
// times, then enrage" retaliation toward allies who hit it — ported as a
// dedicated behavior since the modern brain has no react_to_attack override
// chain. The hostile dragon's own fire/charge/tail attacks are covered by
// ports/bigdragon.dm; this file only adds the healing + friendly-retaliation
// layer to the docile variants (leopardmander + bigdragon/friendly).

// ---------------------------------------------------------------------------
// Shared mob-side helpers (moved off the deleted ai_holder).
// ---------------------------------------------------------------------------

/// True if P is a valid heal patient: edible, alive, hurt below 95% HP. Also
/// barks an occasional "hold still" line, rate-limited via dq_healbelly_last_speak.
/mob/living/simple_mob/proc/dq_confirm_patient(mob/living/P)
	if(!istype(P))
		return FALSE
	if(!will_eat(P))
		return FALSE
	if(issilicon(P))
		return FALSE
	// Synths/animals only if player-controlled; carbons always.
	if(!iscarbon(P) && !P.client)
		return FALSE
	if(P.stat == DEAD)
		return FALSE
	if(P.suiciding)
		return FALSE
	if(P.health > (P.getMaxHealth() * 0.95))
		return FALSE
	// Vocal nag, throttled to one line per 30s.
	if(dq_healbelly_vocal && (dq_healbelly_last_speak + 30 SECONDS < world.time))
		var/list/message_options = list(
			"Hey, [P.name]! You are injured, hold still.",
			"[P.name]! Come here, let me help.",
			"[P.name], you need help.",
		)
		say(pick(message_options))
		dq_healbelly_last_speak = world.time
	return TRUE

/// Performs the HELP-intent heal pounce: swallow the patient into a heal belly
/// and top them off with a few stabilising chems so they don't die mid-swallow.
/// Mirrors the legacy healbelly/melee_attack on I_HELP.
/mob/living/simple_mob/proc/dq_heal_pounce(mob/living/L)
	if(!istype(L) || !will_eat(L))
		return FALSE
	var/old_intent = a_intent
	a_intent = I_HELP
	PounceTarget(L)
	if(ishuman(L) && L.reagents)
		var/list/to_inject = list(
			REAGENT_ID_MYELAMINE,
			REAGENT_ID_OSTEODAXON,
			REAGENT_ID_SPACEACILLIN,
			REAGENT_ID_PERIDAXON,
			REAGENT_ID_IRON,
			REAGENT_ID_HYRONALIN,
		)
		for(var/RG in to_inject)
			if(!L.reagents.has_reagent(RG))
				L.reagents.add_reagent(RG, 10)
	L.extinguish_mob()
	a_intent = old_intent
	return TRUE

/mob/living/simple_mob
	/// Whether this healbelly mob nags hurt patients with "hold still" lines.
	var/dq_healbelly_vocal = TRUE
	/// world.time of the last patient nag, for the 30s throttle.
	var/dq_healbelly_last_speak = 0

// ---------------------------------------------------------------------------
// Heal-belly behavior — find a wounded ally, approach, swallow to heal.
// ---------------------------------------------------------------------------

/datum/ai_behavior/healbelly_heal_ally
	name = "heal ally"
	desc = "Swallow a wounded ally into a healing belly to mend them."
	// HELP-path, friendly behavior. Tagged HELP for player-castable gating.
	valid_intents = DQ_INTENT_HELP_FLAG
	// IDLE so any genuine combat threat preempts it, but it still runs whenever
	// the mob is otherwise unoccupied (no primary_threat required).
	priority_class = DQ_BEHAVIOR_PRIORITY_IDLE
	target_kind = DQ_TARGET_MOB
	no_threat_required = TRUE
	min_range = 0
	max_range = INFINITY

/datum/ai_behavior/healbelly_heal_ally/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob)

/datum/ai_behavior/healbelly_heal_ally/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/SM = brain.get_owner()
	if(!istype(SM) || SM.client)
		return null
	if(!brain.model)
		return null
	// Don't go patient-hunting while we have something to fight.
	if(brain.primary_threat)
		return null
	// Pick the most-wounded valid ally we can see.
	var/mob/living/best_patient = null
	var/best_frac = INFINITY
	for(var/mob/living/ally as anything in brain.model.visible_friendlies)
		if(!SM.dq_confirm_patient(ally))
			continue
		var/frac = ally.getMaxHealth() ? (ally.health / ally.getMaxHealth()) : 1
		if(frac < best_frac)
			best_frac = frac
			best_patient = ally
	if(!best_patient)
		return null
	// Outscore idle wander/speak but stay below combat priorities.
	return DQAI_RESULT(20, best_patient)

/datum/ai_behavior/healbelly_heal_ally/start(datum/ai_brain/brain, atom/target, atom/source)
	. = ..()
	if(. == DQ_BEHAVIOR_FAILED)
		return
	return DQ_BEHAVIOR_CONTINUE

/datum/ai_behavior/healbelly_heal_ally/tick(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/SM = brain.get_owner()
	var/mob/living/patient = target
	if(!istype(SM) || !istype(patient) || QDELETED(patient))
		return DQ_BEHAVIOR_FAILED
	// Patient healed up or wandered out of validity — done.
	if(!SM.dq_confirm_patient(patient))
		return DQ_BEHAVIOR_DONE
	if(!SM.Adjacent(patient))
		if(!brain.smart_step_toward(patient))
			step_to(SM, patient)
		return DQ_BEHAVIOR_CONTINUE
	// Adjacent: ensure the right (healing) belly is selected, then swallow.
	dq_healbelly_select_heal_gut(SM)
	SM.dq_heal_pounce(patient)
	return DQ_BEHAVIOR_DONE

/datum/ai_behavior/healbelly_heal_ally/get_player_verb_info()
	var/static/list/L = list(
		"name" = "Heal Swallow",
		"desc" = "Swallow a wounded ally into a healing belly.",
		"category" = "Friendly",
		"auto_target" = FALSE,
	)
	return L

/// Point a healbelly mob's vore_selected at its dedicated heal gut, if it has
/// one. Bigdragon tracks it as `gut2`; other healbelly mobs (leopardmander)
/// already default their stomach to DM_HEAL so this is a no-op for them.
/proc/dq_healbelly_select_heal_gut(mob/living/simple_mob/SM)
	if(istype(SM, /mob/living/simple_mob/vore/bigdragon))
		var/mob/living/simple_mob/vore/bigdragon/BG = SM
		if(BG.gut2)
			BG.vore_selected = BG.gut2

// ---------------------------------------------------------------------------
// Leopardmander — the canonical Sivian healbelly drake. Docile, nom_mob,
// vore_default_mode = DM_HEAL. Heals allies, retaliates if struck.
// ---------------------------------------------------------------------------

/mob/living/simple_mob/vore/leopardmander
	ai_attack_on_sight = FALSE  // docile; only fights when provoked

/mob/living/simple_mob/vore/leopardmander/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/healbelly_heal_ally,
		/datum/ai_behavior/retaliate_to_attacker,
		/datum/ai_behavior/melee_attack,
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/flee_low_hp,
		/datum/ai_behavior/idle_wander,
		/datum/ai_behavior/idle_speak,
	)
	return L

// ---------------------------------------------------------------------------
// Friendly bigdragon — tamed / spawned-jovial dragon. Keeps the hostile
// dragon's charge + tail-sweep specials (no fire: norange = 1), gains the
// heal-belly behavior, and warns-then-enrages allies who attack it.
// ---------------------------------------------------------------------------

/mob/living/simple_mob/vore/bigdragon/friendly
	ai_attack_on_sight = FALSE

/mob/living/simple_mob/vore/bigdragon/friendly/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/healbelly_heal_ally,
		/datum/ai_behavior/dragon_friendly_warn,
		// Specials still usable once enraged (set_hostile flips it back).
		/datum/ai_behavior/dragon_tail_sweep,
		/datum/ai_behavior/dragon_charge,
		/datum/ai_behavior/melee_attack,
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/idle_wander,
		/datum/ai_behavior/idle_speak,
	)
	return L

// Warn-then-enrage retaliation toward allies. Mirrors the legacy
// healbelly/retaliate/dragon/react_to_attack three-strike escalation: the
// dragon barks an escalating warning and bats the offender back, and on the
// fourth provocation it enrages (which flips it hostile + targets them).
//
// State (warning count + last-warning time) lives on the dragon mob.

/mob/living/simple_mob/vore/bigdragon
	/// Escalating-warning count for the friendly dragon's ally retaliation.
	var/dq_dragon_warnings = 0
	/// world.time of the last warning, used to cool the counter back down.
	var/dq_dragon_last_warning = 0

/datum/ai_behavior/dragon_friendly_warn
	name = "warn provocateur"
	priority_class = DQ_BEHAVIOR_PRIORITY_INTERRUPT
	target_kind = DQ_TARGET_MOB
	eval_triggers = list(COMSIG_DQAI_DAMAGE_TAKEN)
	cooldown = 1 SECOND

/datum/ai_behavior/dragon_friendly_warn/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vore/bigdragon)

/datum/ai_behavior/dragon_friendly_warn/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/vore/bigdragon/D = brain.get_owner()
	if(!istype(D) || D.stat || D.noenrage || D.enraged)
		return null
	var/atom/attacker = brain.model?.get_last_attacker()
	if(!ismob(attacker))
		return null
	// Only allies (faction-mates / ALLY disposition) get the warning treatment;
	// genuine enemies should be handled by the normal hostile dragon kit once
	// enraged. If the attacker isn't an ally, let retaliate/enrage take over.
	if(!D.IIsAlly(attacker))
		return null
	// Decay the warning count if it's been quiet for a minute (legacy
	// handle_special_strategical reset).
	if(D.dq_dragon_last_warning + 1 MINUTE < world.time)
		D.dq_dragon_warnings = 0
	return DQAI_RESULT(110, attacker)

/datum/ai_behavior/dragon_friendly_warn/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/vore/bigdragon/D = brain.get_owner()
	if(!istype(D) || !ismob(target))
		return DQ_BEHAVIOR_FAILED
	switch(D.dq_dragon_warnings)
		if(0)
			D.say("Stop that.")
		if(1)
			D.say("I'm warning you here.")
		if(2)
			D.say("You do that again, and you'll regret it.")
		else
			// Fourth strike — enrage. This flips the dragon hostile and gives it
			// the attacker as a target (handled by the mob's enrage proc).
			D.enrage(target)
			return DQ_BEHAVIOR_DONE
	D.dq_dragon_last_warning = world.time
	D.dq_dragon_warnings += 1
	// Bat them back if we have a clear line — legacy dissuade()/chargeend().
	if(target in check_trajectory(target, D, pass_flags = PASSTABLE))
		D.chargeend(target, 1, 1)
	return DQ_BEHAVIOR_DONE
