// Body effects: everything that used to be a /datum/modifier (MED-5).
//
// A body effect is a named, usually temporary, condition on a mob: a factor table for a while
// (entangled, grievous wounds, numbness, cloning sickness, ...), a persistent trait
// (colourblindness, tall), or something that does work every few seconds while it lasts
// (shields, auras, berserk, the technomancer's mends, horror symptoms). There is no datum per
// application:
//
//   - The effect's DEFINITION is a flyweight /datum/body_effect subtype (one shared instance
//     per type, body_effect_def()), declaring `factors`, texts, a stacking rule and hooks.
//     Definitions are shared: they never hold per-mob state.
//   - An APPLICATION is one contribution to EFFECT_BODY_EFFECTS on the mob, keyed by the
//     definition's type, held by the mob itself; its value is the number of stacks.
//   - A timed application expires through after() on the mob's timer clock. For a living
//     mob that is CLOCK_BIO, so stasis slows or stops the countdown and suspension pauses it
//     (an entangled patient in a stasis bag is still entangled when they come out). A
//     definition with `world_clock` counts real time instead (the global OM owner).
//   - Per-tick work is an OM behaviour on the mob: a definition with `tick_interval` gets
//     on_tick(L) on an after() cadence (same clock as its expiry) while it is on.
//   - Per-application state (the origin, a synced item, a counter) lives on the mob, keyed by
//     the definition's type: body_effect_origin(), body_effect_state()/set_body_effect_state().
//     It is dropped when the last stack ends.
//
// The body reads the per-key value (type -> stacks) in recompute_factors(); a change of the
// contribution invalidates the factors through /datum/om/effect/body_effects/on_changed().
//
// API (on /mob/living):
//   apply_body_effect(type, duration, origin, suppress)  timed when duration > 0, held otherwise
//   remove_body_effect(type, silent)           ends every stack of `type` (and subtypes)
//   has_body_effect(type)                      any stack of `type` or a subtype
//   body_effect_stacks(type)                   stacks of exactly `type`
//   body_effect_remaining(type)                deciseconds until the last stack ends
//   body_effect_origin(type)                   whoever applied it (resolved), or null
//   body_effect_state(type) / set_body_effect_state(type, value)
//   clear_body_effects(silent)                 ends everything (rejuvenate, Destroy)

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
	/// A persistent trait of the character: recorded on the identity, so it follows cloning.
	var/genetic = FALSE
	/// The client sees the world tinted this colour (or colour matrix) while the effect is on.
	var/client_color
	/// Wire colour replacement list while the effect is on (colourblindness).
	var/list/wire_colors_replace
	/// A filter added to the mob while the effect is on (a filter parameter list).
	var/list/filter_parameters
	var/filter_priority = 1
	/// Deciseconds. When set, on_tick(L) runs this often (on the effect's clock) while it is on.
	var/tick_interval = 0
	/// Count duration and ticks in real time rather than the mob's (bio) clock. For effects
	/// that must keep running while the body is in stasis (stasis itself).
	var/world_clock = FALSE
	/// Ends (silently) when the mob dies. Checked on each tick and on death.
	var/end_on_death = FALSE
	/// An aura: ends when its origin is gone or further than this many tiles away. Checked
	/// every tick; set tick_interval with it.
	var/aura_max_distance = 0

/// Called once when the first stack takes hold. Definitions are shared: keep no state here.
/datum/body_effect/proc/on_start(mob/living/L)
	return

/// Called once when the last stack ends. `expired` is TRUE when it ran out (not removed or cured).
/datum/body_effect/proc/on_end(mob/living/L, expired)
	return

/// Called every tick_interval while the effect is on, before on_tick(): the place to end the
/// effect when its conditions are gone (the item was taken off, the mob left the area).
/datum/body_effect/proc/on_check(mob/living/L)
	return

/// Called every tick_interval while the effect is on (after on_check(), if it is still on).
/datum/body_effect/proc/on_tick(mob/living/L)
	return

/// Override for special admission rules (robots excluded, ...). `suppress_output`: the caller
/// reapplies it repeatedly (a reagent), so failure messages would spam.
/datum/body_effect/proc/can_apply(mob/living/L, suppress_output = FALSE)
	return TRUE

/// The overlay colour on `L` (effect_color unless the application sets its own).
/datum/body_effect/proc/overlay_color(mob/living/L)
	return effect_color

/// Behaviour grants for the combat AI while the effect is on (a static list), or null.
/datum/body_effect/proc/get_dq_granted_behaviors()
	return null

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
	/// Body effect type -> list of timed-stack names, one per timed stack, soonest first. Each
	/// names a `body_effect` timer slot (body_effect_after()); the slot owns the timer. Lazy.
	var/list/body_effect_timers
	/// Next timed-stack serial (names only, never a timer id).
	var/tmp/body_effect_serial = 0
	/// Body effect type -> an owned /datum/body_effect_origin naming whoever applied it. Lazy.
	var/list/body_effect_origins
	/// Body effect type -> per-application state (anything the definition keeps). Lazy.
	var/list/body_effect_data
	/// Body effect type -> the application's own factor table (a static alist, or null for
	/// none), replacing the definition's `factors`. Lazy; a type absent here uses `factors`.
	var/list/body_effect_factors

/// type -> stacks for every body effect on the mob (read only; empty list when none).
/mob/living/proc/body_effects()
	RETURN_TYPE(/list)
	var/static/list/none = list()
	return om_value_of(src, EFFECT_BODY_EFFECTS) || none

/mob/living/proc/body_effect_stacks(path)
	var/list/active = body_effects()
	return active[path] || 0

/mob/living/proc/has_body_effect(path)
	for(var/key in body_effects())
		if(ispath(key, path))
			return TRUE
	return FALSE

/// The first active body effect type that is `path` or a subtype of it, or null.
/mob/living/proc/body_effect_of_type(path)
	for(var/key in body_effects())
		if(ispath(key, path))
			return key
	return null

/// Whoever applied body effect `path` (the mob itself when nobody else did), or null when it
/// is gone or the effect is not on.
/mob/living/proc/body_effect_origin(path)
	var/datum/body_effect_origin/O = body_effect_origins?[path]
	return O?.origin

/// Records whoever applied body effect `path`: an owned record holding a relation view, so the
/// origin reads null once it is deleted.
/mob/living/proc/set_body_effect_origin(path, atom/origin)
	if(isnull(origin))
		if(body_effect_origins && (path in body_effect_origins))
			rel_add(src, nameof(body_effect_origins), null, path)
			if(!length(body_effect_origins))
				rel_clear(src, nameof(body_effect_origins))
		return
	var/datum/body_effect_origin/O = new
	rel_set(O, nameof(O.origin), origin)
	rel_add(src, nameof(body_effect_origins), O, path)

/mob/living/proc/body_effect_state(path)
	return body_effect_data?[path]

/mob/living/proc/set_body_effect_state(path, value)
	if(isnull(value))
		if(body_effect_data)
			body_effect_data -= path
			UNSETEMPTY(body_effect_data)
		return
	LAZYSET(body_effect_data, path, value)

/// Replaces the factor table of the running application of `path` (charge- or strength-dependent
/// effects). Pass a static alist; null means no factors. Swapping between static tables keeps
/// the recompute cheap: nothing changes when the same table is set again.
/mob/living/proc/set_body_effect_factors(path, alist/new_factors)
	if(!body_effect_stacks(path))
		return
	if(body_effect_factors && (path in body_effect_factors) && body_effect_factors[path] == new_factors)
		return
	LAZYSET(body_effect_factors, path, new_factors)
	invalidate_factors()

/// Goes back to the definition's `factors` for `path`.
/mob/living/proc/reset_body_effect_factors(path)
	if(!body_effect_factors || !(path in body_effect_factors))
		return
	body_effect_factors -= path
	UNSETEMPTY(body_effect_factors)
	invalidate_factors()

/// The timer slot for body effect timer `name` ("[path]#[serial]" or "[path]#tick"): on the mob,
/// or, for a world-clock effect, on the global owner under a name that includes the mob.
/mob/living/proc/body_effect_slot(datum/body_effect/def, name)
	return def.world_clock ? "body_effect:[om_handle(src)]:[name]" : "body_effect:[name]"

/// Schedules body effect timer `name` for `path` on the definition's clock (replacing one of that
/// name). The slot owns the timer: firing, cancelling and deletion end it.
/mob/living/proc/body_effect_after(datum/body_effect/def, name, delay, proc_ref, path)
	if(def.world_clock)
		return after_slot(null, body_effect_slot(def, name), delay, GLOBAL_PROC_REF(body_effect_world_timer), src, proc_ref, path)
	return after_slot(src, body_effect_slot(def, name), delay, proc_ref, path)

/mob/living/proc/body_effect_cancel(datum/body_effect/def, name)
	cancel_after(def.world_clock ? null : src, body_effect_slot(def, name))

/mob/living/proc/body_effect_pending(datum/body_effect/def, name)
	return after_pending(def.world_clock ? null : src, body_effect_slot(def, name))

/mob/living/proc/body_effect_timer_left(datum/body_effect/def, name)
	return after_left(def.world_clock ? null : src, body_effect_slot(def, name)) || 0

/// A new timed stack of `path`: its name, scheduled to expire after `duration`.
/mob/living/proc/body_effect_new_stack(datum/body_effect/def, path, duration)
	var/name = "[path]#[++body_effect_serial]"
	body_effect_after(def, name, duration, PROC_REF(body_effect_expired), path)
	return name

/// A world-clock body effect timer firing (weak: dropped if the mob is gone).
/proc/body_effect_world_timer(mob/living/L, proc_ref, path)
	if(QDELETED(L))
		return
	call(L, proc_ref)(path)

/// Deciseconds until the last timed stack of `path` ends; 0 when none.
/mob/living/proc/body_effect_remaining(path)
	. = 0
	var/list/timers = body_effect_timers?[path]
	if(!length(timers))
		return
	var/datum/body_effect/def = body_effect_def(path)
	for(var/name in timers)
		. = max(., body_effect_timer_left(def, name))

/// Applies body effect `path`. `duration` in deciseconds of the effect's clock; 0 or null holds
/// it until removed. `origin`: whoever caused it (defaults to the mob). Returns TRUE when it took
/// hold or was refreshed.
/mob/living/proc/apply_body_effect(path, duration, atom/origin, suppress_output = FALSE)
	var/datum/body_effect/def = body_effect_def(path)
	if(QDELETED(src))
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
					for(var/name in timers)
						body_effect_cancel(def, name)
					body_effect_timers -= path
					return TRUE
				if(body_effect_remaining(path) >= duration)
					return TRUE
				for(var/name in timers)
					body_effect_cancel(def, name)
				body_effect_timers[path] = list(body_effect_new_stack(def, path, duration))
				return TRUE
	else
		// The origin is readable from can_apply() and on_start().
		set_body_effect_origin(path, origin || src)
		if(!def.can_apply(src, suppress_output) || QDELETED(src))
			if(!body_effect_stacks(path))
				set_body_effect_origin(path, null)
			return FALSE
	var/stacks = (def.stacks == MODIFIER_STACK_ALLOWED) ? current + 1 : 1
	om_hold(src, EFFECT_BODY_EFFECTS, src, stacks, path)
	changed(src, CHANGE_MOB_CONDITIONS)
	PUBLISH_CHANGE(src, MOB_KEY_CONDITIONS)
	if(duration)
		LAZYINITLIST(body_effect_timers)
		LAZYADD(body_effect_timers[path], body_effect_new_stack(def, path, duration))
	if(!current)
		if(def.on_created_text)
			to_chat(src, def.on_created_text)
		if(def.genetic)
			record_genetic_effect(path, TRUE)
		if(def.changes_icon_scale())
			update_transform()
		if(def.mob_overlay_state)
			update_modifier_visuals()
		if(def.client_color)
			update_client_color()
		if(LAZYLEN(def.filter_parameters))
			add_filter("body_effect:[path]", def.filter_priority, def.filter_parameters)
		if(def.tick_interval)
			body_effect_after(def, "[path]#tick", def.tick_interval, PROC_REF(body_effect_tick), path)
		def.on_start(src)
	return TRUE

/// One tick of body effect `path`.
/mob/living/proc/body_effect_tick(path)
	if(!body_effect_stacks(path))
		return
	var/datum/body_effect/def = body_effect_def(path)
	if(def.end_on_death && stat == DEAD)
		end_body_effect(path, TRUE)
		return
	if(def.aura_max_distance)
		var/atom/A = body_effect_origin(path)
		if(!istype(A) || get_dist(src, A) > def.aura_max_distance)
			end_body_effect(path, FALSE)
			return
	def.on_check(src)
	if(QDELETED(src) || !body_effect_stacks(path))
		return
	def.on_tick(src)
	if(QDELETED(src) || !body_effect_stacks(path) || body_effect_pending(def, "[path]#tick"))
		return
	body_effect_after(def, "[path]#tick", def.tick_interval, PROC_REF(body_effect_tick), path)

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

/// Ends one stack of `path` (or of the first subtype found); the effect ends with its last stack.
/mob/living/proc/remove_body_effect_stack(path, silent = FALSE)
	var/key = body_effect_of_type(path)
	if(!key)
		return FALSE
	var/current = body_effect_stacks(key)
	if(current <= 1)
		end_body_effect(key, silent)
		return TRUE
	var/list/timers = body_effect_timers?[key]
	if(length(timers))
		body_effect_cancel(body_effect_def(key), timers[1])
		timers.Cut(1, 2)
	om_hold(src, EFFECT_BODY_EFFECTS, src, current - 1, key)
	return TRUE

/// `expired`: the last timed stack ran out (as opposed to removal or a cure).
/mob/living/proc/end_body_effect(path, silent, expired = FALSE)
	var/datum/body_effect/def = body_effect_def(path)
	for(var/name in body_effect_timers?[path])
		body_effect_cancel(def, name)
	if(body_effect_timers)
		body_effect_timers -= path
		UNSETEMPTY(body_effect_timers)
	body_effect_cancel(def, "[path]#tick")
	if(!om_release(src, EFFECT_BODY_EFFECTS, src, path))
		return
	changed(src, CHANGE_MOB_CONDITIONS)
	PUBLISH_CHANGE(src, MOB_KEY_CONDITIONS)
	if(def.on_expired_text && !silent)
		to_chat(src, def.on_expired_text)
	// A persistent trait leaves the character only when deliberately removed from a living
	// body, not when the body dies or is deleted.
	if(def.genetic && !QDELETED(src) && stat != DEAD)
		record_genetic_effect(path, FALSE)
	if(!QDELETED(src))
		def.on_end(src, expired)
	set_body_effect_origin(path, null)
	set_body_effect_state(path, null)
	if(body_effect_factors)
		body_effect_factors -= path
		UNSETEMPTY(body_effect_factors)
	if(QDELETED(src))
		return
	if(def.changes_icon_scale())
		update_transform()
	if(def.mob_overlay_state)
		update_modifier_visuals()
	if(def.client_color)
		update_client_color()
	if(LAZYLEN(def.filter_parameters))
		remove_filter("body_effect:[path]")

/mob/living/proc/clear_body_effects(silent = FALSE)
	for(var/key in body_effects().Copy())
		end_body_effect(key, silent)
	body_effect_timers = null

/// Ends the effects that don't outlast death (end_on_death). Called from death().
/mob/living/proc/end_body_effects_on_death()
	for(var/key in body_effects().Copy())
		var/datum/body_effect/def = body_effect_def(key)
		if(def.end_on_death)
			end_body_effect(key, TRUE)

/// The filter a body effect added to the mob (for animate()), or null.
/mob/living/proc/body_effect_filter(path)
	return get_filter("body_effect:[path]")

/// Accumulates every body effect's factors (per stack) into `acc`.
/mob/living/proc/accumulate_body_effect_factors(list/acc)
	var/list/active = body_effects()
	for(var/path in active)
		var/alist/table
		if(body_effect_factors && (path in body_effect_factors))
			table = body_effect_factors[path]
		else
			table = body_effect_def(path).factors
		if(!table)
			continue
		for(var/i in 1 to active[path])
			acc = body_factor_accumulate(acc, table)
	return acc

/// OOC listing lines ("name: factor lines") for visible body effects.
/mob/living/proc/describe_body_effects()
	. = list()
	for(var/path in body_effects())
		var/datum/body_effect/def = body_effect_def(path)
		if(def.hidden)
			continue
		. += "[def.name || path]: [jointext(body_factor_describe(def.factors), ", ")]"

/// The wire colour replacement list of the first body effect that sets one, or null.
/mob/living/proc/body_effect_wire_colors()
	for(var/path in body_effects())
		var/datum/body_effect/def = body_effect_def(path)
		if(!isnull(def.wire_colors_replace))
			return def.wire_colors_replace
	return null

/// Client colours of every body effect that sets one (a list; a matrix is one entry).
/mob/living/proc/body_effect_client_colors()
	. = list()
	for(var/path in body_effects())
		var/datum/body_effect/def = body_effect_def(path)
		if(!isnull(def.client_color))
			. += list(def.client_color)

/// Overlay images for every body effect with a mob_overlay_state (update_modifier_visuals()).
/mob/living/proc/body_effect_overlays(reset_color = FALSE)
	. = null
	for(var/path in body_effects())
		var/datum/body_effect/def = body_effect_def(path)
		if(!def.mob_overlay_state)
			continue
		var/image/I = image(icon = def.icon_override ? 'icons/mob/modifier_effects_vr.dmi' : 'icons/mob/modifier_effects.dmi', icon_state = def.mob_overlay_state)
		I.color = def.overlay_color(src)
		if(reset_color)
			I.appearance_flags = RESET_COLOR
		LAZYADD(., I)

/// Who applied one body effect to a mob: owned by the mob's body_effect_origins, keyed by type.
/datum/body_effect_origin
	/// A relation view: null once the origin is deleted.
	var/atom/origin
