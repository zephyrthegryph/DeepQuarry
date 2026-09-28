// Body effects: short factor-only effects as OM contributions (MED-5).
//
// A body effect is what a /datum/modifier used to be when all it did was carry a factor
// table for a while (entangled, grievous wounds, numbness, cloning sickness, ...). There is
// no datum per application:
//
//   - The effect's DEFINITION is a flyweight /datum/body_effect subtype (one shared instance
//     per type, body_effect_def()), declaring `factors`, texts and a stacking rule.
//   - An APPLICATION is one contribution to EFFECT_BODY_EFFECTS on the mob, keyed by the
//     definition's type, held by the mob itself; its value is the number of stacks.
//   - A timed application expires through om_after() on the mob's timer clock. For a living
//     mob that is CLOCK_BIO, so stasis slows or stops the countdown and suspension pauses it
//     (an entangled patient in a stasis bag is still entangled when they come out).
//
// The body reads the per-key value (type -> stacks) in recompute_factors(); a change of the
// contribution invalidates the factors through /datum/om/effect/body_effects/on_changed().
//
// API (on /mob/living):
//   apply_body_effect(type, duration, origin)  timed when duration > 0, held otherwise
//   remove_body_effect(type, silent)           ends every stack of `type` (and subtypes)
//   has_body_effect(type)                      any stack of `type` or a subtype
//   body_effect_remaining(type)                deciseconds of body time until the last stack ends
//   clear_body_effects(silent)                 ends everything (rejuvenate, Destroy)
//
// add_modifier()/has_modifier_of_type()/remove_*modifier*() forward /datum/body_effect paths
// here, so generic "apply this type" hooks (projectile modifier_type_to_apply, modapply
// reagents, species cloning_modifier) take either kind.

/datum/body_effect
	abstract_type = /datum/body_effect
	var/name
	var/desc
	/// Body factors applied (per stack) while the effect is on.
	var/alist/factors
	var/on_created_text
	var/on_expired_text
	/// Hidden from OOC listings.
	var/hidden = FALSE
	/// MODIFIER_STACK_EXTEND (reapplying refreshes to the longer duration), MODIFIER_STACK_FORBID
	/// (reapplying does nothing) or MODIFIER_STACK_ALLOWED (each application is a stack with its
	/// own timer).
	var/stacks = MODIFIER_STACK_EXTEND
	/// Overlay icon_state (icons/mob/modifier_effects.dmi) drawn on the mob while the effect is on.
	var/mob_overlay_state
	var/effect_color
	/// Use icons/mob/modifier_effects_vr.dmi for the overlay.
	var/icon_override = FALSE

/// Called once when the first stack takes hold. Definitions are shared: keep no state here.
/datum/body_effect/proc/on_start(mob/living/L)
	return

/// Called once when the last stack ends. `expired` is TRUE when it ran out (not removed or cured).
/datum/body_effect/proc/on_end(mob/living/L, expired)
	return

/// Override for special admission rules (robots excluded, ...).
/datum/body_effect/proc/can_apply(mob/living/L)
	return TRUE

/datum/body_effect/proc/changes_icon_scale()
	return factors && (!isnull(factors[BF_ICON_SCALE_X]) || !isnull(factors[BF_ICON_SCALE_Y]))

/// The shared definition for `path`.
/proc/body_effect_def(path)
	RETURN_TYPE(/datum/body_effect)
	var/static/list/defs = list()
	var/datum/body_effect/def = defs[path]
	if(!def)
		if(!ispath(path, /datum/body_effect) || path == /datum/body_effect)
			CRASH("body_effect_def: [path] is not a body effect")
		def = new path
		defs[path] = def
	return def

/// The contribution's effect type: a change of any application re-reads the factors.
/datum/om/effect/body_effects

/datum/om/effect/body_effects/on_changed(datum/E, old_value, new_value)
	if(isliving(E))
		var/mob/living/L = E
		L.invalidate_factors()

/mob/living
	/// Body effect type -> list of om_after() timer ids, one per timed stack. Lazy.
	var/list/body_effect_timers

/// type -> stacks for every body effect on the mob (read only; empty list when none).
/mob/living/proc/body_effects()
	return om_value_of(src, EFFECT_BODY_EFFECTS)

/mob/living/proc/body_effect_stacks(path)
	var/list/active = body_effects()
	return active[path] || 0

/mob/living/proc/has_body_effect(path)
	for(var/key in body_effects())
		if(ispath(key, path))
			return TRUE
	return FALSE

/// Deciseconds of this mob's body time until the last timed stack of `path` ends; 0 when none.
/mob/living/proc/body_effect_remaining(path)
	. = 0
	for(var/id in body_effect_timers?[path])
		. = max(., om_timer_left(src, id) || 0)

/// Applies body effect `path`. `duration` in deciseconds of body time; 0 or null holds it until
/// removed. Returns TRUE when it took hold or was refreshed.
/mob/living/proc/apply_body_effect(path, duration, mob/living/origin)
	var/datum/body_effect/def = body_effect_def(path)
	if(QDELETED(src) || !def.can_apply(src))
		return FALSE
	var/current = body_effect_stacks(path)
	var/list/timers = body_effect_timers?[path]
	if(current)
		switch(def.stacks)
			if(MODIFIER_STACK_FORBID)
				return FALSE
			if(MODIFIER_STACK_EXTEND)
				if(!length(timers))
					return TRUE // held: nothing to extend
				if(!duration)
					// A held application replaces the countdown.
					for(var/id in timers)
						om_cancel_timer(src, id)
					body_effect_timers -= path
					return TRUE
				if(body_effect_remaining(path) >= duration)
					return TRUE
				for(var/id in timers)
					om_cancel_timer(src, id)
				body_effect_timers[path] = list(om_after(src, duration, PROC_REF(body_effect_expired), path))
				return TRUE
	var/stacks = (def.stacks == MODIFIER_STACK_ALLOWED) ? current + 1 : 1
	om_hold(src, EFFECT_BODY_EFFECTS, src, stacks, path)
	if(duration)
		LAZYINITLIST(body_effect_timers)
		LAZYADD(body_effect_timers[path], om_after(src, duration, PROC_REF(body_effect_expired), path))
	if(!current)
		if(def.on_created_text)
			to_chat(src, def.on_created_text)
		if(def.changes_icon_scale())
			update_transform()
		if(def.mob_overlay_state)
			update_modifier_visuals()
		def.on_start(src)
	return TRUE

/// One timed stack of `path` ran out.
/mob/living/proc/body_effect_expired(path)
	var/list/timers = body_effect_timers?[path]
	if(length(timers))
		timers.Cut(1, 2)
		if(!length(timers))
			body_effect_timers -= path
			UNSETEMPTY(body_effect_timers)
	var/current = body_effect_stacks(path)
	if(current > 1 && length(timers))
		om_hold(src, EFFECT_BODY_EFFECTS, src, current - 1, path)
		return
	end_body_effect(path, FALSE, TRUE)

/// Ends every stack of `path` (and of its subtypes).
/mob/living/proc/remove_body_effect(path, silent = FALSE)
	. = FALSE
	for(var/key in body_effects().Copy())
		if(ispath(key, path))
			end_body_effect(key, silent)
			. = TRUE

/// `expired`: the last timed stack ran out (as opposed to removal or a cure).
/mob/living/proc/end_body_effect(path, silent, expired = FALSE)
	for(var/id in body_effect_timers?[path])
		om_cancel_timer(src, id)
	if(body_effect_timers)
		body_effect_timers -= path
		UNSETEMPTY(body_effect_timers)
	if(!om_release(src, EFFECT_BODY_EFFECTS, src, path))
		return
	var/datum/body_effect/def = body_effect_def(path)
	if(def.on_expired_text && !silent)
		to_chat(src, def.on_expired_text)
	if(QDELETED(src))
		return
	def.on_end(src, expired)
	if(def.changes_icon_scale())
		update_transform()
	if(def.mob_overlay_state)
		update_modifier_visuals()

/mob/living/proc/clear_body_effects(silent = FALSE)
	for(var/key in body_effects().Copy())
		end_body_effect(key, silent)
	body_effect_timers = null

/// Accumulates every body effect's factors (per stack) into `acc`.
/mob/living/proc/accumulate_body_effect_factors(list/acc)
	var/list/active = body_effects()
	for(var/path in active)
		var/datum/body_effect/def = body_effect_def(path)
		for(var/i in 1 to active[path])
			acc = body_factor_accumulate(acc, def.factors)
	return acc

/// OOC listing lines ("name: factor lines") for visible body effects.
/mob/living/proc/describe_body_effects()
	. = list()
	for(var/path in body_effects())
		var/datum/body_effect/def = body_effect_def(path)
		if(def.hidden)
			continue
		. += "[def.name || path]: [jointext(body_factor_describe(def.factors), ", ")]"

/// Overlay images for every body effect with a mob_overlay_state (update_modifier_visuals()).
/mob/living/proc/body_effect_overlays(reset_color = FALSE)
	. = null
	for(var/path in body_effects())
		var/datum/body_effect/def = body_effect_def(path)
		if(!def.mob_overlay_state)
			continue
		var/image/I = image(icon = def.icon_override ? 'icons/mob/modifier_effects_vr.dmi' : 'icons/mob/modifier_effects.dmi', icon_state = def.mob_overlay_state)
		I.color = def.effect_color
		if(reset_color)
			I.appearance_flags = RESET_COLOR
		LAZYADD(., I)
