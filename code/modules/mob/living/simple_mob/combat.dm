// Does a melee attack.
/// `stance` is the stance the melee attack is made in (the player's input or the AI brain's choice).
/mob/living/simple_mob/proc/attack_target(atom/A, stance = I_HURT)

	if(!A.Adjacent(src))
		return ATTACK_FAILED
	var/turf/their_T = get_turf(A)

	face_atom(A)

	if(melee_attack_delay)
		melee_pre_animation(A)
		handle_attack_delay(A, melee_attack_delay, PROC_REF(attack_target_strike), their_T, stance)
		return ATTACK_SUCCESSFUL // the real result is known once the telegraph ends
	return attack_target_strike(A, their_T, stance)

/// The melee attack itself, after any telegraph.
/mob/living/simple_mob/proc/attack_target_strike(atom/A, turf/their_T, stance = I_HURT)
	// Cooldown testing is done at click code (for players) and interface code (for AI).
	// Simplemob Injury
	if(injury_enrages)
		setClickCooldown(get_attack_speed() - ((injury_level / 2) SECONDS)) // Increase how fast we can attack by our injury level / 2
	else
		setClickCooldown(get_attack_speed() + ((injury_level / 2) SECONDS)) // Delay how fast we can attack by our injury level / 2
	// Stop: Simplemob Injury

	// Returns a value, but will be lost if
	. = do_attack(A, their_T, stance)

	if(melee_attack_delay)
		melee_post_animation(A)

// This does the actual attack.
// This is a seperate proc for the purposes of attack animations.
// A is the thing getting attacked, T is the turf A is/was on when attack_target was called.
/mob/living/simple_mob/proc/do_attack(atom/A, turf/T, stance = I_HURT)
	face_atom(A)
	var/missed = FALSE
	if(!isturf(A) && !(is_in_holder(A, T)) ) // Turfs don't contain themselves so checking contents is pointless if we're targeting a turf.
		missed = TRUE
	else if(!T.AdjacentQuick(src))
		missed = TRUE

	if(missed) // Most likely we have a slow attack and they dodged it or we somehow got moved.
		add_attack_logs(src, A, "Animal-attacked (dodged)", admin_notify = FALSE)
		play_sfx(src, SFX_WEAPONS_PUNCHMISS, 3, extrarange = 0)
		act_message(src, null, null, MSG_OTHERS(span_warning("%U% misses their attack.")))
		return FALSE

	var/damage_to_do = rand(melee_damage_lower, melee_damage_upper)

	damage_to_do = apply_bonus_melee_damage(A, damage_to_do)

	damage_to_do *= factor(BF_MELEE_DAMAGE)

	if(isliving(A)) // Check defenses.
		var/mob/living/L = A

		if(prob(melee_miss_chance))
			add_attack_logs(src, L, "Animal-attacked (miss)", admin_notify = FALSE)
			do_attack_animation(src)
			play_sfx(src, SFX_WEAPONS_PUNCHMISS, 3, extrarange = 0)
			return FALSE // We missed.

		if(ishuman(L))
			var/mob/living/carbon/human/H = L
			if(H.check_shields(damage = damage_to_do, damage_source = src, attacker = src, def_zone = null, attack_text = "the attack"))
				return FALSE // We were blocked.

	if(apply_attack(A, damage_to_do, stance))
		apply_melee_effects(A, stance)
		if(attack_sound)
			playsound(src, attack_sound, 75, 1)

	return TRUE

// Generally used to do the regular attack.
// Override for doing special stuff with the direct result of the attack.
/mob/living/simple_mob/proc/apply_attack(atom/A, damage_to_do, stance = I_HURT)
	return generic_hit(A, src, damage_to_do, pick(attacktext))

// Override for special effects after a successful attack, like injecting poison or stunning the target.
/mob/living/simple_mob/proc/apply_melee_effects(atom/A, stance = I_HURT)
	return

// Override to modify the amount of damage the mob does conditionally.
// This must return the amount of outgoing damage.
// Note that this is done before mob modifiers scale the damage.
/mob/living/simple_mob/proc/apply_bonus_melee_damage(atom/A, damage_amount)
	return damage_amount

//The actual top-level ranged attack proc
/mob/living/simple_mob/proc/shoot_target(atom/A)
	if(!istype(A) || QDELETED(A))
		return

	// Simplemob Injury
	if(injury_enrages)
		setClickCooldown(get_attack_speed() - ((injury_level / 2) SECONDS)) // Increase how fast we can attack by our injury level / 2
	else
		setClickCooldown(get_attack_speed() + ((injury_level / 2) SECONDS)) // Delay how fast we can attack by our injury level / 2
	// Stop: Simplemob Injury

	face_atom(A)

	if(ranged_attack_delay)
		ranged_pre_animation(A)
		handle_attack_delay(A, ranged_attack_delay, PROC_REF(shoot_target_fire))
		return TRUE
	return shoot_target_fire(A)

/// The ranged attack itself, after any telegraph.
/mob/living/simple_mob/proc/shoot_target_fire(atom/A)
	if(needs_reload)
		if(reload_count >= reload_max)
			try_reload()
			return FALSE

	if(ranged_cooldown_time) //If you have a non-zero number in a mob's variables, this pattern begins.
		if(COOLDOWN_FINISHED(src, ranged_cooldown)) //Further down, a timer keeps adding to the ranged_cooldown variable automatically.
			visible_message(span_danger(span_bold("\The [src]") + " fires at \the [A]!")) //Leave notice of shooting.
			shoot(A) //Perform the shoot action
			if(casingtype) //If the mob is designated to leave casings...
				new casingtype(loc) //... leave the casing.
			EXPIRY_SET(src, ranged_cooldown, ranged_cooldown_time + ((injury_level / 2) SECONDS), CLOCK_WORLD) //Special addition here. This is a timer. Keeping updating the time after shooting. Add that ranged cooldown time specified in the mob to the world time.
		return TRUE

	act_message(src, A, null, MSG_OTHERS(span_danger(span_bold("%U%") + " fires at %T%!")))
	shoot(A)
	if(casingtype)
		new casingtype(loc)

	if(ranged_attack_delay)
		ranged_post_animation(A)

	return TRUE

// Shoot a bullet at something.
/mob/living/simple_mob/proc/shoot(atom/A)
	if(A == get_turf(src))
		return

	face_atom(A)

	var/obj/item/projectile/P = new projectiletype(src.loc)
	if(!P)
		return

	// If the projectile has its own sound, use it.
	// Otherwise default to the mob's firing sound.
	playsound(src, P.fire_sound ? P.fire_sound : projectilesound, 80, 1)

	// For some reason there isn't an argument for accuracy, so access the projectile directly instead.
	// Also, placing dispersion here instead of in forced_spread will randomize the chosen angle between dispersion and -dispersion in fire() instead of having to do that here.
	P.accuracy += calculate_accuracy()
	P.dispersion += calculate_dispersion()

	P.launch_projectile(target = A, target_zone = null, user = src, params = null, angle_override = null, forced_spread = 0)
	if(needs_reload)
		reload_count++


/mob/living/simple_mob/proc/try_reload()
	task_timed(src, reload_time, target = src, receiver = src, on_done = PROC_REF(reload_done), busy = src)

/mob/living/simple_mob/proc/reload_done()
	if(reload_sound)
		playsound(src, reload_sound, 70, 1)
	reload_count = 0

/mob/living/simple_mob/proc/calculate_dispersion()
	. = projectile_dispersion // Start with the basic var.

	// Body factors change dispersion. This makes simple_mobs respect that.
	. += factor(BF_DISPERSION)

	// Make sure we don't go under zero dispersion.
	. = max(., 0)

/mob/living/simple_mob/proc/calculate_accuracy()
	. = projectile_accuracy // Start with the basic var.

	// Body factors make it harder or easier to hit things.
	. += factor(BF_ACCURACY)

// Can we currently do a special attack?
/mob/living/simple_mob/proc/can_special_attack(atom/A)
	// Validity check.
	if(!istype(A))
		return FALSE

	// Ability check.
	if(isnull(special_attack_min_range) || isnull(special_attack_max_range))
		return FALSE

	// Distance check.
	var/distance = get_dist(src, A)
	if(distance < special_attack_min_range || distance > special_attack_max_range)
		return FALSE

	// Cooldown check.
	if(!isnull(special_attack_cooldown) && !COOLDOWN_FINISHED(src, special_attack_cooldown_until))
		return FALSE

	// Charge check.
	if(!isnull(special_attack_charges) && special_attack_charges <= 0)
		return FALSE

	return TRUE

// Should we do one? Used to make the AI not waste their special attacks. Only checked for AI. Players are free to screw up on their own.
/mob/living/simple_mob/proc/should_special_attack(atom/A)
	return TRUE

// Special attacks, like grenades or blinding spit or whatever.
// Don't override this, override do_special_attack() for your blinding spit/etc.
/mob/living/simple_mob/proc/special_attack_target(atom/A, stance = I_HURT)
	face_atom(A)

	if(special_attack_delay)
		special_pre_animation(A)
		handle_attack_delay(A, special_attack_delay, PROC_REF(special_attack_fire), stance)
		return TRUE
	return special_attack_fire(A, stance)

/// The special attack itself, after any telegraph.
/mob/living/simple_mob/proc/special_attack_fire(atom/A, stance)
	COOLDOWN_START(src, special_attack_cooldown_until, special_attack_cooldown)
	if(do_special_attack(A, stance))
		if(special_attack_charges)
			special_attack_charges -= 1
		. = TRUE
	else
		. = FALSE

	if(special_attack_delay)
		special_post_animation(A)

/// Missile rack: fires `count` rockets of `rocket_type` at target one second apart
/// (after a half-second deploy), then retracts with `retract_message` and calls
/// `then_proc(target)` if given.
/mob/living/simple_mob/proc/rocket_volley(atom/target, rocket_type, count, retract_message, then_proc)
	after(src, 0.5 SECONDS, PROC_REF(rocket_volley_step), with = list(target, rocket_type, count, retract_message, then_proc, 1))

/mob/living/simple_mob/proc/rocket_volley_step(atom/target, rocket_type, count, retract_message, then_proc, i)
	var/turf/T = get_turf(target)
	if(T)
		act_message(src, null, null, MSG_OTHERS(span_warning("%U% fires a rocket into the air!")))
		play_sfx(src, SFX_WEAPONS_RPG, volume = 70)
		face_atom(T)
		var/obj/item/projectile/arc/explosive_rocket/rocket = new rocket_type(loc)
		rocket.old_style_target(T, src)
		rocket.fire()
	if(i < count)
		after(src, 1 SECOND, PROC_REF(rocket_volley_step), with = list(target, rocket_type, count, retract_message, then_proc, i + 1))
		return
	after(src, 1 SECOND, PROC_REF(rocket_volley_end), with = list(target, retract_message, then_proc))

/mob/living/simple_mob/proc/rocket_volley_end(atom/target, retract_message, then_proc)
	visible_message(span_warning(retract_message))
	play_sfx(src, SFX_EFFECTS_TURRET_MOVE2)
	if(then_proc)
		call(src, then_proc)(target)

// Override this for the actual special attack. `stance` is the stance the attacker chose (player input or AI).
/mob/living/simple_mob/proc/do_special_attack(atom/A, stance)
	return FALSE

// Waits out an attack telegraph, then calls `then_proc(A, extra)` on src.
// Also makes sure the AI doesn't do anything stupid in the middle of the delay.
/// Extra arguments after `then_proc` are passed on to it after `A`.
/mob/living/simple_mob/proc/handle_attack_delay(atom/A, delay_amount, then_proc, ...)
	ai_busy_begin()
	// Click delay modifiers also affect telegraphing time.
	// This means berserked enemies will leave less time to dodge.
	var/true_attack_delay = delay_amount * factor(BF_ATTACK_SPEED)

	setClickCooldown(true_attack_delay) // Insurance against a really long attack being longer than default click delay.

	if(!after(src, true_attack_delay, PROC_REF(attack_delay_done), with = list(then_proc, list(A) + args.Copy(4))))
		ai_busy_end()

/mob/living/simple_mob/proc/attack_delay_done(then_proc, list/call_args)
	ai_busy_end()
	var/atom/A = call_args[1]
	if(QDELETED(A))
		return
	if(then_proc)
		call(src, then_proc)(arglist(call_args))
// Override these four for special custom animations (like the GOLEM).
/mob/living/simple_mob/proc/melee_pre_animation(atom/A)
	do_windup_animation(A, melee_attack_delay)

/mob/living/simple_mob/proc/melee_post_animation(atom/A)

/mob/living/simple_mob/proc/ranged_pre_animation(atom/A)
	do_windup_animation(A, ranged_attack_delay) // Semi-placeholder.

/mob/living/simple_mob/proc/ranged_post_animation(atom/A)

/mob/living/simple_mob/proc/special_pre_animation(atom/A)
	do_windup_animation(A, special_attack_delay) // Semi-placeholder.

/mob/living/simple_mob/proc/special_post_animation(atom/A)
