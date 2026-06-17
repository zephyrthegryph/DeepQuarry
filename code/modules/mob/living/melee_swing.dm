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

/// TRUE while the current swing is a charged heavy. Drives the telegraph colour, wider
/// (cleave) arc, knockback, bonus damage, and bonus stagger.
/mob/living/var/charging_heavy = FALSE

/// One-shot: the next swing is a charged heavy. Set by the Wind Up verb; also implied by a
/// fresh riposte (a parry flows into a heavy finisher).
/mob/living/var/queued_heavy = FALSE

/// Charge a heavy blow into your next swing, then swing at the adjacent thing you're facing.
/// Bindable; the heavy is slower and telegraphed (red), wider, and knocks back — the windup
/// to a stagger-break/execution.
/mob/living/verb/wind_up_heavy()
	set name = "Wind Up Heavy Blow"
	set category = "IC.Game"
	set src = usr
	var/obj/item/weapon = get_active_hand()
	if(!istype(weapon) || !weapon.force || (weapon.flags & NOBLUDGEON))
		to_chat(src, span_warning("You need a weapon in hand to wind up a heavy blow."))
		return
	queued_heavy = TRUE
	// Swing at whatever living thing is in front of us right now.
	var/turf/front = get_step(src, dir)
	var/mob/living/target = front ? (locate(/mob/living) in front) : null
	if(target)
		begin_melee_swing(target, weapon)
	else
		to_chat(src, span_notice("You wind up a heavy blow — your next strike will be charged."))

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

/// The 3-tile frontal arc regardless of weapon — a charged heavy always cleaves.
/mob/living/proc/get_swing_tiles_wide(atom/target)
	var/turf/origin = get_turf(src)
	if(!origin)
		return list()
	var/swing_dir = get_dir(src, target) || dir
	var/list/turf/tiles = list()
	for(var/d in list(swing_dir, turn(swing_dir, 45), turn(swing_dir, -45)))
		var/turf/T = get_step(origin, d)
		if(T && !(T in tiles))
			tiles += T
	return tiles

/// Run a full windup -> swing -> recovery aimed at `target` (a mob or a turf) with `weapon`.
/// The swing resolves against whoever stands in the telegraphed tiles, so aiming at a tile hits
/// anything on it. Returns TRUE if a swing was committed (whether or not it connected), FALSE if
/// it couldn't start or cancelled.
/// Called on a bare LEFT mouse-press. If this is a real melee swing (HURT intent, a bludgeoning
/// weapon in hand, an adjacent living target), kick it off on the press and return TRUE so the client
/// marks the press as a held attack — the swing then stays wound up until release (see the hold-to-
/// strike loop in begin_melee_swing). Returns FALSE for anything that isn't a swing, so the normal
/// release-click handles it (UI, items, ranged, non-adjacent, …).
/mob/living/proc/dq_try_held_attack(atom/target)
	if(a_intent == I_GRAB) // GRAB keeps its grab path; every other intent swings (matches item_attack)
		return FALSE
	if(target == src)
		return FALSE
	// Swing at a living mob OR an adjacent tile (a directional / whiff swing into empty space).
	if(!isliving(target) && !isturf(target))
		return FALSE
	if(!Adjacent(target))
		return FALSE
	if(!checkClickCooldown()) // respect the post-swing recovery — the MouseDown path bypasses ClickOn's check
		return FALSE
	if(is_swinging || world.time < melee_locked_until)
		return FALSE
	var/obj/item/weapon = get_active_hand()
	if(!istype(weapon) || !weapon.force || (weapon.flags & NOBLUDGEON))
		// No bludgeoning weapon in hand. A bare-handed swing isn't a held attack, but a finisher on
		// a target you've already broken open still lands — so executions work unarmed too. Anything
		// else falls through to the normal release-click (UI, shoves, non-lethal punches, …).
		if(a_intent == I_HURT && isliving(target) && can_execute(target))
			perform_execution(target, null)
			return TRUE
		return FALSE
	INVOKE_ASYNC(src, PROC_REF(begin_melee_swing), target, weapon) // begin_melee_swing sleeps on the windup
	return TRUE

/mob/living/proc/begin_melee_swing(atom/target, obj/item/weapon)
	if(is_swinging)
		return FALSE
	if(blocking) // a raised guard commits you — no attacking until it drops (and a beat after)
		return FALSE
	if(world.time < melee_locked_until || world.time < l_move_time + dq_move_attack_lock())
		return FALSE
	if(QDELETED(target) || QDELETED(weapon))
		return FALSE
	if(!weapon.force || (weapon.flags & NOBLUDGEON))
		return FALSE
	if(!Adjacent(target))
		return FALSE

	// An opponent we've already broken down (staggered open, downed, or grabbed) gets
	// finished with a cinematic execution instead of a normal swing.
	if(a_intent == I_HURT && isliving(target) && can_execute(target))
		return perform_execution(target, weapon)

	// Charged heavy: queued explicitly (Wind Up verb), or flowing out of a fresh riposte.
	// A bigger, slower, telegraphed blow that sweeps wide, knocks back, and shatters poise.
	charging_heavy = queued_heavy || (world.time < riposte_until)
	queued_heavy = FALSE

	var/list/mods = get_intent_combat_mods()
	// Fatigue: the more drained you are, the slower you wind up and recover.
	var/fatigue_mult = 1 + (1 - stamina / max(max_stamina, 1)) * STAMINA_FATIGUE_SCALE
	// Combo: a swing started soon after a landed hit (or a parry) winds up faster.
	var/comboing = world.time < combo_until
	// A heavy winds up notably slower (more telegraph); a normal swing is unchanged.
	var/heavy_windup = charging_heavy ? 1.6 : 1
	var/windup = max(2, round(weapon.get_melee_windup() * mods[INTENT_MOD_WINDUP] * fatigue_mult * heavy_windup * (comboing ? COMBO_WINDUP_MULT : 1)))
	// A charged heavy always sweeps the 3-tile arc (cleave), even with a small weapon.
	var/list/turf/swing_tiles = charging_heavy ? get_swing_tiles_wide(target) : get_swing_tiles(target, weapon)
	if(!length(swing_tiles))
		charging_heavy = FALSE
		return FALSE

	is_swinging = TRUE
	feint_requested = FALSE
	face_atom(target)
	// A held left-press swing stays wound up until release (hold-to-charge); set in MouseDown
	// before this proc starts, so it's reliably visible here.
	var/is_held = (client && client.held_attack_target == target)

	// Exertion: bigger weapons and aggressive intents cost more stamina (Help is cheap).
	var/swing_cost = round(STAMINA_COST_SWING * (weapon.w_class / ITEMSIZE_NORMAL) * mods[INTENT_MOD_DAMAGE])
	adjust_stamina(-swing_cost)

	// Telegraph the targeted tiles for the duration of the windup (auto-clears), and warn any AI
	// mobs standing in them so they can dodge or brace. Charged heavies read red (unblockable);
	// a normal swing is a yellow parryable telegraph.
	var/telegraph_kind = charging_heavy ? DQ_TELEGRAPH_DODGE : DQ_TELEGRAPH_PARRY
	for(var/turf/T as anything in swing_tiles)
		dq_telegraph(T, windup, telegraph_kind)
		for(var/mob/living/threatened in T)
			if(threatened != src && threatened.ai_brain)
				threatened.ai_brain.notify_incoming_attack(src, windup)

	// Windup pose: a held swing rears back ONCE and HOLDS it (no return); a normal swing does the
	// quick pull-back-and-return.
	if(is_held)
		dq_rear_back_pose()
	else
		do_windup_animation(target, windup)

	// Wait out the windup. do_after cancels if WE move, drop the weapon, or get incapacitated.
	// Passing target = src means a dodging victim does NOT cancel it (they just leave the tiles).
	// The extra_check cancels on a feint (right-click during the windup).
	if(!do_after(src, windup, target = src, progress = FALSE, hidden = TRUE, interaction_key = "melee_swing", extra_checks = CALLBACK(src, PROC_REF(swing_not_feinted))))
		if(is_held)
			dq_settle_pose()
		if(feint_requested)
			adjust_stamina(round(swing_cost * 0.75)) // a feint hands most of the wasted effort back
		feint_requested = FALSE // clear it here too (mirrors the mid-hold path), never leak into the next swing
		charging_heavy = FALSE
		is_swinging = FALSE
		return FALSE

	// Re-validate the weapon is still in hand after the windup.
	if(QDELETED(weapon) || get_active_hand() != weapon)
		if(is_held)
			dq_settle_pose()
		charging_heavy = FALSE
		is_swinging = FALSE
		return FALSE

	// Hold-to-strike: a held swing stays reared back until the player RELEASES the button — then it
	// strikes. Holding past DQ_SWING_HEAVY_CHARGE charges it into a heavy (stronger, wider, knockback).
	// A right-click during the hold FEINTS (cancel, no strike). Capped at DQ_SWING_MAX_HOLD; moving /
	// losing the weapon / the target leaving reach cancels it. A quick tap just runs 0 iterations here.
	if(is_held)
		var/hold_start = world.time
		while(client && client.held_attack_target == target && world.time < hold_start + DQ_SWING_MAX_HOLD)
			if(feint_requested || QDELETED(target) || get_active_hand() != weapon || (isliving(target) && !Adjacent(target)) || blocking || incapacitated())
				break
			if(!charging_heavy && world.time >= hold_start + DQ_SWING_HEAVY_CHARGE)
				charging_heavy = TRUE
				visible_message(span_danger("\The [src] winds up a heavy blow!"))
				playsound(src, 'sound/weapons/parry.ogg', 30, 1, -1)
				// Brief red cleave telegraph (short, so it doesn't linger after the strike).
				for(var/turf/HT as anything in get_swing_tiles_wide(target))
					dq_telegraph(HT, windup, DQ_TELEGRAPH_DODGE)
					for(var/mob/living/threatened in HT)
						if(threatened != src && threatened.ai_brain)
							threatened.ai_brain.notify_incoming_attack(src, windup)
			sleep(1)
		if(feint_requested) // feinted mid-hold — refund most of the effort, no strike
			dq_settle_pose()
			feint_requested = FALSE
			adjust_stamina(round(swing_cost * 0.75))
			charging_heavy = FALSE
			is_swinging = FALSE
			return FALSE
		if(QDELETED(weapon) || get_active_hand() != weapon)
			dq_settle_pose()
			charging_heavy = FALSE
			is_swinging = FALSE
			return FALSE
		// Hand the reared-back pose straight into the strike's lunge (instant clear, no settle tween).
		dq_clear_pose()
		// Re-aim at the target's current position for the strike on release.
		face_atom(target)
		swing_tiles = charging_heavy ? get_swing_tiles_wide(target) : get_swing_tiles(target, weapon)

	// Swing: lunge + whoosh, then resolve against whoever is in the tiles NOW.
	do_attack_animation(target)
	playsound(src, charging_heavy ? 'sound/weapons/heavysmash.ogg' : 'sound/weapons/punchmiss.ogg', charging_heavy ? 55 : 40, 1, -1)
	var/zone = zone_sel?.selecting || BP_TORSO // fall back to chest (clientless mobs have no HUD doll)
	// A charged heavy hits harder and shatters more poise; Heavy Hands adds to the heavy.
	var/dmg_mult = mods[INTENT_MOD_DAMAGE] * (charging_heavy ? 1.6 * perk_mult(DQ_PERK_FX_HEAVY_DMG) : 1)
	var/landed = FALSE // an unparried hit connected — gates the combo chain
	for(var/turf/T as anything in swing_tiles)
		for(var/mob/living/victim in T)
			if(victim == src)
				continue
			var/hit_zone = victim.resolve_item_attack(weapon, src, zone)
			if(hit_zone)
				weapon.apply_hit_effect(victim, src, hit_zone, dmg_mult)
				landed = TRUE
				// Build the victim's poise — a charged heavy strips a big chunk.
				victim.add_stagger(round(weapon.force * dmg_mult) + (charging_heavy ? DQ_STAGGER_HEAVY : 0), src)
				src.apply_wound_effect(victim, weapon, hit_zone) // limb-targeted effect, if any
				if(charging_heavy && isliving(victim)) // knock the struck target back a tile
					resolve_shove(victim)
				else if(isliving(victim) && has_perk(/datum/perk/body/str_force_of_will) && prob(DQ_PERK_FORCE_OF_WILL_PROB))
					resolve_shove(victim) // Force of Will: your melee strikes can knock enemies back.

	var/recovery
	if(landed && !charging_heavy)
		// Flow into a follow-up: open the combo window and cut (but don't skip) the recovery.
		// Agile Strikes widens the window so you keep your rhythm flowing between enemies.
		combo_until = world.time + COMBO_WINDOW + (has_perk(/datum/perk/body/str_agile_strikes) ? COMBO_WINDOW : 0)
		recovery = max(2, round(weapon.get_melee_recovery() * mods[INTENT_MOD_RECOVERY] * fatigue_mult * COMBO_RECOVERY_MULT))
	else
		// A heavy, a whiff, or a parry: full (fatigue-scaled, heavier-for-a-heavy) recovery, combo broken.
		combo_until = 0
		recovery = max(2, round(weapon.get_melee_recovery() * mods[INTENT_MOD_RECOVERY] * fatigue_mult * (charging_heavy ? 1.5 : 1)))
	setClickCooldown(recovery)
	charging_heavy = FALSE
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
	if(world.time < melee_locked_until || world.time < l_move_time + dq_move_attack_lock())
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
		dq_telegraph(front, windup, DQ_TELEGRAPH_DODGE) // a shove goes THROUGH a guard — read as unblockable
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
	// Shove-resistance perks, strongest first.
	if(victim.has_perk(/datum/perk/body/str_juggernaut)) // immune to knockback entirely
		victim.visible_message(span_warning("\The [src] shoves \the [victim], who doesn't move an inch!"))
		return
	var/standing_firm = world.time > victim.l_move_time + DQ_SHOVE_LOCK // hasn't moved this beat
	if(standing_firm && (victim.has_perk(/datum/perk/body/str_wall_of_meat) || victim.has_perk(/datum/perk/body/end_rooted)))
		victim.visible_message(span_warning("\The [src] shoves \the [victim], but they hold their ground!"))
		return
	if(victim.has_perk(/datum/perk/body/str_iron_grip) && prob(DQ_PERK_IRON_GRIP_RESIST)) // Iron Grip: shrug off a shove
		victim.visible_message(span_warning("\The [victim] keeps their footing against \the [src]'s shove!"))
		return

	var/shove_dir = get_dir(src, victim)
	if(!shove_dir)
		shove_dir = dir
	if(victim.blocking)
		victim.end_block() // the shove goes through the guard and drops it

	// Explicit density check rather than Move()'s return — mobs would otherwise swap places
	// instead of colliding, and we want "shoved into someone" to knock them down.
	var/turf/dest = get_step(victim, shove_dir)
	var/blocked = !dest || dest.density
	var/mob/living/slammed_into = null
	if(!blocked)
		for(var/atom/movable/obstacle in dest)
			if(obstacle.density && obstacle != victim)
				blocked = TRUE
				if(isliving(obstacle))
					slammed_into = obstacle
				break

	if(blocked)
		// Slammed into a wall, object, or another body — knocked down + poise-staggered.
		victim.Weaken(DQ_SHOVE_KNOCKDOWN)
		victim.add_stagger(DQ_STAGGER_SHOVE, src)
		if(slammed_into)
			// Domino: the body we slammed them into goes down too. One system for PvP and PvE —
			// a player shoving a mob into its packmates, or a mob shoving a player into another.
			slammed_into.Weaken(DQ_SHOVE_KNOCKDOWN)
			slammed_into.add_stagger(DQ_STAGGER_SHOVE, src)
			slammed_into.melee_locked_until = max(slammed_into.melee_locked_until, world.time + DQ_SHOVE_LOCK)
			victim.visible_message(span_danger("\The [src] shoves \the [victim] into \the [slammed_into], knocking them both sprawling!"))
		else
			victim.visible_message(span_danger("\The [src] shoves \the [victim] into the way, knocking them down!"))
		playsound(victim, 'sound/effects/bodyfall1.ogg', 50, 1, -1)
	else
		victim.Move(dest, shove_dir) // dest is clear of dense atoms, so this won't swap
		victim.visible_message(span_warning("\The [src] shoves \the [victim] back!"))
		// Crusher / Juggernaut: your shoves rock the enemy's guard even on a clean push.
		if(has_perk(/datum/perk/body/str_crusher) || has_perk(/datum/perk/body/str_juggernaut))
			victim.add_stagger(DQ_STAGGER_SHOVE, src)

	victim.melee_locked_until = max(victim.melee_locked_until, world.time + DQ_SHOVE_LOCK)
	victim.setMoveCooldown(DQ_SHOVE_LOCK)
