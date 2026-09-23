// Constantly emites radiation from the tile it's placed on.
/obj/effect/map_effect/radiation_emitter
	name = "radiation emitter"
	icon_state = "radiation_emitter"
	var/range = 3
	var/radiation_power = 30 // Bigger numbers means more radiation.
	var/last_event = 0
	/// Mutex to prevent infinite recursion when propagating radiation pulses
	var/active = null
	var/strength = 50
	/// REACT_AT token for the next radiation pulse; null when not scheduled.
	var/tmp/radiate_timer

/obj/effect/map_effect/radiation_emitter/on_react(reason, source, source_kind)
	. = ..()
	if(!(reason & REACT_REASON_TIMER) || source != radiate_timer)
		return
	radiate_timer = null
	radiate()
	radiate_timer = REACT_REARM(src, radiate_timer, world.time + 1.5 SECONDS)

/obj/effect/map_effect/radiation_emitter/proc/radiate()
	if(active)
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
	last_event = world.time
	active = FALSE


/obj/effect/map_effect/radiation_emitter/Initialize(mapload)
	radiate_timer = REACT_REARM(src, radiate_timer, world.time)
	return ..()

/obj/effect/map_effect/radiation_emitter/Destroy()
	radiate_timer = REACT_REARM(src, radiate_timer, null)
	return ..()

/obj/effect/map_effect/radiation_emitter/strong
	range = 7
	radiation_power = 100
	strength = 250
