// Modern-AI port for /mob/living/simple_mob/animal/sif/sakimm — Sivian
// kleptomaniac scavengers ("raccoons") that hoard shiny things and only fight
// when provoked.
//
// Two legacy AI flavours existed:
//   /datum/ai_holder/simple_mob/retaliate/cooperative/sakimm  (base sakimm) —
//       only wore hats it picked up; otherwise plain retaliate+cooperative.
//   /datum/ai_holder/simple_mob/intentional/sakimm  (the /intelligent subtype) —
//       the full klepto brain:
//         * list_targets()/find_target(): added loose loot (steal_loot_list)
//           outside its hoard as theft targets when not already holding an item.
//         * pre_melee_attack(): dropped any held item before a fight; disarmed
//           standing humans, hurt grounded ones (sometimes bolting with their
//           dropped loot instead), help-"attacked" pickup-able items.
//         * post_melee_attack(): picked up an adjacent item with an empty hand;
//           when fighting a living thing it side-stepped (dodge dance) and
//           called for help.
//         * handle_special_strategical(): wore hats, ran a `greed` counter that
//           grew while empty-handed and made it more likely to go hunting loot,
//           dropped loot at home, and pinned max_home_distance while carrying.
//         * should_go_home()/special_flee_check(): wanted to run home / flee
//           while holding loot.
//
// take_hat() / drop_hat() / the `hat` var still live on the sakimm mob.

/mob/living/simple_mob/animal/sif/sakimm
	use_modern_ai = TRUE

/mob/living/simple_mob/animal/sif/sakimm/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/sakimm_hoard_tick,
		/datum/ai_behavior/sakimm_steal_item,
		/datum/ai_behavior/sakimm_smart_melee,
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/retaliate_to_attacker,
		/datum/ai_behavior/call_for_help,
		/datum/ai_behavior/return_home,
		/datum/ai_behavior/follow_leader,
		/datum/ai_behavior/flee_low_hp,
		/datum/ai_behavior/idle_wander,
		/datum/ai_behavior/idle_speak,
	)
	return L

// The base sakimm is passive (retaliate-only); only the /intelligent variant
// went actively hunting. We keep that distinction via ai_attack_on_sight, which
// both inherit as FALSE-ish through faction dispositions — they do not aggress
// on sight, matching legacy hostile = FALSE.

/mob/living/simple_mob/animal/sif/sakimm/get_ai_target_selectors()
	var/static/list/L = list(/datum/target_selector/sakimm_loot)
	return L

// ---------------------------------------------------------------------------
// Loot-aware target selector. Falls back to the closest hostile, but when the
// sakimm is empty-handed and greedy it will also consider loose loot outside
// its hoard as a "target" so the steal behavior can go grab it. Mirrors the
// legacy list_targets()/find_target() item-injection.
// ---------------------------------------------------------------------------

/// Shared loot table — the item types a sakimm covets. Proc-local static so it
/// is allocated once and shared, the DM-idiomatic per-type constant table.
/proc/dq_sakimm_loot_types()
	var/static/list/L = list(
		/obj/item/coin,
		/obj/item/gun,
		/obj/item/fossil,
		/obj/item/stack/material,
		/obj/item/material,
		/obj/item/reagent_containers/food/snacks,
		/obj/item/clothing/head,
		/obj/item/reagent_containers/glass,
		/obj/item/flashlight,
		/obj/item/stack/medical,
		/obj/item/seeds,
		/obj/item/spacecash,
	)
	return L

/// Find the nearest covetable, unanchored, unowned item outside the sakimm's
/// hoard radius. Returns null if the sakimm already holds something.
/proc/dq_sakimm_find_loot(mob/living/simple_mob/animal/sif/sakimm/S, range = 7)
	if(!istype(S) || S.get_active_hand())
		return null
	var/turf/home = S.ai_brain?.home_turf
	var/list/loot_types = dq_sakimm_loot_types()
	var/obj/item/best = null
	var/best_dist = INFINITY
	for(var/obj/item/I in view(range, S))
		if(I.anchored || (I in S.contents))
			continue
		if(home && get_dist(I, home) <= 1)
			continue  // already in the hoard
		if(!is_type_in_list(I, loot_types))
			continue
		var/d = get_dist(S, I)
		if(d < best_dist)
			best_dist = d
			best = I
	return best

/datum/target_selector/sakimm_loot

/datum/target_selector/sakimm_loot/select(datum/ai_brain/brain, list/candidates)
	// Living threats always take priority — defend yourself first.
	var/threat = dq_get_selector(/datum/target_selector/closest).select(brain, candidates)
	if(threat)
		return threat
	return null  // loot acquisition is handled by the steal behavior, not here

// ---------------------------------------------------------------------------
// Steal item — walk to a loose covetable item and pick it up. Background-ish
// priority so any real combat preempts it, but above plain idle wander.
// ---------------------------------------------------------------------------

/datum/ai_behavior/sakimm_steal_item
	name = "steal shiny"
	priority_class = DQ_BEHAVIOR_PRIORITY_IDLE
	target_kind = DQ_TARGET_ITEM
	no_threat_required = TRUE

/datum/ai_behavior/sakimm_steal_item/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/animal/sif/sakimm)

/datum/ai_behavior/sakimm_steal_item/evaluate(datum/ai_brain/brain, atom/source)
	if(brain.primary_threat)
		return null  // busy fighting
	var/mob/living/simple_mob/animal/sif/sakimm/S = brain.holder
	if(!istype(S) || S.get_active_hand())
		return null
	// Greed: the legacy AI rolled prob(5 + greed) to start hunting. We bake a
	// modest constant chance per evaluate so empty-handed sakimm drift toward
	// loot over time without thrashing.
	if(!prob(35))
		return null
	var/obj/item/loot = dq_sakimm_find_loot(S, brain.vision_range)
	if(!loot)
		return null
	return DQAI_RESULT(6, loot)

/datum/ai_behavior/sakimm_steal_item/tick(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/animal/sif/sakimm/S = brain.holder
	if(!istype(S) || QDELETED(target) || S.get_active_hand())
		return DQ_BEHAVIOR_DONE
	var/obj/item/loot = target
	if(loot.anchored)
		return DQ_BEHAVIOR_FAILED
	if(S.Adjacent(loot))
		S.a_intent = I_HELP
		loot.attack_hand(S)
		return DQ_BEHAVIOR_DONE
	if(!brain.smart_step_toward(loot))
		step_to(S, loot)
	return DQ_BEHAVIOR_CONTINUE

// ---------------------------------------------------------------------------
// Smart melee — intent selection + opportunistic loot-grab + dodge dance.
// Mirrors legacy pre_melee_attack() + post_melee_attack().
// ---------------------------------------------------------------------------

/datum/ai_behavior/sakimm_smart_melee
	name = "sakimm scuffle"
	priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL
	target_kind = DQ_TARGET_MOB
	min_range = 0
	max_range = 1

/datum/ai_behavior/sakimm_smart_melee/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/animal/sif/sakimm)

/datum/ai_behavior/sakimm_smart_melee/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/animal/sif/sakimm/S = brain.holder
	var/mob/threat = brain.primary_threat
	if(!istype(S) || !threat || !S.Adjacent(threat))
		return null
	if(!S.checkClickCooldown())
		return null
	return DQAI_RESULT(42, threat)

/datum/ai_behavior/sakimm_smart_melee/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/animal/sif/sakimm/S = brain.holder
	if(!istype(S) || !isliving(target))
		return DQ_BEHAVIOR_FAILED
	var/mob/living/L = target
	// pre_melee_attack: drop any held loot to fight bare-pawed.
	if(S.get_active_hand())
		S.drop_from_inventory(S.get_active_hand(), get_turf(S))
	// Intent selection.
	if(ishuman(L))
		if(L.incapacitated(INCAPACITATION_DISABLED))
			// Grounded victim: sometimes bolt with their dropped loot instead of
			// pressing the attack. We disengage and grab the loot directly; the
			// sakimm_steal_item behavior takes over for any farther loot.
			// TODO: legacy retargeted to the exact dropped item; here we settle
			// for "grab adjacent loot, else disengage" which is close enough.
			if(prob(30))
				var/turf/T = get_turf(L)
				var/obj/item/IT = locate() in T.contents
				if(IT && !IT.anchored && !S.get_active_hand())
					if(S.Adjacent(IT))
						S.a_intent = I_HELP
						IT.attack_hand(S)
					return DQ_BEHAVIOR_DONE
			S.a_intent = I_HURT
		else
			S.a_intent = I_DISARM
	else
		S.a_intent = I_HURT
	S.attack_target(L)
	brain.last_attack_at = world.time
	// post_melee_attack: dance to the side so we're a harder target, then the
	// generic call_for_help behavior can rally allies next selection.
	var/turf/sidestep = get_step(S, pick(GLOB.alldirs))
	if(sidestep && !sidestep.density)
		S.IMove(sidestep)
	S.face_atom(L)
	return DQ_BEHAVIOR_DONE

// ---------------------------------------------------------------------------
// Hoard tick — wear hats, manage greed/hoard state, drop loot at home. Mirrors
// legacy handle_special_strategical()/handle_special_tactic(). Background
// priority, slow cooldown.
// ---------------------------------------------------------------------------

/datum/ai_behavior/sakimm_hoard_tick
	name = "manage hoard"
	priority_class = DQ_BEHAVIOR_PRIORITY_BACKGROUND
	target_kind = DQ_TARGET_NONE
	no_threat_required = TRUE
	cooldown = 4 SECONDS

/datum/ai_behavior/sakimm_hoard_tick/applicable_to(mob/living/owner)
	return istype(owner, /mob/living/simple_mob/animal/sif/sakimm)

/datum/ai_behavior/sakimm_hoard_tick/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/simple_mob/animal/sif/sakimm/S = brain.holder
	if(!istype(S))
		return null
	return DQAI_RESULT(1, S)

/datum/ai_behavior/sakimm_hoard_tick/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/simple_mob/animal/sif/sakimm/S = brain.holder
	if(!istype(S))
		return DQ_BEHAVIOR_FAILED
	var/obj/item/held = S.get_active_hand()
	// Wear a held hat.
	if(held && istype(held, /obj/item/clothing/head) && !S.hat)
		S.take_hat(S)
		S.visible_message(span_infoplain("[span_bold("\The [S]")] wears \the [held]."))
		held = S.get_active_hand()
	// Carrying loot? Head home and pin the home radius so we stash it.
	var/carrying = held || S.hat
	if(carrying && held)
		brain.max_home_distance = 1
		brain.returns_home = TRUE
		// At home: stash the loot.
		if(brain.home_turf && get_dist(S, brain.home_turf) <= 1)
			S.drop_from_inventory(held, get_turf(S))
	else
		// Empty-handed: loosen leash and let it roam for new loot.
		brain.max_home_distance = initial(brain.max_home_distance)
		brain.returns_home = FALSE
	return DQ_BEHAVIOR_DONE
