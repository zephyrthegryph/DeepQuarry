// This holds information about a specific 'planetside' area, such as its time, weather, etc.  This will most likely be used to model Sif,
// but away missions may also have use for this.

/datum/planet
	var/name = "a rock"
	var/desc = "Someone neglected to write a nice description for this poor rock."

	var/datum/time/current_time = new() // Holds the current time for sun positioning.  Note that we assume day and night is the same length because simplicity.
	var/sun_process_interval = 1 HOUR
	var/sun_last_process = null // world.time

	var/datum/weather_holder/weather_holder
	var/datum/sun_holder/sun_holder

	var/sun_position = 0 // 0 means midnight, 1 means noon.
	var/list/sun = list("brightness","color")
	var/list/expected_z_levels

	var/planetary_wall_type = /turf/unsimulated/wall/planetary

	var/list/turf/simulated/floor/planet_floors
	var/list/turf/unsimulated/wall/planetary/planet_walls

	var/tmp/last_step = 0
	var/needs_work = 0 // Bitflags to signal to the planet controller these need (properly deferrable) work. Flags defined in controller.

	var/sun_name = "the sun" // For flavor.

	var/moon_name = null // Purely for flavor. Null means no moon exists.
	var/moon_phase = null // Set if above is defined.

/datum/planet/New()
	..()
	weather_holder = new(src)
	sun_holder = new(src)
	current_time = current_time.make_random_time()
	if(moon_name)
		moon_phase = pick(list(
			MOON_PHASE_NEW_MOON,
			MOON_PHASE_WAXING_CRESCENT,
			MOON_PHASE_FIRST_QUARTER,
			MOON_PHASE_WAXING_GIBBOUS,
			MOON_PHASE_FULL_MOON,
			MOON_PHASE_WANING_GIBBOUS,
			MOON_PHASE_LAST_QUARTER,
			MOON_PHASE_WANING_CRESCENT
			))
	update_sun()

/// Every 2 s on the slow lane (SSplanets starts every planet): the planet's clock, weather and
/// sun. Lighting and wall temperature changes queue on SSplanets, which applies them in batches.
/datum/planet/periodic_step(delta)
	if(current_time)
		var/difference = last_step ? world.time - last_step : delta
		current_time = current_time.add_seconds((difference / 10) * PLANET_TIME_MODIFIER)
	last_step = world.time
	update_weather() // We update this first, because some weather types decease the brightness of the sun.
	if(sun_last_process <= world.time - sun_process_interval)
		update_sun()
	if(needs_work & PLANET_PROCESS_SUN)
		needs_work &= ~PLANET_PROCESS_SUN
		SSplanets.needs_sun_update |= src
	if(needs_work & PLANET_PROCESS_TEMP)
		needs_work &= ~PLANET_PROCESS_TEMP
		SSplanets.needs_temp_update |= src

// This changes the position of the sun on the planet.
/datum/planet/proc/update_sun()
	sun_last_process = world.time

/datum/planet/proc/update_weather()
	if(weather_holder)
		weather_holder.weather_tick()

/datum/planet/proc/update_sun_deferred(new_brightness, new_color)
	sun["brightness"] = CLAMP01(new_brightness)
	sun["color"] = new_color
	needs_work |= PLANET_PROCESS_SUN

/// Override for unique sun angle handling for stuff like northern/southern hemisphere sun angles during the day cycle
/datum/planet/proc/get_sun_solar_position()
	return 220 - (sun_position * 80) // this base version doesn't know how long a planet's day is, so just goes back and forth facing south-eastish based on midnight to noon intensity

REF_OWNED(/datum/planet, list("weather_holder", "sun_holder"))
