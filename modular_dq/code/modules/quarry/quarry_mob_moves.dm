// Quarry mob move framework.
//
// Each combat-capable quarry mob declares a `quarry_move_pool` —
// a list of /datum/quarry_mob_move typepaths. When the AI is
// engaging a target, ICheckSpecialAttack/ISpecialAttack are routed
// here: the framework filters the pool to moves that are eligible
// (cooldown expired, target in range, custom predicate passes),
// weighted-picks one, runs the telegraph (overlay + sound), waits
// the windup, then calls execute(mob, target).
//
// Authoring a new move is small: subtype /datum/quarry_mob_move,
// set the declarative vars, and override execute(). No AI changes.
//
// Move state (cooldown timestamps) lives on the mob, not the move
// datum, so moves can be shared across all mobs of a given type
// (single instance per typepath in the cache below).


// ---- The move base class --------------------------------------------

/datum/quarry_mob_move
	/// Display name (logs, debug).
	var/name = "Generic Move"

	/// Cooldown in deciseconds after a successful execute. The move
	/// won't fire on the same mob again until world.time elapses
	/// the cooldown.
	var/cooldown = 5 SECONDS

	/// Wind-up time in deciseconds. During windup the mob is
	/// telegraphed but not yet committed — interruptions during
	/// this window cancel the move without spending its cooldown.
	/// 0 = instant move (no telegraph).
	var/windup = 0

	/// Eligible distance band from mob to target. Both endpoints
	/// inclusive. Default melee.
	var/range_min = 1
	var/range_max = 1

	/// Selection weight when the AI is choosing between eligible
	/// moves. Higher = picked more often.
	var/weight = 10

	/// Visual telegraph: an icon_state on the mob's icon (or a
	/// path to a separate dmi) shown as an overlay during windup.
	/// Null means no visual cue beyond the windup pause.
	var/telegraph_icon = null
	var/telegraph_icon_state = null

	/// Audio telegraph: a sound file played at the mob's tile when
	/// the windup starts. Null for silent.
	var/telegraph_sound = null
	var/telegraph_sound_volume = 60


/// Optional eligibility predicate. The framework already checks
/// range and cooldown — override this for additional gating
/// (target stunned, target adjacent to a wall, mob below HP %, etc.).
/// Default: always eligible.
/datum/quarry_mob_move/proc/can_use(mob/living/user, atom/target)
	return TRUE


/// The actual effect. Called after the windup completes. Subtypes
/// override this. Return ATTACK_SUCCESSFUL on success so the AI
/// holder treats it as a complete attack.
/datum/quarry_mob_move/proc/execute(mob/living/user, atom/target)
	return ATTACK_SUCCESSFUL


// ---- Cache so we don't allocate a move datum per mob ----------------

GLOBAL_LIST_EMPTY(_quarry_move_cache)

/proc/_quarry_get_move(typepath)
	if(!ispath(typepath, /datum/quarry_mob_move))
		return null
	if(!GLOB._quarry_move_cache[typepath])
		GLOB._quarry_move_cache[typepath] = new typepath
	return GLOB._quarry_move_cache[typepath]


// ---- Mob mixin: pool + cooldown tracking ----------------------------

/mob/living/simple_mob
	/// Typepaths of /datum/quarry_mob_move available to this mob.
	/// Null/empty = use upstream special-attack behavior (unchanged). The
	/// `length(quarry_move_pool)` guards in ICheckSpecialAttack /
	/// ISpecialAttack handle null fine; per CLAUDE.md §6a no eager `= list()`
	/// because every simple_mob in the game pays the allocation otherwise.
	var/list/quarry_move_pool
	/// Per-move cooldown stamps. Keyed by move typepath (as string),
	/// value is world.time when the move becomes usable again.
	var/list/quarry_move_cooldowns


// ---- AI interface overrides ----------------------------------------

/mob/living/simple_mob/ICheckSpecialAttack(atom/A)
	if(length(quarry_move_pool))
		return !!_quarry_pick_eligible_move(A)
	return ..()


/mob/living/simple_mob/ISpecialAttack(atom/A)
	if(length(quarry_move_pool))
		var/datum/quarry_mob_move/M = _quarry_pick_eligible_move(A)
		if(M)
			return _quarry_run_move(M, A)
		return FALSE
	return ..()


// ---- Move selection + execution -----------------------------------

/// Walks the mob's move pool, filters by can_use + range + cooldown,
/// weighted-picks one. Returns the move datum (cached instance) or
/// null if none are eligible right now.
/mob/living/simple_mob/proc/_quarry_pick_eligible_move(atom/A)
	if(!A || !length(quarry_move_pool))
		return null
	var/dist = get_dist(src, A)
	var/list/eligible = list()
	for(var/move_type in quarry_move_pool)
		var/datum/quarry_mob_move/M = _quarry_get_move(move_type)
		if(!M)
			continue
		if(dist < M.range_min || dist > M.range_max)
			continue
		if(quarry_move_cooldowns && quarry_move_cooldowns["[move_type]"] > world.time)
			continue
		if(!M.can_use(src, A))
			continue
		eligible[M] = M.weight
	if(!length(eligible))
		return null
	return pickweight(eligible)


/// Executes the move: starts the telegraph overlay/sound, waits the
/// windup, then runs execute(). Stamps the cooldown on success.
/// Returns the result of execute() so the AI holder can treat it as
/// a normal attack outcome.
/mob/living/simple_mob/proc/_quarry_run_move(datum/quarry_mob_move/M, atom/target)
	if(!M)
		return FALSE

	// Telegraph
	var/image/tele_image = null
	if(M.windup > 0)
		if(M.telegraph_sound)
			playsound(src, M.telegraph_sound, M.telegraph_sound_volume, 1)
		if(M.telegraph_icon && M.telegraph_icon_state)
			tele_image = image(M.telegraph_icon, src, M.telegraph_icon_state, ABOVE_MOB_LAYER)
			add_overlay(tele_image)
		sleep(M.windup)
		if(tele_image)
			cut_overlay(tele_image)

	// During the windup the mob (or target) may have died/moved/qdel'd.
	// Re-validate before executing so a wound-up move on a corpse
	// doesn't crash.
	if(QDELETED(src) || stat == DEAD)
		return FALSE
	if(QDELETED(target))
		return FALSE
	// Range may have changed during windup. Re-check; if out of
	// range, the move "fizzles" without spending its cooldown so
	// the mob can try a different move next tick.
	var/dist = get_dist(src, target)
	if(dist < M.range_min || dist > M.range_max)
		return FALSE

	var/result = M.execute(src, target)
	if(result == ATTACK_SUCCESSFUL)
		if(!quarry_move_cooldowns)
			quarry_move_cooldowns = list()
		quarry_move_cooldowns["[M.type]"] = world.time + M.cooldown
	return result


// ---- One reference move for framework validation -------------------
//
// A simple wind-up bite: 0.6s telegraph (red flicker + growl), then
// a double-damage bite on the target. Assigned to a test mob via
// quarry_move_pool below to verify the pipeline end-to-end.

/datum/quarry_mob_move/test_heavy_bite
	name = "Heavy Bite"
	cooldown = 5 SECONDS
	windup = 0.6 SECONDS
	range_min = 1
	range_max = 1
	weight = 10
	telegraph_sound = 'sound/voice/shriek1.ogg'
	telegraph_sound_volume = 40

/datum/quarry_mob_move/test_heavy_bite/execute(mob/living/user, atom/target)
	if(!isliving(target))
		return FALSE
	var/mob/living/L = target
	var/dmg = 0
	if(istype(user, /mob/living/simple_mob))
		var/mob/living/simple_mob/sm = user
		dmg = rand(sm.melee_damage_lower, sm.melee_damage_upper) * 2
	if(dmg <= 0)
		dmg = 20
	L.apply_damage(dmg, BRUTE, def_zone = pick(BP_TORSO, BP_HEAD))
	user.visible_message(span_danger("\The [user] lunges with a savage bite at \the [L]!"))
	return ATTACK_SUCCESSFUL
