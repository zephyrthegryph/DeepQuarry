// Phased player melee: windup -> swing -> recovery.
//
// Harm-intent attacks with a weapon no longer land instantly. Instead the attacker winds
// up (sprite pulls back, target tiles light up), and after the windup the swing resolves
// against whoever is standing in the telegraphed tiles RIGHT THEN — so a target can step
// out during the windup to dodge. Bigger weapons wind up slower, recover slower, and sweep
// a wider arc. Moving (or dropping the weapon, or being incapacitated) cancels the swing.
//
// Entry point is /mob/living/attackby in code/_onclick/item_attack.dm, which diverts the
// instant attack here. The actual hit is resolved by calling the weapon's own
// /obj/item/attack() per victim (with melee_swing_resolving set so it skips its instant
// cooldown/animation), so weapon overrides (baton charge, energy-blade cell drain),
// incorporeal checks, lastattacker, attack logs, armor, shields, miss chance, hitsound
// and damage all behave exactly as an instant attack would — once per victim.

/// If a swing's flag is still up this long after its windup should have ended, the
/// safety timer force-clears it (a runtime between set and clear would otherwise
/// permanently disable this mob's armed melee).
#define MELEE_SWING_STUCK_GRACE (3 SECONDS)

// ---------------------------------------------------------------------------
// Item timing/shape — size-scaled defaults with per-weapon overrides.
// ---------------------------------------------------------------------------

/// Deciseconds of windup before the swing lands. Override `melee_windup` per weapon.
/obj/item/proc/get_melee_windup()
	if(melee_windup)
		return melee_windup
	// Indexed by w_class: TINY, SMALL, NORMAL, LARGE, HUGE.
	var/static/list/windup_by_size = list(2, 3, 4, 6, 9)
	return windup_by_size[clamp(w_class, ITEMSIZE_TINY, ITEMSIZE_HUGE)]

/// Deciseconds of recovery (post-swing click cooldown). Override `melee_recovery` per weapon.
/obj/item/proc/get_melee_recovery()
	if(melee_recovery)
		return melee_recovery
	var/static/list/recovery_by_size = list(3, 4, 5, 7, 10)
	return recovery_by_size[clamp(w_class, ITEMSIZE_TINY, ITEMSIZE_HUGE)]

/// TRUE if this weapon's swing sweeps a 3-tile frontal arc instead of a single tile.
/obj/item/proc/melee_is_sweep()
	if(!isnull(melee_sweep))
		return melee_sweep
	return w_class >= ITEMSIZE_LARGE

// ---------------------------------------------------------------------------
// Swing orchestration.
// ---------------------------------------------------------------------------

/// TRUE while a windup/swing is in progress; blocks starting another and is read by ClickOn.
/mob/living/var/is_swinging = FALSE
/// TRUE while begin_melee_swing is resolving hits through /obj/item/attack(); tells attack()
/// to skip its own click cooldown + lunge animation (the swing already did both).
/mob/living/var/melee_swing_resolving = FALSE
/// Monotonic swing id. The stuck-flag safety timer only clears the swing it was armed for,
/// so a timer left over from a finished swing can never clobber a newer one.
/mob/living/var/melee_swing_serial = 0

/// Safety net for is_swinging: fires MELEE_SWING_STUCK_GRACE after the windup should have
/// resolved. If the flag is still up for the same swing, something between the set and the
/// clear runtimed — release it (and the resolving flag) rather than wedging the mob forever.
/mob/living/proc/clear_stuck_swing(serial)
	if(!is_swinging || serial != melee_swing_serial)
		return FALSE
	log_world("[src] ([type]) melee swing #[serial] was still flagged after its windup expired; force-clearing is_swinging")
	is_swinging = FALSE
	melee_swing_resolving = FALSE
	return TRUE

/// The turfs a swing with `weapon` aimed at `target` would strike: the tile toward the
/// target, plus (for sweeping weapons) the two 45-degree flanking tiles.
/mob/living/proc/get_swing_tiles(atom/target, obj/item/weapon)
	var/turf/origin = get_turf(src)
	if(!origin)
		return list()
	var/swing_dir = get_dir(src, target)
	if(!swing_dir)			// target shares our tile — fall back to our facing
		swing_dir = dir
	var/list/turf/tiles = list()
	var/turf/front = get_step(origin, swing_dir)
	if(front)
		tiles += front
	if(weapon.melee_is_sweep())
		var/turf/flank_a = get_step(origin, turn(swing_dir, 45))
		var/turf/flank_b = get_step(origin, turn(swing_dir, -45))
		if(flank_a && !(flank_a in tiles))
			tiles += flank_a
		if(flank_b && !(flank_b in tiles))
			tiles += flank_b
	return tiles

/// Run a full windup -> swing -> recovery against `target` with `weapon`. Returns TRUE if a
/// swing was committed (whether or not it connected), FALSE if it couldn't start or cancelled.
/mob/living/proc/begin_melee_swing(mob/living/target, obj/item/weapon)
	if(is_swinging)
		return FALSE
	if(QDELETED(target) || QDELETED(weapon))
		return FALSE
	if(!weapon.force || (weapon.flags & NOBLUDGEON))
		return FALSE
	if(!Adjacent(target))
		return FALSE

	var/windup = weapon.get_melee_windup()
	var/list/turf/swing_tiles = get_swing_tiles(target, weapon)
	if(!length(swing_tiles))
		return FALSE

	face_atom(target)

	// Telegraph the targeted tiles for the duration of the windup (auto-clears).
	for(var/turf/T as anything in swing_tiles)
		make(/obj/effect/temp_visual/swing_telegraph, at = T, duration = windup)

	// Pull-back animation.
	do_windup_animation(target, windup)

	// Set the reentry gate as late as possible: nothing above sleeps (animations
	// are async), so a second click can't race in before this line — and every
	// statement between a TRUE flag and its clear is a potential permanent wedge
	// if it runtimes.
	is_swinging = TRUE
	melee_swing_resolving = FALSE
	var/serial = ++melee_swing_serial
	// Belt-and-braces: guarantees the flag resets even if something below runtimes.
	after(src, windup + MELEE_SWING_STUCK_GRACE, PROC_REF(clear_stuck_swing), with = list(serial))

	// Wait out the windup. do_after cancels if WE move, drop the weapon, or get incapacitated.
	// Passing target = src means a dodging victim does NOT cancel it (they just leave the tiles).
	task_start(/datum/task/timed/living_begin_melee_swing_living, src, src, duration = windup, target_arg = target, weapon = weapon, swing_tiles = swing_tiles, progress = FALSE, interaction_key = "melee_swing", hidden = TRUE)
	return TRUE

/datum/task/timed/living_begin_melee_swing_living
	complete_proc = /mob/living/proc/begin_melee_swing_living_done
	cancel_proc = /mob/living/proc/begin_melee_swing_living_failed
	var/mob/living/target_arg
	var/obj/item/weapon
	var/list/turf/swing_tiles

/mob/living/proc/begin_melee_swing_living_done(datum/task/timed/living_begin_melee_swing_living/task)
	var/mob/living/target = task.target_arg
	var/obj/item/weapon = task.weapon
	var/list/turf/swing_tiles = task.swing_tiles

	// Re-validate the weapon is still in hand after the windup.
	if(QDELETED(weapon) || get_active_hand() != weapon)
		is_swinging = FALSE
		return FALSE

	// The swing is committed: clear the gate and start recovery BEFORE resolving
	// hits. weapon.attack() runs arbitrary downstream code — a runtime in there
	// used to leave is_swinging stuck TRUE forever, permanently disabling this
	// mob's armed melee (attackby hard-gates on it with no reset path). The click
	// cooldown already prevents a double-swing in the gap; clear_stuck_swing is
	// the last-resort backstop.
	setClickCooldown(weapon.get_melee_recovery())
	is_swinging = FALSE

	// Swing: lunge + whoosh, then resolve against whoever is in the tiles NOW.
	do_attack_animation(target)
	play_sfx(src, SFX_WEAPONS_PUNCHMISS, 1.6)
	var/zone = zone_sel?.selecting || BP_TORSO // fall back to chest (clientless mobs have no HUD doll)
	// Resolve THROUGH the weapon's attack() so per-weapon overrides (stunbaton
	// deductcharge, energy-blade cell use), is_incorporeal, lastattacker and
	// add_attack_logs all run exactly once per victim. melee_swing_resolving makes
	// the base attack() skip its instant cooldown/animation — already paid above.
	melee_swing_resolving = TRUE
	for(var/turf/T as anything in swing_tiles)
		for(var/mob/living/victim in contents_of(T))
			if(victim == src)
				continue
			if(QDELETED(weapon))
				break // a weapon override consumed/destroyed it mid-sweep
			weapon.attack(victim, src, zone, 1) // attack_modifier 1; null would zero the damage
	melee_swing_resolving = FALSE

	return TRUE

/mob/living/proc/begin_melee_swing_living_failed(datum/task/timed/living_begin_melee_swing_living/task)
	is_swinging = FALSE
	return FALSE
