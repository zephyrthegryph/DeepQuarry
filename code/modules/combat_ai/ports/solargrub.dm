// Solargrub port — restores the AI for the juvenile solargrub and its larva.
//
// Two deleted holders:
//   /datum/ai_holder/simple_mob/retaliate/solargrub
//       Retaliate-only. Its sole override was react_to_attack(): when struck,
//       unanchor (the grub anchors itself to drain power cables in Life()) and
//       free the AI (set_AI_busy(FALSE)) so it can turn and fight back. The
//       shock/poison-on-bite and the cable power-draining live on the mob
//       (apply_melee_effects / Life()) and are untouched by this port.
//   /datum/ai_holder/simple_mob/solargrub_larva
//       A bespoke MACHINE-hunter (not a mob-hunter): list_targets() returned
//       nearby powered /obj/machinery, can_attack() validated them, and
//       post_melee_attack() pushed just-visited machines onto a small
//       ignored_targets ring so the larva spreads out instead of re-nesting the
//       same machine. attack_target() (still on the mob) crawls into the
//       machine / vent. The larva never fights mobs at all.
//
// Modern port:
//   * solargrub: retaliate kit + a damage-triggered "unanchor and break free"
//     behavior reproducing react_to_attack.
//   * larva: a custom MACHINE target selector feeding a single "infest machine"
//     behavior that calls the surviving attack_target() crawl. A ring of
//     recently-visited machines (state on the mob) reproduces ignored_targets.

// ===========================================================================
// Juvenile solargrub
// ===========================================================================

/mob/living/simple_mob/vore/solargrub
	// Retaliate, don't aggress on sight — it would rather drain power.
	ai_attack_on_sight = FALSE

/mob/living/simple_mob/vore/solargrub/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/solargrub_break_free,
		/datum/ai_behavior/retaliate_to_attacker,
		/datum/ai_behavior/melee_attack,
		/datum/ai_behavior/maul_unconscious,
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/idle_speak,
	)
	return L

// Damage-triggered: unanchor from the powernet and release the AI lock so the
// grub can turn to fight. Mirrors the legacy
// retaliate/solargrub/react_to_attack override.
/datum/ai_behavior/solargrub_break_free
	name = "solargrub break free"
	priority_class = DQ_BEHAVIOR_PRIORITY_INTERRUPT
	target_kind = DQ_TARGET_NONE
	no_threat_required = TRUE
	eval_triggers = list(COMSIG_DQAI_DAMAGE_TAKEN)
	cooldown = 1 SECOND

/datum/ai_behavior/solargrub_break_free/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/vore/solargrub)

/datum/ai_behavior/solargrub_break_free/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/vore/solargrub/G = brain.get_owner()
	if(!istype(G))
		return null
	// Only worth running while we're stuck draining or AI-locked.
	if(!G.anchored && !brain.busy)
		return null
	return DQAI_RESULT(115, G)

/datum/ai_behavior/solargrub_break_free/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/vore/solargrub/G = brain.get_owner()
	if(!istype(G))
		return DQ_BEHAVIOR_FAILED
	G.anchored = FALSE
	brain.busy = FALSE
	return DQ_BEHAVIOR_DONE

// ===========================================================================
// Solargrub larva — machine-hunting infestation crawler
// ===========================================================================

/mob/living/simple_mob/animal/solargrub_larva
	ai_attack_on_sight = FALSE  // ignores mobs entirely; hunts machines
	/// Ring of recently-infested machines to avoid immediately re-nesting.
	/// Mirrors the legacy ai_holder.ignored_targets.
	var/list/dq_ignored_machines = null

/mob/living/simple_mob/animal/solargrub_larva/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/larva_infest_machine,
		/datum/ai_behavior/idle_wander,
	)
	return L

/mob/living/simple_mob/animal/solargrub_larva/get_ai_target_selectors()
	var/static/list/L = list(/datum/target_selector/larva_machine)
	return L

/// Shared validity check for a candidate machine, mirroring the legacy
/// list_targets() / can_attack() filters: powered (or APC/SMES), not on the
/// ignore list, not an already-occupied or excluded machine type.
/proc/dq_larva_machine_valid(mob/living/simple_mob/animal/solargrub_larva/LV, obj/machinery/M)
	if(!istype(LV) || !istype(M))
		return FALSE
	if(istype(M, /obj/machinery/atmospherics/unary/vent_pump))
		var/obj/machinery/atmospherics/unary/vent_pump/V = M
		return !V.welded
	if(is_type_in_list(M, LV.ignored_machine_types))
		return FALSE
	if(!M.idle_power_usage && !M.active_power_usage && !(istype(M, /obj/machinery/power/apc) || istype(M, /obj/machinery/power/smes)))
		return FALSE
	if(locate(/mob/living/simple_mob/animal/solargrub_larva) in M)
		return FALSE
	if(LAZYFIND(LV.dq_ignored_machines, M))
		return FALSE
	return TRUE

// Custom selector — picks the nearest valid powered machine (or unwelded vent)
// in view. Replaces the legacy list_targets() machine sweep. Note: the world
// model only buckets mobs, so this selector ignores `candidates` and runs its
// own machine scan (machines aren't perceived by the mob-only world model).
/datum/target_selector/larva_machine
	name = "larva machine"

/datum/target_selector/larva_machine/select(datum/ai_brain/brain, list/candidates)
	var/mob/living/simple_mob/animal/solargrub_larva/LV = brain.get_owner()
	if(!istype(LV))
		return null
	var/obj/machinery/best = null
	var/best_dist = INFINITY
	for(var/obj/machinery/M in range(brain.vision_range, LV))
		// Legacy gave vents a 50% consideration roll; keep the flavor.
		if(istype(M, /obj/machinery/atmospherics/unary/vent_pump) && !prob(50))
			continue
		if(!dq_larva_machine_valid(LV, M))
			continue
		var/d = get_dist(LV, M)
		if(d < best_dist)
			best_dist = d
			best = M
	return best

// The larva's whole combat loop: walk to a powered machine and crawl inside.
// attack_target() (on the mob) does the actual enter_machine / ventcrawl.
/datum/ai_behavior/larva_infest_machine
	name = "infest machine"
	priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL
	target_kind = DQ_TARGET_ITEM
	no_threat_required = TRUE

/datum/ai_behavior/larva_infest_machine/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/animal/solargrub_larva)

/datum/ai_behavior/larva_infest_machine/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/animal/solargrub_larva/LV = brain.get_owner()
	if(!istype(LV) || LV.client)
		return null
	// Don't go hunting while already nested inside a machine.
	if(istype(LV.loc, /obj/machinery))
		return null
	var/datum/target_selector/larva_selector = dq_get_selector(/datum/target_selector/larva_machine)
	var/obj/machinery/M = larva_selector.select(brain, null)
	if(!M)
		return null
	return DQAI_RESULT(20, M)

/datum/ai_behavior/larva_infest_machine/tick(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/animal/solargrub_larva/LV = brain.get_owner()
	var/obj/machinery/M = target
	if(!istype(LV) || !istype(M) || QDELETED(M))
		return DQ_BEHAVIOR_FAILED
	if(!dq_larva_machine_valid(LV, M))
		return DQ_BEHAVIOR_DONE
	if(!LV.Adjacent(M))
		if(!brain.smart_step_toward(M, 1))
			step_to(LV, M)
		return DQ_BEHAVIOR_CONTINUE
	// Adjacent — crawl in (enter_machine / ventcrawl), then remember the machine
	// so we spread out instead of re-nesting it. Mirrors post_melee_attack's
	// ignored_targets ring (cap 4).
	LV.attack_target(M)
	LAZYADD(LV.dq_ignored_machines, M)
	if(LAZYLEN(LV.dq_ignored_machines) > 3)
		LV.dq_ignored_machines.Cut(1, 2)
	return DQ_BEHAVIOR_DONE
