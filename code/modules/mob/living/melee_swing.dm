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

/// world.time until which a follow-up swing combos (faster windup). Set by a landed, unparried
/// hit; cleared by a miss or a parry.
/mob/living/var/combo_until = 0

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

/// Run a full windup -> swing -> recovery aimed at `target` (a mob or a turf) with `weapon`.
/// The swing resolves against whoever stands in the telegraphed tiles, so aiming at a tile hits
/// anything on it. Returns TRUE if a swing was committed (whether or not it connected), FALSE if
/// it couldn't start or cancelled.
/mob/living/proc/begin_melee_swing(atom/target, obj/item/weapon)
	if(is_swinging)
		return FALSE
	if(world.time < melee_locked_until || world.time < l_move_time + DQ_MOVE_ATTACK_LOCK)
		return FALSE
	if(QDELETED(target) || QDELETED(weapon))
		return FALSE
	if(!weapon.force || (weapon.flags & NOBLUDGEON))
		return FALSE
	if(!Adjacent(target))
		return FALSE

	var/list/mods = get_intent_combat_mods()
	// Fatigue: the more drained you are, the slower you wind up and recover.
	var/fatigue_mult = 1 + (1 - stamina / max(max_stamina, 1)) * STAMINA_FATIGUE_SCALE
	// Combo: a swing started soon after a landed hit (or a parry) winds up faster.
	var/comboing = world.time < combo_until
	var/windup = max(2, round(weapon.get_melee_windup() * mods[INTENT_MOD_WINDUP] * fatigue_mult * (comboing ? COMBO_WINDUP_MULT : 1)))
	var/list/turf/swing_tiles = get_swing_tiles(target, weapon)
	if(!length(swing_tiles))
		return FALSE

	is_swinging = TRUE
	feint_requested = FALSE
	face_atom(target)

	// Exertion: bigger weapons and aggressive intents cost more stamina (Help is cheap).
	var/swing_cost = round(STAMINA_COST_SWING * (weapon.w_class / ITEMSIZE_NORMAL) * mods[INTENT_MOD_DAMAGE])
	adjust_stamina(-swing_cost)

	// Telegraph the targeted tiles for the duration of the windup (auto-clears), and warn any AI
	// mobs standing in them so they can dodge or brace (interactive_melee.dm). The brain reacts via
	// its behavior-signal dispatch, not a raw BYOND signal.
	for(var/turf/T as anything in swing_tiles)
		new /obj/effect/temp_visual/swing_telegraph(T, windup)
		for(var/mob/living/threatened in T)
			if(threatened != src && threatened.ai_brain)
				threatened.ai_brain.notify_incoming_attack(src, windup)

	// Pull-back animation.
	do_windup_animation(target, windup)

	// Wait out the windup. do_after cancels if WE move, drop the weapon, or get incapacitated.
	// Passing target = src means a dodging victim does NOT cancel it (they just leave the tiles).
	// The extra_check cancels on a feint (right-click during the windup).
	if(!do_after(src, windup, target = src, progress = FALSE, hidden = TRUE, interaction_key = "melee_swing", extra_checks = CALLBACK(src, PROC_REF(swing_not_feinted))))
		if(feint_requested)
			adjust_stamina(round(swing_cost * 0.75)) // a feint hands most of the wasted effort back
		is_swinging = FALSE
		return FALSE

	// Re-validate the weapon is still in hand after the windup.
	if(QDELETED(weapon) || get_active_hand() != weapon)
		is_swinging = FALSE
		return FALSE

	// Swing: lunge + whoosh, then resolve against whoever is in the tiles NOW.
	do_attack_animation(target)
	playsound(src, 'sound/weapons/punchmiss.ogg', 40, 1, -1)
	var/zone = zone_sel?.selecting || BP_TORSO // fall back to chest (clientless mobs have no HUD doll)
	var/landed = FALSE // an unparried hit connected — gates the combo chain
	for(var/turf/T as anything in swing_tiles)
		for(var/mob/living/victim in T)
			if(victim == src)
				continue
			var/hit_zone = victim.resolve_item_attack(weapon, src, zone)
			if(hit_zone)
				weapon.apply_hit_effect(victim, src, hit_zone, mods[INTENT_MOD_DAMAGE])
				landed = TRUE

	if(landed)
		// Flow into a follow-up: open the combo window and cut (but don't skip) the recovery.
		combo_until = world.time + COMBO_WINDOW
		setClickCooldown(max(2, round(weapon.get_melee_recovery() * mods[INTENT_MOD_RECOVERY] * fatigue_mult * COMBO_RECOVERY_MULT)))
	else
		// Whiffed or got parried: full (fatigue-scaled) recovery, and the combo is broken.
		combo_until = 0
		setClickCooldown(max(2, round(weapon.get_melee_recovery() * mods[INTENT_MOD_RECOVERY] * fatigue_mult)))
	is_swinging = FALSE
	return TRUE

/// do_after extra-check for the windup: a right-click during the windup sets feint_requested,
/// which cancels the swing here (no damage, no cooldown — a feint is free).
/mob/living/proc/swing_not_feinted()
	return !feint_requested

// ---------------------------------------------------------------------------
// Shove — the Disarm-intent answer to a guard.
// ---------------------------------------------------------------------------

/// Disarm-intent shove: a committed move (windup, feintable, loses to a faster attack) that goes
/// THROUGH a guard rather than being negated by it. On connect it breaks the target's block, knocks
/// them back a tile, knocks them down if they slam into something, and locks them out of moving and
/// acting for a beat. Reuses the swing's windup/feint machinery.
/mob/living/proc/begin_melee_shove(atom/target, obj/item/weapon)
	if(is_swinging)
		return FALSE
	if(world.time < melee_locked_until || world.time < l_move_time + DQ_MOVE_ATTACK_LOCK)
		return FALSE
	if(QDELETED(target) || QDELETED(weapon))
		return FALSE
	if(!weapon.force || (weapon.flags & NOBLUDGEON))
		return FALSE
	if(!Adjacent(target))
		return FALSE

	var/list/mods = get_intent_combat_mods()
	var/fatigue_mult = 1 + (1 - stamina / max(max_stamina, 1)) * STAMINA_FATIGUE_SCALE
	var/windup = max(1, round(weapon.get_melee_windup() * mods[INTENT_MOD_WINDUP] * fatigue_mult))

	is_swinging = TRUE
	feint_requested = FALSE
	face_atom(target)
	adjust_stamina(-round(STAMINA_COST_SWING * (weapon.w_class / ITEMSIZE_NORMAL)))

	var/turf/front = get_step(src, get_dir(src, target)) || get_turf(target)
	if(front)
		new /obj/effect/temp_visual/swing_telegraph(front, windup)
	do_windup_animation(target, windup)

	// Same windup/feint contract as a swing: moving, dropping the weapon, incapacitation or a feint cancel it.
	if(!do_after(src, windup, target = src, progress = FALSE, hidden = TRUE, interaction_key = "melee_swing", extra_checks = CALLBACK(src, PROC_REF(swing_not_feinted))))
		is_swinging = FALSE
		return FALSE

	if(QDELETED(weapon) || get_active_hand() != weapon)
		is_swinging = FALSE
		return FALSE

	do_attack_animation(target)
	playsound(src, 'sound/weapons/thudswoosh.ogg', 50, 1, -1)
	if(isliving(target) && Adjacent(target))
		resolve_shove(target)

	setClickCooldown(max(1, round(weapon.get_melee_recovery() * mods[INTENT_MOD_RECOVERY] * fatigue_mult)))
	is_swinging = FALSE
	return TRUE

/// Apply a shove to an adjacent victim: break their guard, knock them a tile away (knocking them
/// down if that tile is blocked by a wall, object, or another body), and lock their movement and
/// actions briefly.
/mob/living/proc/resolve_shove(mob/living/victim)
	var/shove_dir = get_dir(src, victim)
	if(!shove_dir)
		shove_dir = dir
	if(victim.blocking)
		victim.end_block() // the shove goes through the guard and drops it

	// Explicit density check rather than Move()'s return — mobs would otherwise swap places
	// instead of colliding, and we want "shoved into someone" to knock them down.
	var/turf/dest = get_step(victim, shove_dir)
	var/blocked = !dest || dest.density
	if(!blocked)
		for(var/atom/movable/obstacle in dest)
			if(obstacle.density && obstacle != victim)
				blocked = TRUE
				break

	if(blocked)
		// Slammed into a wall, object, or another body — knocked down.
		victim.Weaken(DQ_SHOVE_KNOCKDOWN)
		victim.visible_message(span_danger("\The [src] shoves \the [victim] into the way, knocking them down!"))
	else
		victim.Move(dest, shove_dir) // dest is clear of dense atoms, so this won't swap
		victim.visible_message(span_warning("\The [src] shoves \the [victim] back!"))

	victim.melee_locked_until = max(victim.melee_locked_until, world.time + DQ_SHOVE_LOCK)
	victim.setMoveCooldown(DQ_SHOVE_LOCK)
