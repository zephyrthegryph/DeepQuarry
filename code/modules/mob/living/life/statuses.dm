// Mob statuses as timed contributions (doc/rewrite/life_on_om.md §7).
//
// Every timed impairment a mob can suffer (stun, sleep, blindness, stutter, dizziness, ...) is a
// contribution the mob holds on itself in the contribution store: it starts when applied and the
// deadline wheel ends it. Nothing counts it down per frame. Amounts are status units: one unit
// wears off per LIFE_CYCLE (per_cycle units per cycle for statuses that wore off faster).
//
// Anything else that must keep a status on while a condition lasts holds it with its own key
// (voluntary sleep, an unattended body staying asleep, a broken eye keeping sight blurred) and
// releases it when the condition ends.
//
// Immunity is an effect too (EFFECT_IMMUNE_*). A status definition names the immunity that
// blocks it; applying checks it, and gaining the immunity ends the statuses it blocks. Mob types
// declare theirs in object-model decls (self_effects), mutations in GLOB.mutation_immunities,
// and godmode holds them while attached. This replaced the CANSTUN/CANWEAKEN/CANPARALYSE
// status_flags: a flag had one owner, so clearing it (godmode ending) could not know whether
// the mob's type, a mutation or something else still wanted the immunity; a hold per source
// can't be dropped by another source, and it dies with its source.

// --- Definitions ------------------------------------------------------------------------------

/// A mob status: a timed contribution with a mob-facing API (status_at_least() and friends).
/datum/om/effect/mob_status
	abstract_type = /datum/om/effect/mob_status
	/// Status units that wear off per LIFE_CYCLE (a mob may override: /mob/proc/status_rate()).
	var/per_cycle = 1
	/// While resting, this many units wear off per LIFE_CYCLE instead (0: no difference).
	var/per_cycle_resting = 0
	/// Most units the status can hold (0: no cap).
	var/max_units = 0
	/// EFFECT_IMMUNE_* id that blocks this status.
	var/immunity
	/// Increases scale with the mob's BF_DISABLE_DURATION factor.
	var/scaled = FALSE
	/// Increases clear the mob's facing lock.
	var/clears_facing = FALSE
	/// Starting or ending re-derives canmove and lying at once.
	var/incapacitating = FALSE
	/// Screen alert while active: category and type.
	var/alert_category
	var/alert_type
	/// Status indicator (icon state over the mob's head) while active.
	var/indicator

/datum/om/effect/mob_status/on_changed(datum/E, old_value, new_value)
	var/mob/M = E
	if(istype(M) && !QDELETED(M))
		M.on_status_changed(src, !!new_value)

/datum/om/effect/mob_status/stunned
	immunity = EFFECT_IMMUNE_STUN
	scaled = TRUE
	clears_facing = TRUE
	incapacitating = TRUE
	alert_category = "stunned"
	alert_type = /atom/movable/screen/alert/stunned
	indicator = "stunned"

/datum/om/effect/mob_status/weakened
	immunity = EFFECT_IMMUNE_WEAKEN
	scaled = TRUE
	clears_facing = TRUE
	incapacitating = TRUE
	alert_category = "weakened"
	alert_type = /atom/movable/screen/alert/weakened
	indicator = "weakened"

/datum/om/effect/mob_status/paralyzed
	immunity = EFFECT_IMMUNE_PARALYZE
	scaled = TRUE
	clears_facing = TRUE
	incapacitating = TRUE
	alert_category = "paralyzed"
	alert_type = /atom/movable/screen/alert/paralyzed
	indicator = "paralysis"

/// Carbons wake at their species' waking_speed (status_rate()).
/datum/om/effect/mob_status/sleeping
	scaled = TRUE
	clears_facing = TRUE
	incapacitating = TRUE
	alert_category = "asleep"
	alert_type = /atom/movable/screen/alert/asleep
	indicator = "sleeping"

/datum/om/effect/mob_status/confused
	scaled = TRUE
	alert_category = "confused"
	alert_type = /atom/movable/screen/alert/confused
	indicator = "confused"

/datum/om/effect/mob_status/blinded
	scaled = TRUE
	indicator = "blinded"

/datum/om/effect/mob_status/blurry

/datum/om/effect/mob_status/deafened

/datum/om/effect/mob_status/stuttering

/datum/om/effect/mob_status/muted

/datum/om/effect/mob_status/drugged
	alert_category = "high"
	alert_type = /atom/movable/screen/alert/high

/datum/om/effect/mob_status/slurring

/datum/om/effect/mob_status/drowsy

/// Two points of hallucination wore off per cycle.
/datum/om/effect/mob_status/hallucinating
	per_cycle = 2

/// Dizziness and jitters are 0-1000 points: 3 wear off per cycle, 15 while resting. The shake
/// components follow the status (on_status_changed()).
/datum/om/effect/mob_status/dizzy
	per_cycle = 3
	per_cycle_resting = 15
	max_units = 1000
	immunity = EFFECT_IMMUNE_DIZZY

/datum/om/effect/mob_status/jittery
	per_cycle = 3
	per_cycle_resting = 15
	max_units = 1000
	immunity = EFFECT_IMMUNE_JITTER

/// A status immunity. Gaining it ends every active status that names it.
/datum/om/effect/mob_immunity

/datum/om/effect/mob_immunity/on_changed(datum/E, old_value, new_value)
	var/mob/M = E
	if(!new_value || !istype(M) || QDELETED(M))
		return
	for(var/status_id in mob_statuses_blocked_by(id))
		M.status_end(status_id)

/// Status ids whose definition names immunity `immunity_id`.
/proc/mob_statuses_blocked_by(immunity_id)
	var/static/list/by_immunity
	if(!by_immunity)
		by_immunity = list()
		for(var/datum/om/effect/mob_status/def in om_registry().effects)
			if(def.immunity)
				LAZYADD(by_immunity[def.immunity], def.id)
	return by_immunity[immunity_id]

/// The mob_status definition for `effect_id`.
/proc/mob_status_def(effect_id)
	RETURN_TYPE(/datum/om/effect/mob_status)
	var/datum/om/effect/mob_status/def = om_registry().effect(effect_id)
	if(!istype(def))
		CRASH("[effect_id] is not a mob status")
	return def

// --- The status API -------------------------------------------------------------------------

/// TRUE while `effect_id` is in effect on this mob (from any source).
/mob/proc/has_status(effect_id)
	return om_has(src, effect_id)

/// TRUE when this mob holds the immunity that blocks `effect_id`.
/mob/proc/status_immune(effect_id)
	var/datum/om/effect/mob_status/def = mob_status_def(effect_id)
	return def.immunity && om_has(src, def.immunity)

/// Status units of `effect_id` that wear off per LIFE_CYCLE on this mob.
/mob/proc/status_rate(datum/om/effect/mob_status/def)
	if(def.per_cycle_resting && resting)
		return def.per_cycle_resting
	return def.per_cycle

/// Lazy: status id -> the rate its current expiry was computed with, for statuses whose rate
/// can change while they run (status_rate_check()).
/mob/var/list/status_rates_used

/// The rate of `effect_id` may have changed (resting, a blindfold): rescale what is left so the
/// same number of units remains, worn off at the new rate from now on.
/mob/proc/status_rate_check(effect_id)
	var/datum/om/effect/mob_status/def = mob_status_def(effect_id)
	var/rate = status_rate(def)
	var/used = LAZYACCESS(status_rates_used, effect_id) || def.per_cycle
	if(rate == used)
		return
	status_rescale(effect_id, used, rate)
	status_note_rate(def, rate)

/// Records the rate an expiry was computed with (only when it differs from the default).
/mob/proc/status_note_rate(datum/om/effect/mob_status/def, rate)
	if(rate == def.per_cycle)
		LAZYREMOVE(status_rates_used, def.id)
	else
		LAZYSET(status_rates_used, def.id, rate)

/// When this mob's own timed `effect_id` ends (scheduler time), or now if it has none.
/mob/proc/status_expiry(effect_id)
	var/now = om_time_of(src)
	var/expires = om_expires_at(src, effect_id, src)
	return expires ? max(expires, now) : now

/// Remaining `effect_id`, in status units, rounded up (0 when not in effect). A status that
/// something holds (rather than a timed dose) reads at least 1.
/mob/proc/status_units(effect_id)
	if(!om_has(src, effect_id))
		return 0
	var/datum/om/effect/mob_status/def = mob_status_def(effect_id)
	var/left = status_expiry(effect_id) - om_time_of(src)
	return max(left > 0 ? CEILING(left * status_rate(def) / LIFE_CYCLE, 1) : 0, 1)

/// Remaining real seconds of this mob's own timed `effect_id` (0 when none), for readouts.
/mob/proc/status_seconds(effect_id)
	return max(status_expiry(effect_id) - om_time_of(src), 0) / (1 SECONDS)

/// "Can't go below remaining duration": at least `amount` units from now.
/mob/proc/status_at_least(effect_id, amount)
	var/datum/om/effect/mob_status/def = mob_status_def(effect_id)
	amount = status_increase(def, amount)
	if(amount <= 0)
		return FALSE
	if(def.max_units)
		amount = min(amount, def.max_units)
	var/rate = status_rate(def)
	var/until = om_time_of(src) + amount * LIFE_CYCLE / rate
	if(until > status_expiry(effect_id))
		om_apply_until(src, effect_id, src, until)
		status_note_rate(def, rate)
	return TRUE

/// "Sets remaining duration": exactly `amount` units from now (0 ends this mob's own dose;
/// holds by other sources stay).
/mob/proc/status_set(effect_id, amount)
	var/datum/om/effect/mob_status/def = mob_status_def(effect_id)
	if(amount > 0)
		if(!status_admit(def, amount))
			return FALSE
		if(def.max_units)
			amount = min(amount, def.max_units)
		if(def.clears_facing)
			facing_dir = null
	var/rate = status_rate(def)
	om_apply_until(src, effect_id, src, om_time_of(src) + max(amount, 0) * LIFE_CYCLE / rate)
	status_note_rate(def, rate)
	return TRUE

/// "Adds to remaining duration": negative shortens (never below now). An increase scales like
/// status_at_least(); a status with a cap never exceeds it.
/mob/proc/status_adjust(effect_id, amount)
	var/datum/om/effect/mob_status/def = mob_status_def(effect_id)
	if(amount > 0)
		amount = status_increase(def, amount)
		if(amount <= 0)
			return FALSE
	var/rate = status_rate(def)
	var/now = om_time_of(src)
	var/until = status_expiry(effect_id) + amount * LIFE_CYCLE / rate
	if(def.max_units)
		until = min(until, now + def.max_units * LIFE_CYCLE / rate)
	om_apply_until(src, effect_id, src, until)
	status_note_rate(def, rate)
	return TRUE

/// Ends this mob's own timed `effect_id` (holds by other sources stay).
/mob/proc/status_end(effect_id)
	om_release(src, effect_id, src)
	LAZYREMOVE(status_rates_used, effect_id)

/// Rescales the remaining `effect_id` from `old_rate` to `new_rate` units per cycle, so the
/// same number of units is left (dizziness wearing off faster while resting).
/mob/proc/status_rescale(effect_id, old_rate, new_rate)
	var/expires = om_expires_at(src, effect_id, src)
	if(!expires || old_rate == new_rate || new_rate <= 0)
		return
	var/now = om_time_of(src)
	om_apply_until(src, effect_id, src, now + (expires - now) * old_rate / new_rate)

/// Admission of an increase: immunity, then the status signal's veto. FALSE blocks it.
/mob/proc/status_admit(datum/om/effect/mob_status/def, amount)
	if(def.immunity && om_has(src, def.immunity))
		return FALSE
	return !(status_signal(def, amount) & COMPONENT_NO_STUN)

/// Sends the signal that announces an increase of `def` (the statuses that have one).
/mob/proc/status_signal(datum/om/effect/mob_status/def, amount)
	switch(def.id)
		if(EFFECT_STUNNED)
			return SEND_SIGNAL(src, COMSIG_LIVING_STATUS_STUN, amount)
		if(EFFECT_WEAKENED)
			return SEND_SIGNAL(src, COMSIG_LIVING_STATUS_WEAKEN, amount)
		if(EFFECT_PARALYZED)
			return SEND_SIGNAL(src, COMSIG_LIVING_STATUS_PARALYZE, amount)
		if(EFFECT_SLEEPING)
			return SEND_SIGNAL(src, COMSIG_LIVING_STATUS_SLEEP, amount)
		if(EFFECT_BLINDED)
			return SEND_SIGNAL(src, COMSIG_LIVING_STATUS_BLIND, amount)
	return NONE

/// An increase of `amount` units: admitted, then scaled (status_scale()). Returns the units to
/// add, 0 when blocked.
/mob/proc/status_increase(datum/om/effect/mob_status/def, amount)
	if(amount <= 0 || !status_admit(def, amount))
		return 0
	amount = status_scale(def, amount)
	if(amount > 0 && def.clears_facing)
		facing_dir = null
	return amount

/// Scales an increase for this mob (species and modifier resistances).
/mob/proc/status_scale(datum/om/effect/mob_status/def, amount)
	return amount

/// A status started (`active`) or ended on this mob, from any source or by expiry.
/mob/proc/on_status_changed(datum/om/effect/mob_status/def, active)
	if(def.incapacitating)
		update_canmove()
	if(def.alert_category)
		if(active)
			throw_alert(def.alert_category, def.alert_type)
		else
			clear_alert(def.alert_category)
	switch(def.id)
		if(EFFECT_DIZZY)
			if(active)
				LoadComponent(/datum/component/dizzy_shake)
			else
				qdel(GetComponent(/datum/component/dizzy_shake))
		if(EFFECT_JITTERY)
			if(active)
				LoadComponent(/datum/component/jittery_shake)
			else
				qdel(GetComponent(/datum/component/jittery_shake))

/mob/living/status_scale(datum/om/effect/mob_status/def, amount)
	. = ..()
	if(def.scaled)
		. = scale_disable_duration(.)

/mob/living/on_status_changed(datum/om/effect/mob_status/def, active)
	..()
	switch(def.id)
		if(EFFECT_WEAKENED)
			if(active)
				stop_aiming(no_message = 1)
		if(EFFECT_DEAFENED)
			if(active)
				deaf_loop.start()
			else
				deaf_loop.stop()
	if(def.indicator)
		if(active)
			add_status_indicator(def.indicator)
		else
			remove_status_indicator(def.indicator)

/// Scale a stun / weaken / paralysis / sleep / confusion / blindness duration
/// by BF_DISABLE_DURATION (0 = immune).
/mob/living/proc/scale_disable_duration(amount)
	var/scale = factor(BF_DISABLE_DURATION)
	return scale == 1 ? amount : round(amount * scale)

/mob/living/carbon/status_rate(datum/om/effect/mob_status/def)
	if(def.id == EFFECT_SLEEPING && species)
		return species.waking_speed
	return ..()

/// Resting your eyes with a blindfold heals blur four times as fast.
/mob/living/carbon/human/status_rate(datum/om/effect/mob_status/def)
	if(def.id == EFFECT_BLURRY && wearing_blindfold())
		return 4
	return ..()

/mob/living/carbon/human/proc/wearing_blindfold()
	return istype(get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/sunglasses/blindfold)

/// Species resistances to stun and weakness apply before the modifier scaling.
/mob/living/carbon/human/status_scale(datum/om/effect/mob_status/def, amount)
	switch(def.id)
		if(EFFECT_STUNNED)
			amount *= species.stun_mod
		if(EFFECT_WEAKENED)
			amount *= species.weaken_mod
	return ..(def, amount)

/mob/living/carbon/human/on_status_changed(datum/om/effect/mob_status/def, active)
	..()
	// Passing out: our AI can now control the suit.
	if(active && def.id == EFFECT_PARALYZED && wearing_rig && !stat)
		wearing_rig.notify_ai(span_danger("Warning: user consciousness failure. Mobility control passed to integrated intelligence system."))

// --- Voluntary sleep ------------------------------------------------------------------------

/// TRUE while this mob sleeps by choice (the Sleep verb): a hold until it chooses to wake.
/mob/living/proc/sleeping_voluntarily()
	return om_expires_at(src, EFFECT_SLEEPING, src, "voluntary") == 0

/mob/living/verb/mob_sleep()
	set name = "Sleep"
	set category = "IC.Game"
	var/asleep = sleeping_voluntarily()
	if(!asleep && tgui_alert(src, "Are you sure you wish to go to sleep? You will snooze until you use the Sleep verb again.", "Sleepy Time", list("No", "Yes")) != "Yes")
		return
	asleep = !asleep
	to_chat(src, span_notice("You are [asleep ? "now sleeping. Use the Sleep verb again to wake up" : "no longer sleeping"]."))
	set_voluntary_sleep(asleep)

/// Sleeps by choice until called again with FALSE: a hold, so no dose wearing off wakes the mob
/// and ending a dose (status_set(EFFECT_SLEEPING, 0)) doesn't either.
/mob/living/proc/set_voluntary_sleep(asleep)
	if(asleep)
		om_hold(src, EFFECT_SLEEPING, src, TRUE, "voluntary")
	else
		om_release(src, EFFECT_SLEEPING, src, "voluntary")

// --- Immunity sources -----------------------------------------------------------------------

/// Mutation -> the status immunities it grants while the mob has it.
GLOBAL_LIST_INIT(mutation_immunities, list(
	"[HULK]" = list(EFFECT_IMMUNE_STUN, EFFECT_IMMUNE_WEAKEN, EFFECT_IMMUNE_PARALYZE),
))

/// Holds (or releases) the status immunities mutation `mut` grants. Called by add_mutation()
/// and remove_mutation(); the key is the mutation, so two sources never release each other.
/mob/proc/update_mutation_immunities(mut)
	var/list/immunities = GLOB.mutation_immunities["[mut]"]
	if(!immunities)
		return
	var/key = "mutation:[mut]"
	var/held = has_mutation(mut)
	for(var/immunity in immunities)
		if(held)
			om_hold(src, immunity, src, TRUE, key)
		else
			om_release(src, immunity, src, key)

/// Holds every incapacitation immunity on `M` with `source` as the source.
/proc/hold_incapacitation_immunity(mob/M, datum/source)
	om_hold(M, EFFECT_IMMUNE_STUN, source)
	om_hold(M, EFFECT_IMMUNE_WEAKEN, source)
	om_hold(M, EFFECT_IMMUNE_PARALYZE, source)

/proc/release_incapacitation_immunity(mob/M, datum/source)
	om_release(M, EFFECT_IMMUNE_STUN, source)
	om_release(M, EFFECT_IMMUNE_WEAKEN, source)
	om_release(M, EFFECT_IMMUNE_PARALYZE, source)

// Mob types immune by nature (they had CANSTUN, CANWEAKEN and CANPARALYSE cleared).

/datum/om/bundle/immune_incapacitation
	self_effects = list(EFFECT_IMMUNE_STUN = TRUE, EFFECT_IMMUNE_WEAKEN = TRUE, EFFECT_IMMUNE_PARALYZE = TRUE)

/datum/om/decl/immune_incapacitation
	abstract_type = /datum/om/decl/immune_incapacitation
	include = list(/datum/om/bundle/immune_incapacitation)

/datum/om/decl/immune_incapacitation/carbon_human_dummy
	of = /mob/living/carbon/human/dummy

/datum/om/decl/immune_incapacitation/simple_mob_animal_borer
	of = /mob/living/simple_mob/animal/borer

/datum/om/decl/immune_incapacitation/simple_mob_animal_sif_leech
	of = /mob/living/simple_mob/animal/sif/leech

/datum/om/decl/immune_incapacitation/simple_mob_animal_space_space_worm
	of = /mob/living/simple_mob/animal/space/space_worm

/datum/om/decl/immune_incapacitation/simple_mob_vox_armalis
	of = /mob/living/simple_mob/vox/armalis

/datum/om/decl/immune_incapacitation/simple_mob_mechanical_mecha_eclipse
	of = /mob/living/simple_mob/mechanical/mecha/eclipse

/datum/om/decl/immune_incapacitation/simple_mob_vore_ddraig
	of = /mob/living/simple_mob/vore/ddraig

/datum/om/decl/immune_incapacitation/simple_mob_ysbryd
	of = /mob/living/simple_mob/ysbryd

/datum/om/decl/immune_incapacitation/simple_mob_humanoid_cultist_human
	of = /mob/living/simple_mob/humanoid/cultist/human

/datum/om/decl/immune_incapacitation/simple_mob_humanoid_cultist_tesh
	of = /mob/living/simple_mob/humanoid/cultist/tesh

/datum/om/decl/immune_incapacitation/simple_mob_humanoid_cultist_lizard
	of = /mob/living/simple_mob/humanoid/cultist/lizard

/datum/om/decl/immune_incapacitation/simple_mob_humanoid_cultist_caster
	of = /mob/living/simple_mob/humanoid/cultist/caster

/datum/om/decl/immune_incapacitation/simple_mob_humanoid_cultist_initiate
	of = /mob/living/simple_mob/humanoid/cultist/initiate

/datum/om/decl/immune_incapacitation/simple_mob_humanoid_cultist_castertesh
	of = /mob/living/simple_mob/humanoid/cultist/castertesh

/datum/om/decl/immune_incapacitation/simple_mob_humanoid_cultist_elite
	of = /mob/living/simple_mob/humanoid/cultist/elite

/datum/om/decl/immune_incapacitation/simple_mob_humanoid_cultist_magus
	of = /mob/living/simple_mob/humanoid/cultist/magus

/datum/om/decl/immune_incapacitation/simple_mob_humanoid_cultist_hunter
	of = /mob/living/simple_mob/humanoid/cultist/hunter

/datum/om/decl/immune_incapacitation/simple_mob_humanoid_cultist_noodle
	of = /mob/living/simple_mob/humanoid/cultist/noodle

/datum/om/decl/immune_incapacitation/simple_mob_humanoid_astral_collective
	of = /mob/living/simple_mob/humanoid/astral_collective

/datum/om/decl/immune_incapacitation/simple_mob_humanoid_merc
	of = /mob/living/simple_mob/humanoid/merc

/datum/om/decl/immune_incapacitation/simple_mob_construct_cardinal
	of = /mob/living/simple_mob/construct/cardinal

/datum/om/decl/immune_incapacitation/simple_mob_construct_juggernaut
	of = /mob/living/simple_mob/construct/juggernaut

/datum/om/decl/immune_incapacitation/simple_mob_vore_morph
	of = /mob/living/simple_mob/vore/morph


/// The AI can be stunned and paralysed (its EMP stun) but not knocked down.
/datum/om/decl/ai_immunity
	of = /mob/living/silicon/ai
	self_effects = list(EFFECT_IMMUNE_WEAKEN = TRUE)

/// Silicons don't get dizzy or jittery.
/datum/om/decl/silicon_immunity
	of = /mob/living/silicon
	self_effects = list(EFFECT_IMMUNE_DIZZY = TRUE, EFFECT_IMMUNE_JITTER = TRUE)

/// A blindfold going on or off changes how fast blur heals.
/mob/living/carbon/human/on_equipment_changed()
	..()
	if(has_status(EFFECT_BLURRY))
		status_rate_check(EFFECT_BLURRY)
