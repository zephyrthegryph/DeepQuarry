// Phased player melee: windup -> swing -> recovery.
//
// Harm-intent attacks with a weapon no longer land instantly. Instead the attacker winds
// up (sprite pulls back, target tiles light up), and after the windup the swing resolves
// against whoever is standing in the telegraphed tiles RIGHT THEN — so a target can step
// out during the windup to dodge. Bigger weapons wind up slower, recover slower, and sweep
// a wider arc. Moving (or dropping the weapon, or being incapacitated) cancels the swing.
//
// Entry point is /mob/living/attackby in code/_onclick/item_attack.dm, which diverts the
// instant attack here. The actual hit reuses the normal resolve_item_attack/apply_hit_effect
// path, so armor, shields, miss chance, hitsound and damage are unchanged.

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
		new /obj/effect/temp_visual/swing_telegraph(T, windup)

	// Pull-back animation.
	do_windup_animation(target, windup)

	// Set the reentry gate as late as possible: nothing above sleeps (animations
	// are async), so a second click can't race in before this line — and every
	// statement between a TRUE flag and its clear is a potential permanent wedge
	// if it runtimes.
	is_swinging = TRUE

	// Wait out the windup. do_after cancels if WE move, drop the weapon, or get incapacitated.
	// Passing target = src means a dodging victim does NOT cancel it (they just leave the tiles).
	if(!do_after(src, windup, target = src, progress = FALSE, hidden = TRUE, interaction_key = "melee_swing"))
		is_swinging = FALSE
		return FALSE

	// Re-validate the weapon is still in hand after the windup.
	if(QDELETED(weapon) || get_active_hand() != weapon)
		is_swinging = FALSE
		return FALSE

	// The swing is committed: clear the gate and start recovery BEFORE resolving
	// hits. resolve_item_attack/apply_hit_effect run arbitrary downstream code —
	// a runtime in there used to leave is_swinging stuck TRUE forever, permanently
	// disabling this mob's armed melee (attackby hard-gates on it with no reset
	// path). The click cooldown already prevents a double-swing in the gap.
	setClickCooldown(weapon.get_melee_recovery())
	is_swinging = FALSE

	// Swing: lunge + whoosh, then resolve against whoever is in the tiles NOW.
	do_attack_animation(target)
	playsound(src, 'sound/weapons/punchmiss.ogg', 40, 1, -1)
	var/zone = zone_sel?.selecting || BP_TORSO // fall back to chest (clientless mobs have no HUD doll)
	for(var/turf/T as anything in swing_tiles)
		for(var/mob/living/victim in T)
			if(victim == src)
				continue
			var/hit_zone = victim.resolve_item_attack(weapon, src, zone)
			if(hit_zone)
				weapon.apply_hit_effect(victim, src, hit_zone, 1) // attack_modifier 1; null would zero the damage

	return TRUE
