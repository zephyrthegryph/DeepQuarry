/atom
	///Light systems, both shouldn't be active at the same time.
	var/light_system = STATIC_LIGHT
	///Range of the light in tiles. Zero means no light.
	var/light_range = 0
	///Intensity of the light. The stronger, the less shadows you will see on the lit area.
	var/light_power = 1
	///Hexadecimal RGB string representing the colour of the light. White by default.
	var/light_color = COLOR_WHITE
	///Boolean variable for toggleable lights. Has no effect without the proper light_system, light_range and light_power values.
	var/light_on = FALSE
	///Bitflags to determine lighting-related atom properties.
	var/light_flags = NONE
	///Our light source. Don't fuck with this directly unless you have a good reason!
	var/tmp/datum/light_source/light
	///Any light sources that are "inside" of us, for example, if src here was a mob that's carrying a flashlight, that flashlight's light source would be part of this list.
	var/tmp/list/light_sources

/atom/movable
	///Hint for directional light cone positioning. X is relevant when facing north/south (this setting is for south and inverted for north)
	var/light_cone_x_offset // When facing south, inverted when facing north
	///Hint for directional light cone positioning. Y is relevant when facing east/west (same value used for both east and west)
	var/light_cone_y_offset // When facing east/west, ignored for north/south (uses 16 in those cases)
	///Highest-intensity light affecting us, which determines our visibility.
	var/tmp/affecting_dynamic_lumi = 0
	///Lazylist to keep track on the sources of illumination.
	// affected_dynamic_lights lives in code/datums/sparse_vars/movable_misc.dm
	///Either FALSE, [EMISSIVE_BLOCK_GENERIC], or [EMISSIVE_BLOCK_UNIQUE]
	var/blocks_emissive = EMISSIVE_BLOCK_NONE
	///Internal holder for emissive blocker object, do not use directly use blocks_emissive
	var/tmp/atom/movable/emissive_blocker/em_block

CAPABILITIES(/atom/movable)
	owns_one(nameof(em_block), /atom/movable/emissive_blocker)
	owns_one(nameof(experiment_handler), /datum/experiment_handler)
	owns_one(nameof(overlay_light), /datum/overlay_lighting)
	owns_one(nameof(recursive_move), /datum/recursive_move)
	owns_one(nameof(riding_datum), /datum/riding)
	owns_many(nameof(hose_connectors))
	// What a mob is buckled to, what a puller pulls and what a grab holds: sparse pairs, because a base type takes no var for them (code/engine/declare/link_state.dm).
	// Their writers are buckle_link(), pull_link() and the grab's grab_made(); their readers are buckled_to(), buckled_mob_list(), pulling_target(), pulled_by_mob(),
	// grab_target() and grabbed_by_list() (code/datums/om/relation.dm).
	links(LINK_END(/mob/living, LK_BUCKLED_TO), LINK_END(/atom/movable, LK_BUCKLED_MOBS), sparse = TRUE, b_many = TRUE, holds_while = PROC_REF(link_stays_seated), a_contributes = list(STAT_BUCKLED, TRUE), a_on_unlink = TYPE_PROC_REF(/mob/living, buckle_released), b_on_unlink = PROC_REF(buckle_vacated))
	links(LINK_END(/atom/movable, LK_PULLING), LINK_END(/atom/movable, LK_PULLED_BY), sparse = TRUE, holds_while = PROC_REF(link_stays_in_pull_range), a_on_unlink = PROC_REF(pull_released))
	links(LINK_END(/obj/item/grab, LK_GRABBING), LINK_END(/mob/living, LK_GRABBED_BY), sparse = TRUE, b_many = TRUE, a_on_other_deleted = OTHER_DELETE_ME, b_on_unlink = TYPE_PROC_REF(/mob/living, grab_released))
	// the default drag of every movable: buckle the dragged mob (code/game/objects/buckling.dm)
	op("drag_buckle", item(/mob/living), gesture(GESTURE_DRAG), priority(OP_PRIORITY_DEFAULT), label("Buckle"), when(cond_all(nameof(can_buckle), nameof(drag_buckle))), then(PROC_REF(interaction_drag_buckle)))
	op("vv_get_movable", topic_in(VV_TOPIC, VV_HK_GET_MOVABLE), needs(req_rights(R_ADMIN)), then(PROC_REF(vv_topic_get_movable)))
	op("vv_edit_particles", topic_in(VV_TOPIC, VV_HK_EDIT_PARTICLES), needs(req_rights(R_VAREDIT)), then(PROC_REF(vv_topic_edit_particles)))

// The proc you should always use to set the light of this atom.
// Nonesensical value for l_color default, so we can detect if it gets set to null.
#define NONSENSICAL_VALUE -99999
/atom/proc/set_light(l_range, l_power, l_color = NONSENSICAL_VALUE, l_on)
	if(l_range > 0 && l_range < MINIMUM_USEFUL_LIGHT_RANGE)
		l_range = MINIMUM_USEFUL_LIGHT_RANGE //Brings the range up to 1.4, which is just barely brighter than the soft lighting that surrounds players.


	// Legacy behavior helper
	if(l_range == 0)
		l_on = FALSE
	else if(l_range > 0)
		l_on = TRUE

	var/needs_update = FALSE
	if(!isnull(l_power) && l_power != light_power)
		if(!isnull(set_light_power(l_power)))
			needs_update = TRUE

	if(!isnull(l_range) && l_range != light_range)
		if(!isnull(set_light_range(l_range)))
			needs_update = TRUE

	if(l_color != NONSENSICAL_VALUE && l_color != light_color)
		if(!isnull(set_light_color(l_color)))
			needs_update = TRUE

	if(!isnull(l_on) && l_on != light_on)
		if(!isnull(set_light_on(l_on)))
			needs_update = TRUE

	if(needs_update)
		update_light()

#undef NONSENSICAL_VALUE

// Will update the light (duh).
// Creates or destroys it if needed, makes it update values, makes sure it's got the correct source turf...
/atom/proc/update_light()
	if (QDELETED(src))
		return

	if(light_system != STATIC_LIGHT)
		CRASH("update_light() for [src] with following light_system value: [light_system]")

	if (!light_on || !light_power || !light_range) // We won't emit light anyways, destroy the light source.
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
	if(isnull(.) || !isturf(loc))
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

/// Setter for the light power of this atom.
/atom/proc/set_light_power(new_power)
	if(new_power == light_power)
		return
	. = light_power
	light_power = new_power
	PUBLISH_LEGACY(src, /datum/notice/atom_update_light_power, .)

/// Setter for the light range of this atom.
/atom/proc/set_light_range(new_range)
	if(new_range == light_range)
		return
	. = light_range
	light_range = new_range
	PUBLISH_LEGACY(src, /datum/notice/atom_update_light_range, .)

/// Setter for the light color of this atom.
/atom/proc/set_light_color(new_color)
	if(new_color == light_color)
		return
	. = light_color
	light_color = new_color
	PUBLISH_LEGACY(src, /datum/notice/atom_update_light_color, .)

/// Setter for whether or not this atom's light is on.
/atom/proc/set_light_on(new_value)
	if(new_value == light_on)
		return
	. = light_on
	light_on = new_value
	PUBLISH_LEGACY(src, /datum/notice/atom_update_light_on, .)

/// Setter for the light flags of this atom.
/atom/proc/set_light_flags(new_value)
	if(new_value == light_flags)
		return
	. = light_flags
	light_flags = new_value
	PUBLISH_LEGACY(src, /datum/notice/atom_update_light_flags, .)

///Keeps track of the sources of dynamic luminosity and updates our visibility with the highest.
/atom/movable/proc/update_dynamic_luminosity()
	var/highest = 0
	var/list/adl = dq_get_affected_dynamic_lights(src)
	for(var/i in adl)
		if(adl[i] <= highest)
			continue
		highest = adl[i]
	if(highest == affecting_dynamic_lumi)
		return
	luminosity -= affecting_dynamic_lumi
	affecting_dynamic_lumi = highest
	luminosity += affecting_dynamic_lumi


///Helper to change several lighting overlay settings.
/atom/movable/proc/set_light_range_power_color(range, power, color)
	set_light_range(range)
	set_light_power(power)
	set_light_color(color)


// em_block is owned (implicit OWN, DELETE): the blocker is made at a null loc for this movable's
// overlay, and dies with it (Destroy() cuts the overlay first).
