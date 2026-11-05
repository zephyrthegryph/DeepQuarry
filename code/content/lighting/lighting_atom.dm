/atom
	// The light's range, power and colour are the light_glow() type trait (code/modules/lighting/glow.dm): glow_of(src).range.
	/// The light switch: FALSE only while the atom's light is switched off on purpose (a lamp that starts off declares `light_on = FALSE`).
	/// Whether the atom casts is derived: light_on and a glow range and power above 0 (atom_casts_light()). A declared glow is cast
	/// without any write at init; every writer of the switch or the glow goes through a setter below, and each setter reconciles the
	/// light source (light_changed()), so no caller can leave the source out of step with what the atom casts.
	var/light_on = TRUE
	///Our light source. Don't fuck with this directly unless you have a good reason!
	var/tmp/datum/light_source/light
	///Any light sources that are "inside" of us, for example, if src here was a mob that's carrying a flashlight, that flashlight's light source would be part of this list.
	var/tmp/list/light_sources

/atom/movable
	///Highest-intensity light affecting us, which determines our visibility.
	///Lazylist to keep track on the sources of illumination.
	// affected_dynamic_lights lives in code/datums/sparse_vars/movable_misc.dm
	// blocks_emissive (EMISSIVE_BLOCK_NONE, _GENERIC or _UNIQUE) is the movable_motion type trait: motion_of(A).blocks_emissive
	///Internal holder for emissive blocker object, do not use directly use motion_of(A).blocks_emissive
	var/tmp/atom/movable/emissive_blocker/em_block


// Will update the light (duh).
// Creates or destroys it if needed, makes it update values, makes sure it's got the correct source turf...
/atom/proc/update_light()
	if (QDELETED(src))
		return

	if(atom_rules_of(src).light_system != STATIC_LIGHT)
		CRASH("update_light() for [src] with following light_system value: [atom_rules_of(src).light_system]")

	if (!atom_casts_light(src)) // We won't emit light anyways, destroy the light source.
		rel_clear(src, nameof(light))
	else
		if (!ismovable(loc)) // We choose what atom should be the top atom of the light here.
			. = src
		else
			. = loc

		if (light) // Update the light or create it if it does not exist.
			light.update(.)
		else
			rel_set(src, nameof(light), new/datum/light_source(src, .))


/**
 * Updates the atom's opacity value.
 *
 * This exists to act as a hook for associated behavior.
 * It notifies (potentially) affected light sources so they can update (if needed).
 */
/atom/proc/set_opacity(new_opacity)
	if(new_opacity == opacity)
		return
	. = opacity
	opacity = new_opacity
	tracked_changed(src, nameof(opacity))
SETTER(/atom, opacity)


/atom/movable/set_opacity(new_opacity)
	. = ..()
	opacity_light_update(.)

/// The light a movable blocks follows its opacity; `old` is what set_opacity() returned (null: nothing changed).
/atom/movable/proc/opacity_light_update(old)
	if(isnull(old) || !isturf(loc))
		return

	if(opacity)
		start_blocking_light()
	else
		stop_blocking_light()


/turf/set_opacity(new_opacity)
	. = ..()
	if(isnull(.))
		return
	recalculate_directional_opacity()

/atom/proc/flash_lighting_fx(_range = FLASH_LIGHT_RANGE, _power = FLASH_LIGHT_POWER, _color = COLOR_WHITE, _duration = FLASH_LIGHT_DURATION)
	return


/turf/flash_lighting_fx(_range = FLASH_LIGHT_RANGE, _power = FLASH_LIGHT_POWER, _color = COLOR_WHITE, _duration = FLASH_LIGHT_DURATION)
	if(!_duration)
		stack_trace("Lighting FX obj created on a turf without a duration")
	new /obj/effect/dummy/lighting_obj (src, _range, _power, _color, _duration)


/obj/flash_lighting_fx(_range = FLASH_LIGHT_RANGE, _power = FLASH_LIGHT_POWER, _color = COLOR_WHITE, _duration = FLASH_LIGHT_DURATION)
	if(!_duration)
		stack_trace("Lighting FX obj created on a obj without a duration")
	new /obj/effect/dummy/lighting_obj (get_turf(src), _range, _power, _color, _duration)


/mob/living/flash_lighting_fx(_range = FLASH_LIGHT_RANGE, _power = FLASH_LIGHT_POWER, _color = COLOR_WHITE, _duration = FLASH_LIGHT_DURATION)
	mob_light(_range, _power, _color, _duration)


/mob/living/proc/mob_light(_range, _power, _color, _duration)
	var/obj/effect/dummy/lighting_obj/moblight/mob_light_obj = new (src, _range, _power, _color, _duration)
	return mob_light_obj

/// Whether `A` casts light now: its switch is on and its glow has a range and a power. The one definition update_light() and the tests use.
/proc/atom_casts_light(atom/A)
	if(!A.light_on)
		return FALSE
	var/datum/type_trait/light_glow/glow = glow_of(A)
	return glow.range && glow.power

/// A light input (the switch, the range, the power or the colour) changed: a static light's source follows it now. A movable not yet in the
/// world is skipped (on_materialize() makes its source), as is anything before its Initialize(); overlay lights follow the notices.
/atom/proc/light_changed()
	if(atom_rules_of(src).light_system != STATIC_LIGHT || !(flags & ATOM_INITIALIZED))
		return
	if(ismovable(src) && !(flags & ATOM_MATERIALIZED))
		return
	update_light()

/// Setter for the light power of this atom.
/atom/proc/set_light_power(new_power)
	if(new_power == glow_of(src).power)
		return
	. = glow_of(src).power
	set_trait(src, ENTRY_LIGHT_GLOW, "power", new_power)
	PUBLISH(src, atom_update_light_power, old_power = .)
	light_changed()

/// Setter for the light range of this atom.
/atom/proc/set_light_range(new_range)
	if(new_range == glow_of(src).range)
		return
	. = glow_of(src).range
	set_trait(src, ENTRY_LIGHT_GLOW, "range", new_range)
	PUBLISH(src, atom_update_light_range, old_range = .)
	light_changed()

/// Setter for the light color of this atom.
/atom/proc/set_light_color(new_color)
	if(new_color == glow_of(src).color)
		return
	. = glow_of(src).color
	set_trait(src, ENTRY_LIGHT_GLOW, "color", new_color)
	PUBLISH(src, atom_update_light_color, old_color = .)
	light_changed()

/// Setter for whether or not this atom's light is on.
/atom/proc/set_light_on(new_value)
	if(new_value == light_on)
		return
	. = light_on
	light_on = new_value
	tracked_changed(src, nameof(light_on)) // a drawn thing that shows its lamp redraws
	PUBLISH(src, atom_update_light_on, old_value = .)
	light_changed()
SETTER(/atom, light_on)


/// Setter for the light flags of this atom.
/atom/proc/set_light_flags(new_value)
	var/old_value = STATE_PEEK(src, atom_misc, light_flags)
	if(new_value == old_value)
		return
	. = old_value
	STATE_SET(src, atom_misc, light_flags, new_value || null)
	PUBLISH(src, atom_update_light_flags, old_flags = .)

///Keeps track of the sources of dynamic luminosity and updates our visibility with the highest.
/atom/movable/proc/update_dynamic_luminosity()
	var/highest = 0
	var/list/adl = dq_get_affected_dynamic_lights(src)
	for(var/i in adl)
		if(adl[i] <= highest)
			continue
		highest = adl[i]
	if(highest == STATE_PEEK(src, movable_misc, affecting_dynamic_lumi))
		return
	luminosity -= STATE_PEEK(src, movable_misc, affecting_dynamic_lumi)
	STATE_SET(src, movable_misc, affecting_dynamic_lumi, highest)
	luminosity += STATE_PEEK(src, movable_misc, affecting_dynamic_lumi)


///Helper to change several lighting overlay settings.
/atom/movable/proc/set_light_range_power_color(range, power, color)
	set_light_range(range)
	set_light_power(power)
	set_light_color(color)


// em_block is owned (implicit OWN, DELETE): the blocker is made at a null loc for this movable's
// overlay, and dies with it (Destroy() cuts the overlay first).

/atom/look_light_key()
	var/datum/type_trait/light_glow/glow = glow_of(src)
	return "[glow.range]/[glow.power]/[glow.color]/[light_on]"

CAPABILITIES_PART(/atom/movable, lighting)
	owns_one(nameof(em_block), /atom/movable/emissive_blocker)
	owns_one(nameof(overlay_light), /datum/overlay_lighting)
