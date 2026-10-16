// The light an atom casts (doc/rewrite/proposals/base_vars.md, "Light"). There are no light_range / light_power / light_color vars on /atom.
//
//	CAPABILITIES(/obj/machinery/floor_light)
//		configure(light_glow(range = 3, color = "#ffffff"))   // the type's light: per-type data, no instance cost
//	set_glow(src, GLOW(5, null, null))                       // a run-time change (what set_glow(src, GLOW(null, null, null)) did): null keeps that part
//	set_glow(src, GLOW_OFF)                                  // dark
//	glow_of(A).range / .power / .color                       // what the light system casts; glow_of_type(path) for a type's declaration
//
// A type's light is a type trait (code/engine/declare/type_traits.dm): a light_on gate decides whether it is cast, so a lamp that starts off
// declares its light and turns it on later. set_glow() gives the atom its own copy (set_trait()) and, as set_glow(src, GLOW(null, null, null)) did, turns the light on
// for a range above 0 and off for 0. A look's light (look.glow(), look_glow()) goes through set_glow() too. The light system
// (update_light(), /datum/light_source, overlay lighting) reads only glow_of().

STATIC_ENTRY(light_glow)

/proc/light_glow(range = null, power = null, color = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_LIGHT_GLOW, null, list("range" = range, "power" = power, "color" = color))

/datum/type_trait/light_glow
	/// Range in tiles; 0 is no light.
	var/range = 0
	/// Intensity: the stronger, the fewer shadows on the lit area.
	var/power = 1
	/// The colour, an RGB string.
	var/color = COLOR_WHITE

/datum/type_trait/light_glow/copy_values(datum/type_trait/light_glow/into)
	into.range = range
	into.power = power
	into.color = color

/datum/entry_engine/type_trait/light_glow
	kind = ENTRY_LIGHT_GLOW
	trait_type = /datum/type_trait/light_glow
	publish_key = LIGHT_GLOW_KEY
	base_type = /atom
	var_names = list("light_range" = "range", "light_power" = "power", "light_color" = "color")

/// The light `A` casts while its light is on (its own values once set_glow() wrote one). Read only.
READS_AS(/proc/glow_of, LIGHT_GLOW_KEY)
/proc/glow_of(atom/A) as /datum/type_trait/light_glow
	READS_FROM(A)
	return type_trait_of(A, ENTRY_LIGHT_GLOW)

/// The light a type declares (no instance): the old initial(light_range).
/proc/glow_of_type(type) as /datum/type_trait/light_glow
	READS_FROM() // declared per type: constant
	return type_trait_of_type(type, ENTRY_LIGHT_GLOW)

/**
 * Sets the light `A` casts: `glow` is GLOW(range, power, color), a null part keeping the current one. As set_glow(src, GLOW(null, null, null)) did, a range above 0
 * turns the light on and 0 turns it off; a range below MINIMUM_USEFUL_LIGHT_RANGE is raised to it. Returns TRUE when anything changed.
 */
/// FALSE for an atom that never casts a light, whatever sets one (a fancy shuttle wall).
/atom/proc/accepts_glow()
	return TRUE

/proc/set_glow(atom/A, list/glow, on = null)
	if(isnull(A) || QDELETED(A) || !islist(glow) || !A.accepts_glow())
		return FALSE
	var/range = length(glow) >= 1 ? glow[1] : null
	var/power = length(glow) >= 2 ? glow[2] : null
	var/color = length(glow) >= 3 ? glow[3] : null
	if(range > 0 && range < MINIMUM_USEFUL_LIGHT_RANGE)
		range = MINIMUM_USEFUL_LIGHT_RANGE // just brighter than the soft light around players
	if(isnull(on) && !isnull(range))
		on = range > 0
	var/changed = FALSE
	if(!isnull(power) && A.set_light_power(power) != null)
		changed = TRUE
	if(!isnull(range) && A.set_light_range(range) != null)
		changed = TRUE
	if(!isnull(color) && A.set_light_color(color) != null)
		changed = TRUE
	if(!isnull(on) && A.set_light_on(on) != null)
		changed = TRUE
	if(changed && lighting_of(A).system == STATIC_LIGHT)
		A.update_light()
	return changed

// Lighting transport and emissive configuration is shared per type; only runtime overrides allocate.
STATIC_ENTRY(lighting_config)

/proc/lighting_config(system = null, flags = null, cone_x = null, cone_y = null, emissive = null)
	return entry_make(ENTRY_LIGHTING_CONFIG, null, list("system" = system, "flags" = flags, "cone_x" = cone_x, "cone_y" = cone_y, "emissive" = emissive))

/datum/type_trait/lighting_config
	var/system = STATIC_LIGHT
	var/flags = NONE
	var/cone_x
	var/cone_y
	var/emissive = EMISSIVE_BLOCK_NONE

/datum/type_trait/lighting_config/copy_values(datum/type_trait/lighting_config/into)
	into.system = system
	into.flags = flags
	into.cone_x = cone_x
	into.cone_y = cone_y
	into.emissive = emissive

/datum/entry_engine/type_trait/lighting_config
	kind = ENTRY_LIGHTING_CONFIG
	trait_type = /datum/type_trait/lighting_config
	publish_key = LIGHTING_CONFIG_KEY
	base_type = /atom
	var_names = list("light_system" = "system", "light_flags" = "flags", "light_cone_x_offset" = "cone_x", "light_cone_y_offset" = "cone_y", "blocks_emissive" = "emissive")

READS_AS(/proc/lighting_of, LIGHTING_CONFIG_KEY)
/proc/lighting_of(atom/A) as /datum/type_trait/lighting_config
	READS_FROM(A)
	if(!A)
		return null
	return type_trait_of(A, ENTRY_LIGHTING_CONFIG)

/proc/lighting_of_type(type) as /datum/type_trait/lighting_config
	READS_FROM()
	return type_trait_of_type(type, ENTRY_LIGHTING_CONFIG)
