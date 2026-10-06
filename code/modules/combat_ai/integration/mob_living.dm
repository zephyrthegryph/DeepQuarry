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

CAPABILITIES(/mob/living)
	ref_one(nameof(cameraFollow))
	every(PROC_REF(autofire_interval), then(PROC_REF(autofire_tick)), when = nameof(autofire_on))
	ref_many(nameof(shared_soul_links))
	// Equipped or pump-supplied breathing tank; custody belongs to its actual slot.
	ref_one(nameof(internal))
	owns_one(nameof(ai_brain), /datum/ai_brain)
	owns_one(nameof(aiming), /obj/aiming_overlay)
	owns_one(nameof(body), /datum/body)
	owns_one(nameof(changeling_state), /datum/changeling)
	owns_one(nameof(character_setup_button), /datum/character_setup_button)
	owns_one(nameof(deaf_loop), /datum/looping_sound/mob/deafened)
	owns_one(nameof(firesoundloop), /datum/looping_sound/mob/on_fire)
	owns_one(nameof(inventory_panel), /datum/inventory_panel)
	owns_one(nameof(say_list), /datum/say_list)
	owns_one(nameof(shadekin), /datum/shadekin)
	owns_one(nameof(turfslip), /datum/turfslip)
	owns_one(nameof(vore_panel_button), /datum/vore_panel_button)
	owns_many(nameof(owned_soul_links), /datum/soul_link)
	owns_many(nameof(status_effects))
	owns_many(nameof(trait_states))
	owns_many(nameof(body_effect_origins))
	owns_many(nameof(hud_list))
	owns_many(nameof(stasis_sources))
	// What holds the biological clock rate down (a sleeper, a stasis bed) is the body's stasis (code/modules/medical/stabilisation/stasis.dm).
	on_change(STAT_CLOCK_RATE_BIO, ANY, then(PROC_REF(clock_rate_bio_changed)))
	drag_onto(PROC_REF(mousedrop_input))
	drag_onto(PROC_REF(drop_input))

/mob/living/simple_mob
	/// If TRUE, the brain treats non-faction-mate mobs (including players) as
	/// hostile even when the faction registry says NEUTRAL. Covers the
	/// "everything tries to kill the spider" case for mobs whose faction string
	/// isn't enumerated in /datum/faction_data. Override to FALSE on pets,
	/// neutral wildlife, etc.
	var/ai_attack_on_sight = TRUE

	// Flip the framework on for every simple_mob by default.
	use_modern_ai = TRUE

/// Per-subtype type table of /datum/ai_behavior typepaths the mob has innately
/// (null: use the default factory). Override with TYPE_TABLE().
TYPE_TABLE_DECLARE(/mob/living, get_ai_behaviors, null)

/// Override per subtype. Returns a proc-local static list of
/// /datum/target_selector typepaths used as the brain's selector chain.
TYPE_TABLE_DECLARE(/mob/living, get_ai_target_selectors, null)

/// Creates the brain for a mob that opts in. Subtypes that should never get
/// a brain (player-controlled mobs like succlet, synx, borer) override this
/// to return FALSE.
/mob/living/proc/initialize_ai_brain()
	if(!use_modern_ai)
		return FALSE
	if(ai_brain)
		own_clear(src, nameof(ai_brain), OWN_DELETE)
	rel_set(src, nameof(ai_brain), new /datum/ai_brain(src))
	var/list/sels = TYPE_TABLE_GET(src, get_ai_target_selectors)
	if(sels && length(sels))
		ai_brain.target_selector_chain = sels.Copy()
	// Player-castable dispatcher verb is added lazily on Login (see player_verbs.dm)
	// to avoid bloating the verbs list of the ~95% of simple_mobs that no client
	// will ever pilot.
	return TRUE

/// Called from the damage pipeline. Wires the brain's notify_damage. Safe
/// to call on mobs without a brain — short-circuits.
/mob/living/proc/dq_notify_damage(amount, injury_kind, atom/attacker)
	if(!ai_brain || amount <= 0)
		return
	ai_brain.notify_damage(amount, injury_kind, attacker)

/// Modern brain implementation of taunt(). Replaces the legacy ai_holder
/// version. External code (cyborg guns, hivebot tank, slime feral subtype)
/// calls mob.taunt(attacker, TRUE) to force a target switch.
/mob/living/proc/taunt(atom/movable/taunter, force_target_switch = FALSE)
	if(!ai_brain || !ismob(taunter))
		return
	ai_brain.add_personal(taunter, DQ_DISPOSITION_HOSTILE, 60 SECONDS, "taunted")
	if(force_target_switch)
		rel_set(ai_brain, nameof(ai_brain.primary_threat), taunter)
	ai_brain.invalidate_selection()

/// Re-open Initialize to drive brain creation. Also handles say_list spawning
/// since DM resolves all `/mob/living/Initialize` overrides to the last-defined
/// one — having two separate re-opens silently drops the earlier definition.
// ALLOW(init/FRAMEWORK): the living base allocates its speech table and AI brain when its type has them
/mob/living/Initialize(mapload)
	. = ..()
	// Only allocate a say_list when the mob actually overrides the default
	// type. Most mobs inherit /datum/say_list (empty bark tables) — those get
	// no allocation, which matters at world-init when thousands of simple_mobs
	// spawn. Callers (idle_speak behavior, hear_say) already handle null.
	if(say_list_type && say_list_type != /datum/say_list)
		rel_set(src, nameof(say_list), new say_list_type(src))
	if(!ai_brain)
		initialize_ai_brain()
