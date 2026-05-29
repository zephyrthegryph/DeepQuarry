// Mob integration for the AI framework.
//
// Adds to /mob/living:
//   1. `ai_brain` slot + `use_modern_ai` opt-in flag (TRUE on /mob/living/simple_mob).
//   2. Getter procs for innate behaviors and target selectors (per the
//      static-list-in-proc pattern — never a var on the parent).
//   3. Initialization hook that creates a brain when the flag is set.
//   4. A damage-notification proc that fires the brain's signal pipeline.
//   5. taunt() — promotes the taunter to a personal HOSTILE entry.
//   6. Initialize() re-open to drive brain creation after the upstream chain.

/mob/living
	/// Slot for the AI brain. null on mobs without AI (humans, silicons,
	/// explicitly opted-out simple_mobs).
	var/datum/ai_brain/ai_brain = null

	/// Set to TRUE on a mob subtype to give it an AI brain. Default TRUE on
	/// /mob/living/simple_mob, FALSE everywhere else.
	var/use_modern_ai = FALSE

/mob/living/simple_mob
	/// If TRUE, the brain treats non-faction-mate mobs (including players) as
	/// hostile even when the faction registry says NEUTRAL. Covers the
	/// "everything tries to kill the spider" case for mobs whose faction string
	/// isn't enumerated in /datum/faction_data. Override to FALSE on pets,
	/// neutral wildlife, etc.
	var/ai_attack_on_sight = TRUE

	// Flip the framework on for every simple_mob by default.
	use_modern_ai = TRUE

/// Override per subtype. Returns a proc-local `var/static/list/L = list(...)`
/// of /datum/ai_behavior typepaths the mob has innately.
/mob/living/proc/get_ai_behaviors()
	return null

/// Override per subtype. Returns a proc-local static list of
/// /datum/target_selector typepaths used as the brain's selector chain.
/mob/living/proc/get_ai_target_selectors()
	return null

/// Creates the brain for a mob that opts in. Subtypes that should never get
/// a brain (player-controlled mobs like succlet, synx, borer) override this
/// to return FALSE.
/mob/living/proc/initialize_ai_brain()
	if(!use_modern_ai)
		return FALSE
	if(ai_brain)
		QDEL_NULL(ai_brain)
	ai_brain = new /datum/ai_brain(src)
	var/list/sels = get_ai_target_selectors()
	if(sels && length(sels))
		ai_brain.target_selector_chain = sels.Copy()
	// Player-castable dispatcher verb is added lazily on Login (see player_verbs.dm)
	// to avoid bloating the verbs list of the ~95% of simple_mobs that no client
	// will ever pilot.
	return TRUE

/// Called from the damage pipeline. Wires the brain's notify_damage. Safe
/// to call on mobs without a brain — short-circuits.
/mob/living/proc/dq_notify_damage(amount, damagetype, atom/attacker)
	if(!ai_brain || amount <= 0)
		return
	ai_brain.notify_damage(amount, damagetype, attacker)

/// Modern brain implementation of taunt(). Replaces the legacy ai_holder
/// version. External code (cyborg guns, hivebot tank, slime feral subtype)
/// calls mob.taunt(attacker, TRUE) to force a target switch.
/mob/living/proc/taunt(atom/movable/taunter, force_target_switch = FALSE)
	if(!ai_brain || !ismob(taunter))
		return
	ai_brain.add_personal(taunter, DQ_DISPOSITION_HOSTILE, 60 SECONDS, "taunted")
	if(force_target_switch)
		ai_brain.primary_threat = taunter
	ai_brain.invalidate_selection()

/// Re-open Initialize to drive brain creation. Also handles say_list spawning
/// since DM resolves all `/mob/living/Initialize` overrides to the last-defined
/// one — having two separate re-opens silently drops the earlier definition.
/mob/living/Initialize(mapload)
	. = ..()
	// Only allocate a say_list when the mob actually overrides the default
	// type. Most mobs inherit /datum/say_list (empty bark tables) — those get
	// no allocation, which matters at world-init when thousands of simple_mobs
	// spawn. Callers (idle_speak behavior, hear_say) already handle null.
	if(say_list_type && say_list_type != /datum/say_list)
		say_list = new say_list_type(src)
	if(!ai_brain)
		initialize_ai_brain()

/mob/living/Destroy()
	QDEL_NULL(ai_brain)
	return ..()
