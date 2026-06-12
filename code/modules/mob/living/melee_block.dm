// Melee block / parry / feint, intent stances, and the dedicated attack lockout.
//
// Right-click with a melee weapon raises a guard, locking your facing while it's up. Tap for a
// one-second guard; hold the button to keep it up (press/release ride on client MouseDown/MouseUp,
// with the click as a fallback). The guard has two phases:
//   - A tight parry window at the very start: catch an attack here to fully negate it, stagger the
//     attacker, and open a riposte (your next attacks are briefly unblockable). The skill option.
//   - The block tail (the rest of the second): catch an attack here for a soft block — only half the
//     damage is stopped, and it costs more stamina than a swing. A bail-out for a mistimed parry.
// A guard that expires having caught nothing whiffs: the blocker is locked out and open, which a
// feint baits. A guard cooldown after every guard stops them being fished. Right-click during your
// own windup feints (cancels the swing). On Disarm intent, right-click shoves instead of guarding
// (see begin_melee_shove). Each a_intent trades damage vs windup/recovery/move speed.
//
// A parry cancels the guard animation with a counter-lunge. Parrying is free; only the soft block
// spends stamina. Block/parry plug into the existing shield pipeline (check_shields -> here),
// applying to every incoming melee attack against a human, not just the phased-melee swing.

/mob/living
	/// TRUE while a raised guard is active (set by melee_rightclick, cleared in end_block).
	var/blocking = FALSE
	/// world.time the guard's block tail ends (the whole guard is over).
	var/block_window_until = 0
	/// world.time the tight parry phase ends; an attack caught before this staggers the attacker.
	var/parry_until = 0
	/// world.time the current guard was raised (a tapped guard lasts at least DQ_BLOCK_WINDOW from here).
	var/block_start_at = 0
	/// TRUE while the mouse is held down on a raised guard; the guard persists until release.
	var/block_held = FALSE
	/// Set TRUE when the guard intercepts anything (parry or block) — suppresses the whiff penalty.
	var/block_used = FALSE
	/// world.time a soft block flagged the incoming hit for 50% reduction (read same-tick by the
	/// damage application, then cleared). Set only by the block tail, never a parry.
	var/block_soft_at = 0
	/// world.time until which this mob's melee attacks are unblockable (set by landing a parry).
	var/riposte_until = 0
	/// Set by a right-click during a windup; the swing's do_after reads it and cancels (a feint).
	var/feint_requested = FALSE
	/// world.time until which this mob can't start a melee swing (move lock / block whiff / stagger).
	var/melee_locked_until = 0
	/// world.time until which this mob can't raise another guard (anti-spam after a guard ends).
	var/guard_cooldown_until = 0

// ---------------------------------------------------------------------------
// Per-intent combat stances.
// ---------------------------------------------------------------------------

/// Returns the combat modifier row for this mob's intent:
/// list(damage_mult, windup_mult, recovery_mult, move_slowdown). Index with the INTENT_MOD_* defines.
/mob/proc/get_intent_combat_mods()
	var/static/list/by_intent = list(
		I_HURT   = list(1.0,  1.0, 1.0, 1.5),
		I_DISARM = list(0.55, 0.7, 0.8, 0.5),
		I_HELP   = list(0.3,  0.5, 0.6, 0.0),
		I_GRAB   = list(1.0,  1.0, 1.0, 0.0),
	)
	return by_intent[a_intent] || by_intent[I_HURT]

// ---------------------------------------------------------------------------
// Right-click: feint a swing, else raise a block.
// ---------------------------------------------------------------------------

/// BYOND's right-click context menu is suppressed only while holding a melee weapon, so a bare
/// right-click is a guard then and a normal context menu otherwise. Called whenever the held item
/// might have changed (hand HUD updates, Login).
/mob/living/proc/refresh_combat_popup_menus()
	if(!client || client.buildmode)
		return
	var/obj/item/weapon = get_active_hand()
	client.show_popup_menus = !(istype(weapon) && weapon.force && !(weapon.flags & NOBLUDGEON))

/// `held` is TRUE when the call comes from a mouse-press (MouseDown) — the guard then stays up
/// until release; FALSE from the click fallback raises a self-timed guard.
/mob/living/proc/melee_rightclick(atom/A, held = FALSE)
	// Mid-windup right-click = feint: the swing's do_after extra-check cancels it.
	if(is_swinging)
		feint_requested = TRUE
		return
	if(blocking || incapacitated())
		return
	var/obj/item/weapon = get_active_hand()
	if(!istype(weapon) || !weapon.force || (weapon.flags & NOBLUDGEON))
		return
	if(A == weapon)
		return // right-clicking your own held item is attack_self_secondary, not a guard/shove
	if(A && A != src && isatom(A))
		face_atom(A) // turn toward the threat

	// On Disarm intent, right-click is a shove instead of a block. (Left-click stays a normal swing.)
	if(a_intent == I_DISARM)
		var/mob/living/shove_target
		if(isliving(A) && A != src && Adjacent(A))
			shove_target = A
		else
			var/turf/front = get_step(src, dir) // nobody clicked directly — grab who's in front
			if(front)
				shove_target = locate(/mob/living) in front
		if(shove_target && shove_target != src)
			begin_melee_shove(shove_target, weapon) // validates locks/adjacency itself
		return

	// Any other intent: raise a block.
	if(world.time < melee_locked_until || world.time < l_move_time + DQ_MOVE_ATTACK_LOCK || world.time < guard_cooldown_until)
		return
	start_block(weapon, held)

/mob/living/proc/start_block(obj/item/weapon, held = FALSE)
	blocking = TRUE
	block_used = FALSE
	block_held = held
	block_start_at = world.time
	parry_until = world.time + DQ_PARRY_WINDOW
	// A held guard stays up until release (capped by DQ_BLOCK_MAX); a tapped one self-times out.
	block_window_until = world.time + (held ? DQ_BLOCK_MAX : DQ_BLOCK_WINDOW)
	facing_dir = dir // committed: facing is locked toward the guard while it's up
	// Visible guard hitch: pull back toward the tile we're facing.
	do_windup_animation(get_step(src, dir) || src, DQ_BLOCK_WINDOW)
	playsound(src, 'sound/weapons/parry.ogg', 35, 1, -1)
	visible_message(span_notice("\The [src] raises \a [weapon] in a guard."), span_notice("You raise your guard with \the [weapon]. Time a parry, or hold to block."))
	addtimer(CALLBACK(src, PROC_REF(end_block)), held ? DQ_BLOCK_MAX : DQ_BLOCK_WINDOW, TIMER_UNIQUE | TIMER_OVERRIDE)

/// Called when the guarding mouse button is released. Drops the guard, but never before it has
/// been up for the minimum tap duration, so a quick tap still gets its parry window.
/mob/living/proc/release_block()
	if(!blocking)
		return
	block_held = FALSE
	var/min_end = block_start_at + DQ_BLOCK_WINDOW
	if(world.time >= min_end)
		end_block()
	else
		addtimer(CALLBACK(src, PROC_REF(end_block)), min_end - world.time, TIMER_UNIQUE | TIMER_OVERRIDE)

/mob/living/proc/end_block()
	if(!blocking)
		return
	if(!block_used)
		// The guard ended having caught nothing — a fished parry, so eat an attack + move lockout
		// (a feint baits exactly this).
		melee_locked_until = max(melee_locked_until, world.time + DQ_BLOCK_WHIFF_LOCK)
		setMoveCooldown(DQ_BLOCK_WHIFF_LOCK)
		to_chat(src, span_warning("Your guard drops, having caught nothing — you're wide open!"))
	// Brief cooldown after every guard so they can't be fished back-to-back.
	guard_cooldown_until = world.time + DQ_GUARD_COOLDOWN
	facing_dir = null // release the facing lock
	blocking = FALSE
	block_held = FALSE
	block_window_until = 0
	parry_until = 0
	block_used = FALSE

/// Called from check_shields. Returns TRUE only when the attack is FULLY negated (a parry);
/// returns FALSE for a soft block (which flags the hit for 50% reduction downstream and lets it
/// through) and when there's no guard. A parry also staggers the attacker (a riposte window).
/mob/living/proc/melee_block_intercepts(atom/damage_source, mob/attacker)
	if(!blocking || world.time >= block_window_until)
		return FALSE
	// An attacker riposting off their own parry is unblockable — the hit goes through any guard.
	if(isliving(attacker))
		var/mob/living/living_attacker = attacker
		if(living_attacker.riposte_until > world.time)
			living_attacker.riposte_until = 0
			return FALSE
	// Melee + adjacent + not-incapacitated, matching the shield/weapon parry gate (no projectiles).
	if(!attacker || !default_parry_check(src, attacker, damage_source))
		return FALSE
	// Directional: you only guard what you're facing. The attacker must sit in the front arc of
	// the way you're guarding (the faced tile and its two diagonals), so flanks and rear get through.
	var/attack_dir = get_dir(src, attacker)
	if(attack_dir && !(attack_dir == dir || attack_dir == turn(dir, 45) || attack_dir == turn(dir, -45)))
		return FALSE
	block_used = TRUE // caught something either way — no whiff penalty
	if(world.time < parry_until)
		// True parry: fully negate, stagger the attacker, and open the riposte — your follow-up is
		// both faster (combo windup) and unblockable.
		riposte_until = world.time + DQ_RIPOSTE_WINDOW
		combo_until = world.time + COMBO_WINDOW
		do_attack_animation(attacker) // a snappy counter-lunge that cancels the held-guard animation
		visible_message(span_danger("\The [src] parries \the [attacker]'s attack!"), span_danger("You parry \the [attacker]'s attack! Strike now — your riposte is unblockable."))
		playsound(src, 'sound/weapons/parry.ogg', 50, 1, -1)
		if(isliving(attacker))
			var/mob/living/staggered = attacker
			staggered.melee_locked_until = max(staggered.melee_locked_until, world.time + DQ_PARRY_STAGGER)
			staggered.setMoveCooldown(DQ_PARRY_STAGGER)
		return TRUE
	// Soft block: only half the hit is stopped (flag it for the damage application), and it costs
	// more stamina than the swing it's eating — a bad trade you take when you mistimed the parry.
	block_soft_at = world.time
	var/obj/item/weapon = istype(damage_source, /obj/item) ? damage_source : null
	var/wsize = weapon ? weapon.w_class : ITEMSIZE_NORMAL
	var/list/attacker_mods = attacker.get_intent_combat_mods()
	var/attack_cost = round(STAMINA_COST_SWING * (wsize / ITEMSIZE_NORMAL) * attacker_mods[INTENT_MOD_DAMAGE])
	adjust_stamina(-round(attack_cost * 1.2))
	visible_message(span_warning("\The [src] blocks \the [attacker]'s attack, staggering under it!"))
	playsound(src, 'sound/weapons/genhit.ogg', 35, 1, -1)
	return FALSE
