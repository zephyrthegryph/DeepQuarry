#define WALL_FACT_INTEGRITY 1
#define WALL_FACT_EXPLOSION 2
#define WALL_FACT_CONDUCTIVITY 3
#define WALL_FACT_HEAT_CAPACITY 4
#define WALL_FACT_RAD 5
#define WALL_FACT_NAME 6
#define WALL_FACT_DESC 7

/turf/simulated/wall/proc/update_material()

	if(!material)
		return

	if(reinf_material)
		construction_stage = 6
	else
		construction_stage = null
	// The material cap is the wall's integrity; the wall keeps the damage it already has.
	// A wall is geometry around a material, not a hard-coded thermal type.
	var/material_temperature = SSair?.initialized ? get_temperature() : initial_temperature
	var/list/facts = wall_material_facts(material_temperature)
	var/missing = max_integrity - get_integrity()
	max_integrity = facts[WALL_FACT_INTEGRITY]
	update_integrity(max(1, max_integrity - missing))
	explosion_resistance = facts[WALL_FACT_EXPLOSION]
	thermal_conductivity = facts[WALL_FACT_CONDUCTIVITY]
	heat_capacity = facts[WALL_FACT_HEAT_CAPACITY]
	set_rad_insulation(facts[WALL_FACT_RAD])
	name = facts[WALL_FACT_NAME]
	desc = facts[WALL_FACT_DESC]

	if(material.opacity > 0.5 && !opacity)
		set_light(1)
	else if(material.opacity < 0.5 && opacity)
		set_light(0)

	// Inside a map-load batch every queued member joins its neighbours once at its end (BATCH_WORK_ADJACENCY).
	if(!SSatoms?.batch_defer(BATCH_WORK_ADJACENCY, src))
		update_connections(1)
		update_icon()
	if(SSair?.initialized)
		update_air_ref(0)


/// Material facts (doc/rewrite/init_and_turfs.md sec 3.1) for this wall's (material,
/// reinforcement) pair at `material_temperature`: worked out once per pair and temperature
/// and shared by every wall that has them (Southern Cross maps ~7 k walls of four materials).
/// Read-only: a caller must not change the returned list.
/turf/simulated/wall/proc/wall_material_facts(material_temperature)
	var/temperature_key = num2text(material_temperature, 12)
	return CACHED_KEY(wall_material_facts, "[MATERIAL_CACHE_ID(material)]|[reinf_material ? MATERIAL_CACHE_ID(reinf_material) : "none"]|[temperature_key]", src, material_temperature)

/// Builds the shared facts for a wall's (material, reinforcement, temperature); cleared with the
/// material facts (material_facts_changed() emits /datum/om/event/material_facts_changed).
/proc/build_wall_material_facts(turf/simulated/wall/W, material_temperature)
	var/datum/material/material = W.material
	var/datum/material/reinf_material = W.reinf_material
	var/explosion = material.explosion_resistance
	if(reinf_material && reinf_material.explosion_resistance > explosion)
		explosion = reinf_material.explosion_resistance
	var/conductance = material.thermal_conductance(2.5, 0.25, material_temperature)
	return list(
		W.material_integrity_cap(),
		explosion,
		clamp(conductance / WALL_CONDUCTANCE_PER_TRANSFER_COEFFICIENT, 0.001, WALL_MAX_HEAT_TRANSFER_COEFFICIENT),
		max(10000, material.density * material.specific_heat * 25),
		material.radiation_transmission(RAD_WALL_THICKNESS_MM),
		reinf_material ? "reinforced [material.display_name] wall" : "[material.display_name] wall",
		reinf_material ? "It seems to be a section of wall reinforced with [reinf_material.display_name] and plated with [material.display_name]." : "It seems to be a section of wall plated with [material.display_name].",
	)

DECLARE_SHARED_CACHE_EX(wall_material_facts, GLOBAL_PROC_REF(build_wall_material_facts), SC_ON_EVENT(/datum/om/event/material_facts_changed), 4096, 0)

/turf/simulated/wall/proc/set_material(datum/material/newmaterial, datum/material/newrmaterial, datum/material/newgmaterial)
	material = newmaterial
	reinf_material = newrmaterial
	if(!newgmaterial)
		girder_material = DEFAULT_WALL_MATERIAL
	else
		girder_material = newgmaterial
	update_material()
	check_radioactive()

DECLARE_APPEARANCE_PROC(/turf/simulated/wall, TYPE_PROC_REF(/atom, appearance_overlays), list("thermite"))
/turf/simulated/wall/appearance_overlays()
	. = list()
	if(!material)
		return .

	if(!damage_overlays[1]) //list hasn't been populated
		generate_overlays()

	var/image/I

	if(!density)
		I = image(wall_masks, "[material.icon_base]fwall_open")
		I.color = material.icon_colour
		. += I
		return .

	. += wall_overlay_images()
	if(thermite)
		. += wall_thermite_coat()

/// The dark coating a thermite-treated wall shows (effects.dmi "thermite"): one image shared by every coated wall.
/proc/wall_thermite_coat()
	var/static/image/coat = image('icons/effects/effects.dmi', icon_state = "thermite")
	return coat

/// The overlay images for this wall's state (doc/rewrite/init_and_turfs.md sec 3.5), built
/// once per (masks, material, reinforcement, connections, construction stage, damage step) and
/// shared by every wall in that state. Read-only: callers pass it to add_overlay(), which copies.
/turf/simulated/wall/proc/wall_overlay_images()
	var/list/connections = get_wall_connections() // interned (string_list), so usable as a key
	var/damage_step = 0
	var/damage_fraction = wall_damage_fraction()
	if(damage_fraction > 0)
		damage_step = min(round(damage_fraction * damage_overlays.len) + 1, damage_overlays.len)
	return CACHED_KEY(wall_overlay_sets, "[wall_masks]|[MATERIAL_CACHE_ID(material)]|[reinf_material ? MATERIAL_CACHE_ID(reinf_material) : "none"]|[connections.Join(",")]|[construction_stage]-[damage_step]", wall_masks, material, reinf_material, connections, construction_stage, damage_step ? damage_overlays[damage_step] : null)

DECLARE_SHARED_CACHE_EX(wall_overlay_sets, GLOBAL_PROC_REF(build_wall_overlay_sets), SC_ON_EVENT(/datum/om/event/material_facts_changed), 4096, 0)

/// Builder for wall_overlay_sets. `damage_image` is the damage overlay for the state, or null.
/proc/build_wall_overlay_sets(wall_masks, datum/material/material, datum/material/reinf_material, list/connections, construction_stage, image/damage_image)
	var/list/images = list()
	var/image/I
	for(var/i = 1 to 4)
		I = image(wall_masks, "[material.icon_base][connections[i]]", dir = 1<<(i-1))
		I.color = material.icon_colour
		images += I

	if(reinf_material)
		if(construction_stage != null && construction_stage < 6)
			I = image(wall_masks, "reinf_construct-[construction_stage]")
			I.color = reinf_material.icon_colour
			images += I
		else
			if(icon_exists(wall_masks, "[reinf_material.icon_reinf]0"))
				// Directional icon
				for(var/i = 1 to 4)
					I = image(wall_masks, "[reinf_material.icon_reinf][connections[i]]", dir = 1<<(i-1))
					I.color = reinf_material.icon_colour
					images += I
			else if(icon_exists(wall_masks, "[reinf_material.icon_reinf]"))
				I = image(wall_masks, reinf_material.icon_reinf)
				I.color = reinf_material.icon_colour
				images += I
	var/image/texture = material.get_wall_texture()
	if(texture)
		images += texture
	if(damage_image)
		images += damage_image
	return images

/turf/simulated/wall/proc/generate_overlays()
	var/alpha_inc = 256 / damage_overlays.len

	for(var/i = 1; i <= damage_overlays.len; i++)
		var/image/img = image(icon = 'icons/turf/walls.dmi', icon_state = "overlay_damage")
		img.blend_mode = BLEND_MULTIPLY
		img.alpha = (i * alpha_inc) - 1
		damage_overlays[i] = img


/// The neighbours a wall joins (its adjacency() mask, code/engine/lifeforms/adjacency.dm): faces and corners.
/turf/simulated/wall/var/smooth_mask = 0

/// adjacency() connects: a wall joins walls of a blending material and the low walls it takes.
/turf/simulated/wall/proc/smooth_joins(atom/other, bit)
	if(istype(other, /turf/simulated/wall))
		var/turf/simulated/wall/W = other
		return W.material && can_join_with_wall(W)
	if(istype(other, /obj/structure/low_wall))
		return can_join_with_low_wall(other)
	return FALSE

/// adjacency() changed: its neighbours changed; it redraws against them.
/turf/simulated/wall/proc/smooth_changed(mask)
	smooth_mask = mask
	update_connections()
	update_icon()

/turf/simulated/wall/proc/update_connections(propagate = 0)
	if(!material)
		return
	if(propagate)
		adjacency_refresh(src, TRUE) // a material change the index cannot see: this wall and its neighbours look again
	var/list/dirs = adjacency_mask_dirs(smooth_mask)
	special_wall_connections(dirs, orange(src, 1))
	wall_connections = string_list(dirs_to_corner_states(dirs))

/// wall_connections, or the unconnected corner states before update_connections() has run.
/turf/simulated/wall/proc/get_wall_connections()
	var/static/list/unconnected = list("0", "0", "0", "0")
	return wall_connections || unconnected

/turf/simulated/wall/proc/special_wall_connections(list/dirs, list/inrange)
	if(material.icon_base == "hull") // Could be improved...
		var/additional_dirs = 0
		for(var/direction in GLOB.alldirs)
			var/turf/T = get_step(src,direction)
			if(T && (locate_on(T, /obj/structure/hull_corner)))
				dirs += direction
				additional_dirs |= direction
		if(additional_dirs)
			for(var/diag_dir in GLOB.cornerdirs)
				if ((additional_dirs & diag_dir) == diag_dir)
					dirs += diag_dir

/turf/simulated/wall/proc/can_join_with_wall(turf/simulated/wall/W)
	//No blending if no material
	if(!material || !W.material)
		return 0
	//We can blend if either is the same, or a subtype, of the other one
	if(istype(W.material, material.type) || istype(material, W.material.type))
		return 1
	//Also blend if they have the same iconbase
	if(material.icon_base == W.material.icon_base)
		return 1
	return 0

/turf/simulated/wall/proc/can_join_with_low_wall(obj/structure/low_wall/WF)
	return FALSE

#undef WALL_FACT_INTEGRITY
#undef WALL_FACT_EXPLOSION
#undef WALL_FACT_CONDUCTIVITY
#undef WALL_FACT_HEAT_CAPACITY
#undef WALL_FACT_RAD
#undef WALL_FACT_NAME
#undef WALL_FACT_DESC
