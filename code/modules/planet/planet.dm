// This holds information about a specific 'planetside' area, such as its time, weather, etc.  This will most likely be used to model Sif,
// but away missions may also have use for this.

/datum/planet
	var/name = "a rock"
	var/desc = "Someone neglected to write a nice description for this poor rock."

	var/datum/time/current_time = new() // Holds the current time for sun positioning.  Note that we assume day and night is the same length because simplicity.
	var/sun_process_interval = 1 HOUR
	/// When the sun next updates.
	COOLDOWN_DECLARE(next_sun_process)

	var/datum/weather_holder/weather_holder
	var/datum/sun_holder/sun_holder

	var/sun_position = 0 // 0 means midnight, 1 means noon.
	var/list/sun = list("brightness","color") // ALLOW(instance_list): d: edited in place per instance (2 writers)
	var/list/expected_z_levels

	var/planetary_wall_type = /turf/unsimulated/wall/planetary

	var/list/turf/simulated/floor/planet_floors
	var/list/turf/unsimulated/wall/planetary/planet_walls

	EXPIRY_TMP_DECLARE(last_step)
	var/needs_work = 0 // Bitflags to signal to the planet controller these need (properly deferrable) work. Flags defined in controller.

	var/sun_name = "the sun" // For flavor.

	var/moon_name = null // Purely for flavor. Null means no moon exists.
	var/moon_phase = null // Set if above is defined.

/// The planet's clock, weather and sun run (the planet service sets it when it makes the planet).
/datum/planet/var/clock_running = FALSE
TRACKED(/datum/planet, clock_running)
CAPABILITIES(/datum/planet)
	every(2 SECONDS, then(PROC_REF(planet_step)), when = nameof(clock_running))
	ref_many(nameof(planet_floors))
	ref_many(nameof(planet_walls))
	owns_one(nameof(current_time), /datum/time)
	owns_one(nameof(sun_holder), /datum/sun_holder)
	owns_one(nameof(weather_holder), /datum/weather_holder)

/datum/planet/New()
	..()
	rel_set(src, nameof(weather_holder), new /datum/weather_holder(src))
	rel_set(src, nameof(sun_holder), new /datum/sun_holder(src))
	rel_set(src, nameof(current_time), current_time.make_random_time())
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

/// every(), 2 s while clock_running (the planet service starts every planet): the planet's clock, weather and
/// sun. Lighting and wall temperature changes queue on the planet service, which applies them in batches.
/datum/planet/proc/planet_step(datum/act/timer/A)
	if(current_time)
		var/difference = last_step ? world.time - last_step : A.dt
		rel_set(src, nameof(current_time), current_time.add_seconds((difference / 10) * PLANET_TIME_MODIFIER))
	EXPIRY_STAMP(src, last_step, CLOCK_WORLD)
	update_weather() // We update this first, because some weather types decease the brightness of the sun.
	if(COOLDOWN_FINISHED(src, next_sun_process))
		update_sun()
	if(needs_work & PLANET_PROCESS_SUN)
		needs_work &= ~PLANET_PROCESS_SUN
		SSplanets.needs_sun_update |= src
	if(needs_work & PLANET_PROCESS_TEMP)
		needs_work &= ~PLANET_PROCESS_TEMP
		SSplanets.needs_temp_update |= src
	SSplanets.wake_updates()

// This changes the position of the sun on the planet.
/datum/planet/proc/update_sun()
	COOLDOWN_START(src, next_sun_process, sun_process_interval)

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

// Turfs are never deleted.

// The planet's turfs are relation lists: a released z-level (relation_drop_z) clears them.
