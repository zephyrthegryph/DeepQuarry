// Mob integration for the AI framework.
//
// Adds to /mob/living:
//   1. `ai_brain` slot + `use_modern_ai` opt-in flag (TRUE on /mob/living/simple_mob).
//   2. Getter procs for innate behaviors and target selectors (per the
//      static-list-in-proc pattern — never a var on the parent).
//   3. Initialization hook that creates a brain when the flag is set.
//   4. A damage-notification proc that fires the brain's signal pipeline.
//   5. taunt() — promotes the taunter to a personal HOSTILE entry.
//   6. A setup() hook that drives brain creation once the Initialize() chain has returned.

/mob/living
	/// Slot for the AI brain. null on mobs without AI (humans, silicons,
	/// explicitly opted-out simple_mobs).
	var/datum/ai_brain/ai_brain = null


/mob/living/simple_mob
	/// If TRUE, the brain treats non-faction-mate mobs (including players) as
	/// hostile even when the faction registry says NEUTRAL. Covers the
	/// "everything tries to kill the spider" case for mobs whose faction string
	/// isn't enumerated in /datum/faction_data. Override to FALSE on pets,
	/// neutral wildlife, etc.
	var/ai_attack_on_sight = TRUE

	// Flip the framework on for every simple_mob by default.

/// Per-subtype type table of /datum/ai_behavior typepaths the mob has innately
/// (null: use the default factory). Override with TYPE_TABLE().
TYPE_TABLE_DECLARE(/mob/living, get_ai_behaviors, null)

/// Override per subtype. Returns a proc-local static list of
/// /datum/target_selector typepaths used as the brain's selector chain.
TYPE_TABLE_DECLARE(/mob/living, get_ai_target_selectors, null)

/// Creates the brain for a mob that opts in. Subtypes that should never get
/// a brain (player-controlled mobs like succlet, synx, borer) override this
/// to return FALSE.
/// The starting say list (owns_one(starts =)): only a mob that overrides the default type gets one.
/// Most mobs inherit /datum/say_list (empty bark tables) and allocate nothing; idle_speak and hear_say handle null.
/mob/living/proc/make_say_list(current)
	var/say_type = living_rules_of(src).say_list_type
	if(say_type && say_type != /datum/say_list)
		return say_type

/mob/living/proc/initialize_ai_brain()
	if(!living_rules_of(src).use_modern_ai)
		return FALSE
	if(ai_brain)
		rel_clear(src, nameof(ai_brain))
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

/// Its AI brain, made when it has none and its type opts in (a setup() hook of the living capabilities, after the HUD slot table).
/mob/living/proc/start_ai_brain()
	// Only allocate a say_list when the mob actually overrides the default
	// type. Most mobs inherit /datum/say_list (empty bark tables) — those get
	// no allocation, which matters at world-init when thousands of simple_mobs
	// spawn. Callers (idle_speak behavior, hear_say) already handle null.
	if(!ai_brain)
		initialize_ai_brain()

CAPABILITIES_PART(/mob/living, ai)
	setup(PROC_REF(start_ai_brain))
	owns_one(nameof(ai_brain), /datum/ai_brain)
	on_notice(/datum/notice/mob_statchange, then(PROC_REF(ai_notice_stat_change)))
	on_notice(/datum/notice/living_injured, then(PROC_REF(ai_notice_injured)))
	// The player-castable-moves dispatcher verb is added lazily on login, which keeps it off the verbs list of every wild simple_mob.
	on_notice(/datum/notice/mob_login, then(PROC_REF(ai_notice_login)))
	on_notice(/datum/notice/mob_logout, then(PROC_REF(ai_notice_logout)))
	on_notice(/datum/notice/standing_changed, then(PROC_REF(ai_notice_standing)))
	on_change(STAT_AI_AUTHORITY, ANY, then(PROC_REF(ai_authority_changed)))
	on_change(STAT_RELEVANCE, ANY, then(PROC_REF(ai_relevance_changed)))

/// The mob's stat changed: its brain follows.
/mob/living/proc/ai_notice_stat_change(datum/act/notice/A)
	if(ai_brain?.holder == src)
		ai_brain.on_stat_change(A)

/// The mob was injured: its brain is told.
/mob/living/proc/ai_notice_injured(datum/act/notice/A)
	if(ai_brain?.holder == src)
		ai_brain.on_holder_injured(A)

/// A player took the mob over.
/mob/living/proc/ai_notice_login(datum/act/notice/A)
	if(ai_brain?.holder == src)
		ai_brain.on_holder_login_event(A)

/// The player left the mob.
/mob/living/proc/ai_notice_logout(datum/act/notice/A)
	if(ai_brain?.holder == src)
		ai_brain.on_holder_logout_event(A)

/// A standing of the mob changed: the brain forgets what it worked out from them.
/mob/living/proc/ai_notice_standing(datum/act/notice/A)
	if(ai_brain?.holder == src)
		ai_brain.standings_changed(A)
