// Status counters (doc/mob_life_architecture.md §4.7, §4.9).
//
// Stun, weaken, paralysis, sleep, confusion, blindness, blur, drugs, deafness, drowsiness,
// silence, stuttering and slurring are /datum/status_effect/counter subtypes. A counter
// exists only while it runs: it owns its duration through the status effect's own
// `duration` (the base type expires it), applies its effect on start (HUD alert, status
// indicator, canmove, vision, factors) and undoes it on end, and wakes the mob with
// life_wake() at both ends. Nothing polls a counter, so a mob with no counter running has
// nothing for the status systems to do.
//
// Units are the legacy ones: one "tick" is STATUS_COUNTER_TICK (one nominal Life cycle), so
// Stun(5) still means five cycles. Readers get the remaining ticks through the named getters
// (get_stunned(), get_eye_blurry(), ...), writers go through the setters (Stun/SetStunned/
// AdjustStunned, Blur/SetBlurry/AdjustBlurry, ...). tools/ci/check_grep.sh rejects direct
// writes to the old counter names.

/datum/status_effect/counter
	id = "counter"
	alert_type = null
	tick_interval = STATUS_EFFECT_NO_TICK
	status_type = STATUS_EFFECT_UNIQUE
	remove_on_fullheal = TRUE
	/// HUD alert category thrown while the counter runs, or null.
	var/hud_alert
	/// HUD alert type for `hud_alert`.
	var/hud_alert_type
	/// Status indicator shown over the mob while the counter runs, or null.
	var/indicator
	/// LIFE_SYS_* bits woken when the counter starts and ends.
	var/wake_bits = LIFE_WAKE_STATUS
	/// TRUE: lying and canmove follow this counter.
	var/updates_canmove = FALSE
	/// TRUE: blindness follows this counter.
	var/updates_blindness = FALSE
	/// TRUE: counter_factors() contributes body factors while the counter runs.
	var/has_factors = FALSE

/// `ticks` is the legacy counter value to start with (see STATUS_COUNTER_TICK).
/datum/status_effect/counter/on_creation(mob/living/new_owner, ticks)
	if(ticks <= 0)
		qdel(src)
		return
	owner = new_owner
	duration = ticks * tick_length()
	. = ..()
	if(QDELETED(src) || !owner)
		return
	counter_started()

/// Deciseconds one legacy tick lasts for this counter.
/datum/status_effect/counter/proc/tick_length()
	return STATUS_COUNTER_TICK

/// Remaining legacy ticks (fractional). 0 once expired.
/datum/status_effect/counter/proc/remaining()
	if(duration == STATUS_EFFECT_PERMANENT)
		return 1
	return max(0, (duration - world.time) / tick_length())

/// Sets the remaining legacy ticks. 0 or less ends the counter.
/datum/status_effect/counter/proc/set_remaining(ticks)
	if(QDELETED(src))
		return
	if(ticks <= 0)
		qdel(src)
		return
	duration = world.time + ticks * tick_length()

/// Body factors this counter contributes while it runs (has_factors), or null.
/datum/status_effect/counter/proc/counter_factors()
	return null

/datum/status_effect/counter/proc/counter_started()
	if(hud_alert)
		owner.throw_alert(hud_alert, hud_alert_type)
	if(indicator)
		owner.add_status_indicator(indicator)
	if(has_factors)
		owner.invalidate_factors()
	if(updates_canmove)
		owner.update_canmove()
	if(updates_blindness)
		owner.update_blinded()
	if(GLOB.mob_hibernation_trace)
		log_runtime("MOB_STATUS: [key_name(owner)] ([owner.type]) [id] started for [round(remaining(), 0.1)] ticks")
	owner.life_wake(wake_bits, id)

/datum/status_effect/counter/on_remove()
	if(QDELETED(owner))
		return
	if(hud_alert)
		owner.clear_alert(hud_alert)
	if(indicator)
		owner.remove_status_indicator(indicator)
	if(has_factors)
		owner.invalidate_factors()
	if(updates_canmove)
		owner.update_canmove()
	if(updates_blindness)
		owner.update_blinded()
	if(GLOB.mob_hibernation_trace)
		log_runtime("MOB_STATUS: [key_name(owner)] ([owner.type]) [id] ended")
	owner.life_wake(wake_bits, "[id] ended")

// --- Mob API --------------------------------------------------------------------------------
// Counters live on living mobs. Every other mob reads 0 and ignores writes, as the old vars
// on /mob did in practice.

/// Remaining legacy ticks of counter `counter_type`, 0 when it isn't running.
/mob/proc/status_counter(datum/status_effect/counter/counter_type)
	return 0

/mob/living/status_counter(datum/status_effect/counter/counter_type)
	if(!status_effects)
		return 0
	var/datum/status_effect/counter/C = has_status_effect(counter_type)
	return C ? C.remaining() : 0

/// Sets counter `counter_type` to `ticks` legacy ticks: starts it, changes it, or ends it.
/mob/proc/set_status_counter(datum/status_effect/counter/counter_type, ticks)
	return

/mob/living/set_status_counter(datum/status_effect/counter/counter_type, ticks)
	var/datum/status_effect/counter/C = status_effects ? has_status_effect(counter_type) : null
	if(C)
		C.set_remaining(ticks)
	else if(ticks > 0)
		apply_status_effect(counter_type, ticks)

/// Raises counter `counter_type` to at least `ticks` (never lowers it).
/mob/proc/raise_status_counter(counter_type, ticks)
	var/current = status_counter(counter_type)
	if(ticks > current)
		set_status_counter(counter_type, ticks)

/// Adds `ticks` (may be negative) to counter `counter_type`, never below 0.
/mob/proc/adjust_status_counter(counter_type, ticks)
	if(!ticks)
		return
	set_status_counter(counter_type, max(status_counter(counter_type) + ticks, 0))

/// Scales a stun / weaken / paralysis / sleep / confusion / blindness duration by
/// BF_DISABLE_DURATION (0 = immune). Mobs without a body don't scale.
/mob/proc/scale_disable_duration(amount)
	return amount

/mob/living/scale_disable_duration(amount)
	var/scale = factor(BF_DISABLE_DURATION)
	return scale == 1 ? amount : round(amount * scale)

/// Recomputes `blinded` from the mob's state. Living mobs whose sight has no model beyond
/// the eye_blind counter keep the old flag as their subtype sets it.
/mob/proc/update_blinded()
	return

// --- Movement and stun family ---------------------------------------------------------------

/datum/status_effect/counter/stunned
	id = "stunned"
	hud_alert = "stunned"
	hud_alert_type = /atom/movable/screen/alert/stunned
	indicator = "stunned"
	updates_canmove = TRUE

/datum/status_effect/counter/weakened
	id = "weakened"
	hud_alert = "weakened"
	hud_alert_type = /atom/movable/screen/alert/weakened
	indicator = "weakened"
	updates_canmove = TRUE

/datum/status_effect/counter/paralysis
	id = "paralyzed"
	hud_alert = "paralyzed"
	hud_alert_type = /atom/movable/screen/alert/paralyzed
	indicator = "paralysis"
	updates_canmove = TRUE
	wake_bits = LIFE_WAKE_STATUS | LIFE_SYS_BODY

/// Sleep. Deep sleepers (species waking_speed) wake faster. A held sleep (the Sleep verb, or a
/// mind whose player left) doesn't run out until released.
/datum/status_effect/counter/sleeping
	id = "asleep"
	hud_alert = "asleep"
	hud_alert_type = /atom/movable/screen/alert/asleep
	indicator = "sleeping"
	updates_canmove = TRUE
	updates_blindness = TRUE
	wake_bits = LIFE_WAKE_STATUS | LIFE_SYS_BODY
	tick_interval = STATUS_COUNTER_TICK

/datum/status_effect/counter/sleeping/tick_length()
	var/mob/living/carbon/C = owner
	if(istype(C) && C.species?.waking_speed > 0)
		return STATUS_COUNTER_TICK / C.species.waking_speed
	return STATUS_COUNTER_TICK

/// While held, the sleep never drops below one tick.
/datum/status_effect/counter/sleeping/tick(seconds_between_ticks)
	if(held())
		duration = max(duration, world.time + STATUS_COUNTER_TICK * 2)

/// The sleeper chose to sleep (the Sleep verb), or is a mind with no player behind it.
/datum/status_effect/counter/sleeping/proc/held()
	if(owner.stat == DEAD)
		return FALSE
	if(owner.toggled_sleeping)
		return TRUE
	return ishuman(owner) && owner.mind && !owner.client

/datum/status_effect/counter/confused
	id = "confused"
	hud_alert = "confused"
	hud_alert_type = /atom/movable/screen/alert/confused
	indicator = "confused"

// Setters keep their legacy names and semantics: X(amount) never lowers the counter,
// SetX(amount) sets it, AdjustX(amount) adds to it. The disabling ones scale by
// BF_DISABLE_DURATION and respect CANSTUN / CANWEAKEN / CANPARALYSE.

/mob/proc/get_stunned()
	return status_counter(/datum/status_effect/counter/stunned)

/mob/proc/Stun(amount, ignore_canstun = FALSE) //Can't go below remaining duration
	if(SEND_SIGNAL(src, COMSIG_LIVING_STATUS_STUN, amount, ignore_canstun) & COMPONENT_NO_STUN)
		return
	if(status_flags & CANSTUN)
		facing_dir = null
		raise_status_counter(/datum/status_effect/counter/stunned, scale_disable_duration(amount))

/mob/proc/SetStunned(amount, ignore_canstun = FALSE) //Sets remaining duration
	if(SEND_SIGNAL(src, COMSIG_LIVING_STATUS_STUN, amount, ignore_canstun) & COMPONENT_NO_STUN)
		return
	if(status_flags & CANSTUN)
		set_status_counter(/datum/status_effect/counter/stunned, max(amount, 0))

/mob/proc/AdjustStunned(amount, ignore_canstun = FALSE) //Adds to remaining duration
	if(SEND_SIGNAL(src, COMSIG_LIVING_STATUS_STUN, amount, ignore_canstun) & COMPONENT_NO_STUN)
		return
	if(status_flags & CANSTUN)
		adjust_status_counter(/datum/status_effect/counter/stunned, amount > 0 ? scale_disable_duration(amount) : amount)

/mob/proc/get_weakened()
	return status_counter(/datum/status_effect/counter/weakened)

/mob/proc/Weaken(amount, ignore_canstun = FALSE) //Can't go below remaining duration
	if(SEND_SIGNAL(src, COMSIG_LIVING_STATUS_WEAKEN, amount, ignore_canstun) & COMPONENT_NO_STUN)
		return
	if(status_flags & CANWEAKEN)
		facing_dir = null
		raise_status_counter(/datum/status_effect/counter/weakened, scale_disable_duration(amount))

/mob/proc/SetWeakened(amount, ignore_canstun = FALSE) //Sets remaining duration
	if(SEND_SIGNAL(src, COMSIG_LIVING_STATUS_WEAKEN, amount, ignore_canstun) & COMPONENT_NO_STUN)
		return
	if(status_flags & CANWEAKEN)
		set_status_counter(/datum/status_effect/counter/weakened, max(amount, 0))

/mob/proc/AdjustWeakened(amount, ignore_canstun = FALSE) //Adds to remaining duration
	if(SEND_SIGNAL(src, COMSIG_LIVING_STATUS_WEAKEN, amount, ignore_canstun) & COMPONENT_NO_STUN)
		return
	if(status_flags & CANWEAKEN)
		adjust_status_counter(/datum/status_effect/counter/weakened, amount > 0 ? scale_disable_duration(amount) : amount)

/mob/proc/get_paralysis()
	return status_counter(/datum/status_effect/counter/paralysis)

/mob/proc/Paralyse(amount, ignore_canstun = FALSE) //Can't go below remaining duration
	if(SEND_SIGNAL(src, COMSIG_LIVING_STATUS_PARALYZE, amount, ignore_canstun) & COMPONENT_NO_STUN)
		return
	if(status_flags & CANPARALYSE)
		facing_dir = null
		raise_status_counter(/datum/status_effect/counter/paralysis, scale_disable_duration(amount))

/mob/proc/SetParalysis(amount, ignore_canstun = FALSE) //Sets remaining duration
	if(SEND_SIGNAL(src, COMSIG_LIVING_STATUS_PARALYZE, amount, ignore_canstun) & COMPONENT_NO_STUN)
		return
	if(status_flags & CANPARALYSE)
		set_status_counter(/datum/status_effect/counter/paralysis, max(amount, 0))

/mob/proc/AdjustParalysis(amount, ignore_canstun = FALSE) //Adds to remaining duration
	if(SEND_SIGNAL(src, COMSIG_LIVING_STATUS_PARALYZE, amount, ignore_canstun) & COMPONENT_NO_STUN)
		return
	if(status_flags & CANPARALYSE)
		adjust_status_counter(/datum/status_effect/counter/paralysis, amount > 0 ? scale_disable_duration(amount) : amount)

/mob/proc/get_sleeping()
	return status_counter(/datum/status_effect/counter/sleeping)

/mob/proc/Sleeping(amount, ignore_canstun = FALSE) //Can't go below remaining duration
	if(SEND_SIGNAL(src, COMSIG_LIVING_STATUS_SLEEP, amount, ignore_canstun) & COMPONENT_NO_STUN)
		return
	facing_dir = null
	raise_status_counter(/datum/status_effect/counter/sleeping, scale_disable_duration(amount))

/mob/proc/SetSleeping(amount, ignore_canstun = FALSE) //Sets remaining duration
	if(SEND_SIGNAL(src, COMSIG_LIVING_STATUS_SLEEP, amount, ignore_canstun) & COMPONENT_NO_STUN)
		return
	set_status_counter(/datum/status_effect/counter/sleeping, max(amount, 0))

/mob/proc/AdjustSleeping(amount, ignore_canstun = FALSE) //Adds to remaining duration
	if(SEND_SIGNAL(src, COMSIG_LIVING_STATUS_SLEEP, amount, ignore_canstun) & COMPONENT_NO_STUN)
		return
	adjust_status_counter(/datum/status_effect/counter/sleeping, amount > 0 ? scale_disable_duration(amount) : amount)

/mob/proc/get_confused()
	return status_counter(/datum/status_effect/counter/confused)

/mob/proc/Confuse(amount, ignore_canstun = FALSE) //Can't go below remaining duration
	raise_status_counter(/datum/status_effect/counter/confused, scale_disable_duration(amount))

/mob/proc/SetConfused(amount, ignore_canstun = FALSE) //Sets remaining duration
	set_status_counter(/datum/status_effect/counter/confused, max(amount, 0))

/mob/proc/AdjustConfused(amount, ignore_canstun = FALSE) //Adds to remaining duration
	adjust_status_counter(/datum/status_effect/counter/confused, amount > 0 ? scale_disable_duration(amount) : amount)
