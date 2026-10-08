
/turf/simulated/floor/water/underwater
	name = "sea floor"
	desc = "It's the bottom of the sea, there's water all over the place!"
	icon = 'icons/turf/outdoors.dmi'
	icon_state = "seafloor" // So it shows up in the map editor as water.
	water_state = "seafloor"
	edge_blending_priority = -1
	movement_cost = 4
	can_be_plated = FALSE
	outdoors = OUTDOORS_YES
	flags = TURF_ACID_IMMUNE

	can_dirty = FALSE	// It's water

	depth = 10 // Higher numbers indicates deeper water, 10 is unused right now, but may be useful for adding effects in the future.

	reagent_type = REAGENT_ID_WATER

/turf/simulated/floor/water/underwater/return_air_for_internal_lifeform(mob/living/L)
	if(L.can_breathe_water()) // For squid.
		var/datum/gas_mixture/water_breath = new()
		var/datum/gas_mixture/above_air = return_air()
		var/amount = 300
		water_breath.adjust_gas(GAS_O2, amount) // Assuming water breathes just extract the oxygen directly from the water.
		heat_set(water_breath, above_air.return_temperature())
		return water_breath
	else
		var/gasid = GAS_CO2
		if(ishuman(L))
			var/mob/living/carbon/human/H = L
			if(H.species && H.species.exhale_type)
				gasid = H.species.exhale_type
		var/datum/gas_mixture/water_breath = new()
		var/datum/gas_mixture/above_air = return_air()
		water_breath.adjust_gas(gasid, BREATH_MOLES) // They have no oxygen, but non-zero moles and temp
		heat_set(water_breath, above_air.return_temperature())
		return water_breath

/turf/simulated/floor/water/underwater/Entered(atom/movable/AM, atom/oldloc)
	if(isliving(AM))
		var/mob/living/L = AM
		L.update_water()
		if(L.check_submerged() <= 0)
			return
		if(!istype(oldloc, /turf/simulated/floor/water/underwater))
			to_chat(L, span_warning("You get drenched in water from entering \the [src]!"))
	AM.water_act(5)
	..()

/turf/simulated/floor/water/underwater/Exited(atom/movable/AM, atom/newloc)
	if(isliving(AM))
		var/mob/living/L = AM
		L.update_water()
		if(L.check_submerged() <= 0)
			return
		if(!istype(newloc, /turf/simulated/floor/water/underwater))
			to_chat(L, span_warning("You climb out of \the [src]."))
	..()

/turf/simulated/floor/water/deep/ocean/diving

/turf/simulated/floor/water/deep/ocean/diving/CanZPass(atom, direction)
	return TRUE

//Variations of underwater icons


/turf/simulated/floor/water/underwater/open
	icon = 'icons/effects/weather.dmi'
	icon_state = "underwater-indoors" // Just looks underwater in the map editor, will be invisible once ingame
	name = "deeper waters"
	desc = "The watery depths seem to go even deeper here."

DECLARE_SHARED_CACHE(underwater_visuals, GLOBAL_PROC_REF(build_underwater_visuals), SC_NEVER)

/// Builder for underwater_visuals: the weather layer an underwater tile shows through its vis_contents, one shared atom per icon and state.
/proc/build_underwater_visuals(visuals_icon, visuals_state)
	var/atom/movable/weather_visuals/visuals = new(null)
	visuals.icon = visuals_icon
	visuals.icon_state = visuals_state
	return visuals

/turf/simulated/floor/water/underwater/open/draw(datum/look/look)
	..()
	look.set_icon('icons/turf/open_space.dmi')
	look.state("black_open_lighter")

/turf/simulated/floor/water/underwater/open/edge_look_state()
	return "black_open_lighter"

/turf/simulated/floor/water/underwater/open/sim_after_init(datum/act/timer/A)
	..()
	make_z_transparent(FALSE)

/turf/simulated/floor/water/underwater/open/CanZPass(atom/A, direction, recursive)
	return TRUE

/// We'll rely on the turfs below for water visuals!
/turf/simulated/floor/water/underwater/open/look_water(datum/look/look)
	look.show(CACHED_KEY(underwater_visuals, "underwater", 'icons/effects/weather.dmi', "underwater"))

// Indoors variants that do not use outdoor lighting, and must re-add water overlay icons since they won't be relying on the weather system to do it!

/turf/simulated/floor/water/underwater/indoors
	outdoors = OUTDOORS_NO
	var/overlay_icon = 'icons/effects/weather.dmi'
	var/overlay_state = "underwater-indoors"

/// They must re-add the water visuals, since they won't be relying on the weather system to do it!
/turf/simulated/floor/water/underwater/indoors/look_water(datum/look/look)
	look.show(CACHED_KEY(underwater_visuals, "[overlay_icon]:[overlay_state]", overlay_icon, overlay_state))

/// It sets no bed state of its own: it shows the state the tile has.
/turf/simulated/floor/water/underwater/indoors/edge_look_state()
	return icon_state

/turf/simulated/floor/water/underwater/indoors/open
	icon = 'icons/effects/weather.dmi'
	icon_state = "underwater-indoors" // Just looks underwater in the map editor, will be invisible once ingame
	name = "deeper waters"
	desc = "The watery depths seem to go even deeper here."

/turf/simulated/floor/water/underwater/indoors/open/sim_after_init(datum/act/timer/A)
	..()
	make_z_transparent(FALSE)

/turf/simulated/floor/water/underwater/indoors/open/draw(datum/look/look)
	..()
	look.set_icon('icons/turf/open_space.dmi')
	look.state("black_open_lighter")

/turf/simulated/floor/water/underwater/indoors/open/edge_look_state()
	return "black_open_lighter"

/turf/simulated/floor/water/underwater/indoors/open/CanZPass(atom/A, direction, recursive)
	return TRUE

