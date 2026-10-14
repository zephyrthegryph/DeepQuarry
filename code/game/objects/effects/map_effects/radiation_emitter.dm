// Constantly emites radiation from the tile it's placed on.
/obj/effect/map_effect/radiation_emitter
	name = "radiation emitter"
	icon_state = "radiation_emitter"
	var/range = 3
	var/radiation_power = 30 // Bigger numbers means more radiation.
	COOLDOWN_DECLARE(event_cooldown)
	/// Mutex to prevent infinite recursion when propagating radiation pulses
	var/active = null
	var/strength = 50

/// Radiates only while a client is near (STAT_RELEVANCE, a map effect is proximity tracked): otherwise the every() parks.
CAPABILITIES(/obj/effect/map_effect/radiation_emitter)
	every(2 SECONDS, then(PROC_REF(radiation_emitter_step)), when = STAT_RELEVANCE)

/obj/effect/map_effect/radiation_emitter/proc/radiation_emitter_step(datum/act/timer/A)
	radiate()

/obj/effect/map_effect/radiation_emitter/proc/radiate()
	if(active)
		return
	if(!COOLDOWN_FINISHED(src, event_cooldown))
		return
	active = TRUE
	radiation_pulse(
		src,
		max_range = range,
		threshold = RAD_LIGHT_INSULATION,
		chance = radiation_power,
		minimum_exposure_time = URANIUM_RADIATION_MINIMUM_EXPOSURE_TIME,
		strength = strength
	)
	COOLDOWN_START(src, event_cooldown, 1.5 SECONDS)
	active = FALSE

/obj/effect/map_effect/radiation_emitter/strong
	range = 7
	radiation_power = 100
	strength = 250
