/obj/effect/anomaly
	name = "anomaly"
	desc = "A mysterious anomaly, seen commonly only in the region of space that the station orbits..."
	icon = 'icons/effects/anomalies.dmi'
	icon_state = "vortex"
	density = FALSE
	anchored = TRUE
	light_range = 3

	var/obj/item/assembly/signaler/anomaly/anomaly_core = /obj/item/assembly/signaler/anomaly
	var/area/impact_area

	var/lifespan = ANOMALY_COUNTDOWN_TIMER
	var/death_time

	var/countdown_colour
	var/obj/effect/countdown/anomaly/countdown

	var/immortal = FALSE
	var/move_chance = ANOMALY_MOVECHANCE

	// Anomaly harvesting stuff
	var/datum/anomaly_stats/stats
	var/danger_mult = 1

	/// REACT_AT token for the anomaly's despawn deadline; null when not scheduled (immortal, or not armed yet).
	var/tmp/death_timer
	/// REACT_AT token for the next harvesting pulse; null when not scheduled (no stats yet).
	var/tmp/pulse_timer

/obj/effect/anomaly/Initialize(mapload, new_lifespan, drops_core = TRUE)
	. = ..()

	REACT_PROCESS(src, 2 SECONDS, "moves at random and drives its unique effect every tick while it lives")
	impact_area = get_area(src)

	if(!impact_area)
		return INITIALIZE_HINT_QDEL

	if(!drops_core)
		anomaly_core = null

	if(anomaly_core)
		anomaly_core = new anomaly_core(src)
		anomaly_core.set_frequency(sanitize_frequency(rand(PUBLIC_LOW_FREQ, PUBLIC_HIGH_FREQ)))
		anomaly_core.code = rand(1, 100)
		anomaly_core.anomaly_type = type

	if(new_lifespan)
		lifespan = new_lifespan
	death_time = world.time + lifespan

	countdown = new(src)
	if(countdown_colour)
		countdown.color = countdown_colour

	if(immortal)
		return
	countdown.start()
	death_timer = REACT_REARM(src, death_timer, death_time)

/obj/effect/anomaly/process(seconds_per_tick)
	anomalyEffect(seconds_per_tick)
	// stats can be set directly by callers that bypass stabilize() (e.g. the
	// suspension field generator); catch those and arm the pulse timer lazily.
	if(stats && !pulse_timer)
		pulse_timer = REACT_REARM(src, pulse_timer, max(stats.next_activation, world.time))

/obj/effect/anomaly/on_react(reason, source, source_kind)
	. = ..()
	if(!(reason & REACT_REASON_TIMER))
		return
	if(source == death_timer)
		death_timer = null
		if(!immortal)
			if(loc)
				detonate()
			qdel(src)
		return
	if(source == pulse_timer)
		pulse_timer = null
		anomalyPulse()

/obj/effect/anomaly/Destroy()
	REACT_PROCESS_STOP(src)
	QDEL_NULL(countdown)
	QDEL_NULL(anomaly_core)
	if(stats)
		QDEL_NULL(stats)
	return ..()

/obj/effect/anomaly/proc/anomalyEffect(seconds_per_tick)
	if(prob(move_chance) && !locate(/obj/effect/suspension_field) in get_turf(src))
		move_anomaly()

// Used in anomaly harvesting - Normal anomalies shouldn't pulse
/obj/effect/anomaly/proc/anomalyPulse()
	if(!stats)
		return FALSE

	stats.pulse_effect()
	if(QDELETED(src))
		return FALSE
	stats.next_activation = world.time + rand(stats.min_activation, stats.max_activation)
	pulse_timer = REACT_REARM(src, pulse_timer, stats.next_activation)
	return TRUE

/obj/effect/anomaly/proc/move_anomaly()
	step(src, pick(GLOB.alldirs))

/obj/effect/anomaly/proc/detonate()
	return

/obj/effect/anomaly/ex_act(strength)
	if(strength <= 1)
		qdel(src)
		return TRUE
	return FALSE

/obj/effect/anomaly/proc/anomalyNeutralize()
	new /obj/effect/effect/smoke(loc)
	if(!isnull(anomaly_core))
		anomaly_core.forceMove(get_turf(src))
		anomaly_core = null
	qdel(src)

/obj/effect/anomaly/proc/stabilize(anchor = FALSE, has_core = TRUE, add_stats = FALSE)
	immortal = TRUE
	death_timer = REACT_REARM(src, death_timer, null)
	name = (has_core ? "stable " : "hollow ") + name
	if(!has_core)
		QDEL_NULL(anomaly_core)
	if(anchor)
		move_chance = 0
	if(!stats && add_stats)
		stats = new /datum/anomaly_stats
		stats.attached_anomaly = WEAKREF(src)
		stats.calculate_points()
		density = TRUE
		pulse_timer = REACT_REARM(src, pulse_timer, world.time)
	return

/obj/effect/anomaly/attackby(obj/item/I, mob/user)
	if(istype(I, /obj/item/analyzer) || (istype(I, /obj/item/anomaly_scanner) && !stats))
		if(anomaly_core)
			to_chat(user, span_notice("Analyzing... [src]'s stabilized field is fluctuating along frequency [format_frequency(anomaly_core.frequency)], code [anomaly_core.code]."))
			return TRUE
	if(istype(I, /obj/item/anomaly_scanner) && stats)
		var/obj/item/anomaly_scanner/scanner = I
		if(!do_after(user, 1 SECOND, src))
			return
		scanner.buffered_anomaly = WEAKREF(src)
		scanner.tgui_interact(user)
		return TRUE
	return ..()

/obj/effect/anomaly/bullet_act(obj/item/projectile/proj)
	if(stats && istype(stats.modifier, /datum/anomaly_modifiers/reflective) && prob(stats.severity/1.5))
		balloon_alert_visible("reflected!")

		var/new_x = proj.x = pick(0, 0, 0, -1, 1, -2, 2)
		var/new_y = proj.y = pick(0, 0, 0, -1, 1, -2, 2)

		var/turf/curloc = get_step(proj, get_dir(proj, proj.starting))

		proj.penetrating += 1

		proj.redirect(new_x, new_y, curloc, null)
		return FALSE

	if(istype(proj, /obj/item/projectile/energy/anomaly))
		var/obj/item/projectile/energy/anomaly/anom_proj = proj
		if(stats)
			stats.particle_hit(anom_proj.particle_type)

	return FALSE

/proc/generate_anomaly(turf/anomalycenter, type = FLUX_ANOMALY, anomalyrange = 5, has_changed_lifespan = TRUE, drops_core = TRUE)
	var/turf/local_turf = pick(RANGE_TURFS(anomalyrange, anomalycenter))
	if(!local_turf)
		return
	switch(type)
		if(FLUX_ANOMALY)
			var/explosive = has_changed_lifespan ? FLUX_NO_EMP : FLUX_LIGHT_EMP
			new /obj/effect/anomaly/flux(local_turf, has_changed_lifespan ? rand(25 SECONDS, 35 SECONDS) : null, drops_core, explosive)
		if(GRAVITATIONAL_ANOMALY)
			new /obj/effect/anomaly/grav(local_turf, has_changed_lifespan ? rand(20 SECONDS, 30 SECONDS) : null, drops_core)
		if(PYRO_ANOMALY)
			new /obj/effect/anomaly/pyro(local_turf, has_changed_lifespan ? rand(15 SECONDS, 25 SECONDS) : null, drops_core)
		if(HALLUCINATION_ANOMALY)
			new /obj/effect/anomaly/hallucination/supermatter(local_turf, has_changed_lifespan ? rand(15 SECONDS, 25 SECONDS) : null, drops_core)
		if(BIOSCRAMBLER_ANOMALY)
			new /obj/effect/anomaly/bioscrambler/docile(local_turf, null, drops_core)
		if(DIMENSIONAL_ANOMALY)
			new /obj/effect/anomaly/dimensional(local_turf, null, drops_core)
		if(WEATHER_ANOMALY)
			new /obj/effect/anomaly/weather(local_turf, null, drops_core)
		if(DUST_ANOMALY)
			new /obj/effect/anomaly/dust(local_turf, null, drops_core)
