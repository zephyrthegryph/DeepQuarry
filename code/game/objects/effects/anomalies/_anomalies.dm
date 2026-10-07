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
	EXPIRY_DECLARE(death_time)

	var/countdown_colour
	var/obj/effect/countdown/anomaly/countdown

	var/immortal = FALSE
	var/move_chance = ANOMALY_MOVECHANCE

	// Anomaly harvesting stuff
	var/datum/anomaly_stats/stats
	var/danger_mult = 1

	// An anomaly acts only while a player is near (the proximity tracker, code/controllers/subsystems/proximity.dm).
	proximity_tracked = TRUE

CAPABILITIES(/obj/effect/anomaly)
	every(2 SECONDS, then(PROC_REF(anomaly_step)), when = STAT_RELEVANCE)
	owns_one(nameof(anomaly_core), /obj/item/assembly/signaler/anomaly)
	owns_one(nameof(stats), /datum/anomaly_stats)
	owns_one(nameof(countdown), starts = /obj/effect/countdown/anomaly)
	op("scan_anomaly", item(/obj/item), then(PROC_REF(interaction_scan_anomaly)))
	param(nameof(lifespan), pos = 1)
	param(nameof(drops_core), pos = 2)

/// Whether the anomaly leaves its core (its constructor param).
/obj/effect/anomaly/var/drops_core = TRUE

// ALLOW(init/INSTANCE_STATE): an anomaly needs an area, makes its core with a random frequency and code, and counts down its lifespan
/obj/effect/anomaly/Initialize(mapload)
	. = ..()

	impact_area = get_area(src)

	if(!impact_area())
		return INITIALIZE_HINT_QDEL

	if(!drops_core)
		rel_clear(src, nameof(anomaly_core)) // still the type path here, or a core made early

	if(anomaly_core)
		rel_set(src, nameof(anomaly_core), new anomaly_core(src))
		anomaly_core.set_frequency(sanitize_frequency(rand(PUBLIC_LOW_FREQ, PUBLIC_HIGH_FREQ)))
		anomaly_core.code = rand(1, 100)
		anomaly_core.anomaly_type = type

	EXPIRY_SET(src, death_time, lifespan, CLOCK_WORLD)

	if(countdown_colour)
		countdown.color = countdown_colour

	if(immortal)
		return
	countdown.start()
	after(src, lifespan, PROC_REF(lifespan_over))

/// The anomaly's lifespan ended (its timer): it detonates whether or not anyone is near.
/obj/effect/anomaly/proc/lifespan_over()
	if(immortal || QDELETED(src))
		return
	if(loc)
		detonate()
	consume(src)

/// Acts only while a player is near (STAT_RELEVANCE); otherwise the every() parks until one comes near.
/obj/effect/anomaly/proc/anomaly_step(datum/act/timer/A)
	anomalyEffect(2) // seconds per step: the every() interval
	anomalyPulse()

/obj/effect/anomaly/proc/anomalyEffect(seconds_per_tick)
	if(prob(move_chance) && !locate_within(get_turf(src), /obj/effect/suspension_field))
		move_anomaly()

// Used in anomaly harvesting - Normal anomalies shouldn't pulse
/obj/effect/anomaly/proc/anomalyPulse()
	if(!stats)
		return FALSE
	if(EXPIRY_ACTIVE(stats, next_activation, CLOCK_WORLD))
		return FALSE

	stats.pulse_effect()
	if(QDELETED(src))
		return FALSE
	EXPIRY_SET(stats, next_activation, rand(stats.min_activation, stats.max_activation), CLOCK_WORLD)
	return TRUE

/obj/effect/anomaly/proc/move_anomaly()
	step(src, pick(GLOB.alldirs))

/obj/effect/anomaly/proc/detonate()
	return

/obj/effect/anomaly/ex_act(strength)
	if(strength <= 1)
		consume(src)
		return TRUE
	return FALSE

/obj/effect/anomaly/proc/anomalyNeutralize()
	new /obj/effect/effect/smoke(loc)
	if(!isnull(anomaly_core))
		anomaly_core.forceMove(get_turf(src))
		rel_clear(src, nameof(anomaly_core)) // still the type path here, or a core made early
	consume(src)

/obj/effect/anomaly/proc/stabilize(anchor = FALSE, has_core = TRUE, add_stats = FALSE)
	immortal = TRUE
	name = (has_core ? "stable " : "hollow ") + name
	if(!has_core)
		rel_clear(src, nameof(anomaly_core))
	if(anchor)
		move_chance = 0
	if(!stats && add_stats)
		rel_set(src, nameof(stats), new /datum/anomaly_stats)
		rel_set(stats, nameof(stats.attached_anomaly), src)
		stats.calculate_points()
		set_density(TRUE)
	return

/// Old attackby: analyzers read a stabilized core's frequency; anomaly scanners buffer the anomaly.
/obj/effect/anomaly/proc/interaction_scan_anomaly(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	var/obj/item/I = held
	if(istype(I, /obj/item/analyzer) || (istype(I, /obj/item/anomaly_scanner) && !stats))
		if(anomaly_core)
			to_chat(user, span_notice("Analyzing... [src]'s stabilized field is fluctuating along frequency [format_frequency(anomaly_core.frequency)], code [anomaly_core.code]."))
			return TRUE
	if(istype(I, /obj/item/anomaly_scanner) && stats)
		var/obj/item/anomaly_scanner/scanner = I
		task_timed(user, 1 SECOND, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done), done_args = list(user, scanner))
		return TRUE
	return OP_DECLINE

/obj/effect/anomaly/proc/attackby_timed_done(mob/user, obj/item/anomaly_scanner/scanner)
	rel_set(scanner, nameof(scanner.buffered_anomaly), src)
	scanner.tgui_interact(user)
	return TRUE

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

/// The impact area (an area: a plain var).
/obj/effect/anomaly/proc/impact_area() as /area
	return impact_area
