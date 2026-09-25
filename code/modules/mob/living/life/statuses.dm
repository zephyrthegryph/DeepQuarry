// Mob statuses (doc/rewrite/life_on_om.md §7).
//
// Every timed impairment a mob can suffer (stun, sleep, blindness, stutter, dizziness, ...) is a
// core timed status (code/datums/om/status.dm): a contribution the mob holds on itself, ended by
// the deadline wheel. Its rows (om_library_effects()) declare everything about it: units of
// LIFE_CYCLE, wear rate, immunity, veto signal, alert, indicator and the hooks below. Nothing
// counts a status down per frame, and nothing here switches on which status it is.
//
// Anything that must keep a status on while a condition lasts holds it with its own key
// (voluntary sleep) or tops it up with status_at_least() in the stage that checks the condition.
//
// Immunity is an effect too (EFFECT_IMMUNE_*): a hold per source (type decls, mutations,
// godmode), so no source can drop another's, and gaining it ends the statuses that name it.

// --- Hooks named by the status rows --------------------------------------------------------

/mob/proc/status_clear_facing()
	facing_dir = null

/// Stun, sleep and the end of weakness and paralysis: canmove and lying follow at once.
/mob/proc/status_incapacitation_changed()
	update_canmove()

/mob/proc/status_knocked_down()
	update_canmove()

/mob/living/status_knocked_down()
	..()
	stop_aiming(no_message = 1)

/mob/proc/status_passed_out()
	update_canmove()

/// Passing out: our AI can now control the suit.
/mob/living/carbon/human/status_passed_out()
	..()
	if(wearing_rig && !stat)
		wearing_rig.notify_ai(span_danger("Warning: user consciousness failure. Mobility control passed to integrated intelligence system."))

/mob/proc/status_sight_returned()
	return

/mob/proc/status_deafness_started()
	return

/mob/proc/status_deafness_ended()
	return

/mob/living/status_deafness_started()
	deaf_loop.start()

/mob/living/status_deafness_ended()
	deaf_loop.stop()

/mob/proc/status_dizzy_started()
	LoadComponent(/datum/component/dizzy_shake)

/mob/proc/status_dizzy_ended()
	qdel(GetComponent(/datum/component/dizzy_shake))

/mob/proc/status_jittery_started()
	LoadComponent(/datum/component/jittery_shake)

/mob/proc/status_jittery_ended()
	qdel(GetComponent(/datum/component/jittery_shake))

// --- Presentation, rates and scaling ---------------------------------------------------------

/mob/status_shown(datum/om/effect/status/def, active)
	if(!def.alert)
		return
	if(active)
		throw_alert(def.alert, def.alert_type)
	else
		clear_alert(def.alert)

/mob/living/status_shown(datum/om/effect/status/def, active)
	..()
	if(def.indicator)
		if(active)
			add_status_indicator(def.indicator)
		else
			remove_status_indicator(def.indicator)

/mob/status_resting()
	return resting

/// BF_DISABLE_DURATION scales every `scaled` status (0: immune).
/mob/living/status_scale(datum/om/effect/status/def, amount)
	return scale_disable_duration(amount)

/// Scale a stun / weaken / paralysis / sleep / confusion / blindness duration
/// by BF_DISABLE_DURATION (0 = immune).
/mob/living/proc/scale_disable_duration(amount)
	var/scale = factor(BF_DISABLE_DURATION)
	return scale == 1 ? amount : round(amount * scale)

/// Carbons wake at their species' waking_speed.
/mob/living/carbon/status_rate(datum/om/effect/status/def)
	if(def.id == EFFECT_SLEEPING && species)
		return species.waking_speed
	return ..()

/// Resting your eyes with a blindfold heals blur four times as fast.
/mob/living/carbon/human/status_rate(datum/om/effect/status/def)
	if(def.id == EFFECT_BLURRY && wearing_blindfold())
		return 4
	return ..()

/mob/living/carbon/human/proc/wearing_blindfold()
	return istype(get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/sunglasses/blindfold)

/// Species resistances to stun and weakness apply before the modifier scaling.
/mob/living/carbon/human/status_scale(datum/om/effect/status/def, amount)
	switch(def.id)
		if(EFFECT_STUNNED)
			amount *= species.stun_mod
		if(EFFECT_WEAKENED)
			amount *= species.weaken_mod
	return ..(def, amount)

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
/datum/om/decl/immune_incapacitation
	of = list(
		/mob/living/carbon/human/dummy,
		/mob/living/simple_mob/animal/borer,
		/mob/living/simple_mob/animal/sif/leech,
		/mob/living/simple_mob/animal/space/space_worm,
		/mob/living/simple_mob/vox/armalis,
		/mob/living/simple_mob/mechanical/mecha/eclipse,
		/mob/living/simple_mob/vore/ddraig,
		/mob/living/simple_mob/ysbryd,
		/mob/living/simple_mob/humanoid/cultist/human,
		/mob/living/simple_mob/humanoid/cultist/tesh,
		/mob/living/simple_mob/humanoid/cultist/lizard,
		/mob/living/simple_mob/humanoid/cultist/caster,
		/mob/living/simple_mob/humanoid/cultist/initiate,
		/mob/living/simple_mob/humanoid/cultist/castertesh,
		/mob/living/simple_mob/humanoid/cultist/elite,
		/mob/living/simple_mob/humanoid/cultist/magus,
		/mob/living/simple_mob/humanoid/cultist/hunter,
		/mob/living/simple_mob/humanoid/cultist/noodle,
		/mob/living/simple_mob/humanoid/astral_collective,
		/mob/living/simple_mob/humanoid/merc,
		/mob/living/simple_mob/construct/cardinal,
		/mob/living/simple_mob/construct/juggernaut,
		/mob/living/simple_mob/vore/morph,
	)
	self_effects = list(EFFECT_IMMUNE_STUN = TRUE, EFFECT_IMMUNE_WEAKEN = TRUE, EFFECT_IMMUNE_PARALYZE = TRUE)

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
