/obj/effect/anomaly/weather
	name = "weather anomaly"
	icon_state = "weather"
	anomaly_core = /obj/item/assembly/signaler/anomaly/weather
	lifespan = ANOMALY_COUNTDOWN_TIMER * 2.5
	var/telegraph_percent = 7

	/// Areas are plain vars (not relation targets).
	var/list/area/affected_areas
	/// Relation list view: the turfs the weather acts on.
	var/list/turf/affected_turfs

	var/datum/anomalous_weather/selected_weather

	var/is_raining = FALSE

CAPABILITIES(/obj/effect/anomaly/weather)
	owns_one(nameof(selected_weather), /datum/anomalous_weather, starts = PROC_REF(make_weather))

/obj/effect/anomaly/weather/Initialize(mapload, new_lifespan, drops_core)
	. = ..()

	LAZYADD(affected_areas, impact_area())

	var/telegraph = lifespan / telegraph_percent

	for(var/spread_dir in GLOB.alldirs)
		var/area/nearby = find_adjacent_impacted_area(spread_dir)
		if(isnull(nearby) || nearby.flag_check(AREA_FORBID_EVENTS))
			continue
		if(istype(nearby, /area/space))
			continue
		LAZYOR(affected_areas, nearby)

	for(var/area/area in affected_areas)
		for(var/mob/mob in area)
			to_chat(mob, span_notice(selected_weather.telegraph_message))
		for(var/turf/turf in area)
			if(isopenturf(turf))
				rel_add(src, nameof(affected_turfs), GetBelow(turf))
			rel_add(src, nameof(affected_turfs), turf)

	apply_wibbly_filters(src)

	after(src, telegraph, PROC_REF(start_weather))

/obj/effect/anomaly/weather/proc/add_turfs(list/turf/to_add)
	for(var/turf/turf in to_add)
		if(isspace(turf))
			continue
		rel_add(src, nameof(affected_turfs), turf)

/obj/effect/anomaly/weather/proc/find_adjacent_impacted_area(check_dir)
	var/limit = 10
	var/turf/next_turf = get_step(src, check_dir)
	while(next_turf.loc == impact_area() && limit > 0)
		next_turf = get_step(next_turf, check_dir)
		if(isnull(next_turf))
			return null
		limit -= 1

	return next_turf.loc

/obj/effect/anomaly/weather/anomalyNeutralize()
	clear_weather()
	return ..()

/obj/effect/anomaly/weather/detonate()
	var/atom/smoke_location = loc
	if(consume(src))
		new /obj/effect/effect/smoke/bad/burntfood(smoke_location) // OOoooOooh spooky cloud... Doesn't do ANYTHING

/obj/effect/anomaly/weather/anomalyEffect(seconds_per_tick)
	..()
	if(!is_raining)
		return

	for(var/turf/turf in affected_turfs)
		if(isopenturf(turf))
			turf = GetBelow(turf)
		selected_weather.affect_turf(turf)

	if(stats)
		return

	for(var/mob/mob as anything in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(get_area(mob) in affected_areas)
			selected_weather.hear_sounds(mob, TRUE)
		else
			selected_weather.hear_sounds(mob, FALSE)

/obj/effect/anomaly/weather/proc/pick_weather(new_weather_path)
	if(!new_weather_path)
		new_weather_path = pick(subtypesof(/datum/anomalous_weather))

	rel_set(src, nameof(selected_weather), new new_weather_path)

/obj/effect/anomaly/weather/proc/start_weather()
	if(QDELETED(src))
		return

	is_raining = TRUE

	if(selected_weather.loop_sounds)
		selected_weather.loop_sounds.start()

	for(var/turf/area_turf in affected_turfs)
		selected_weather.apply_to_turf(area_turf)

/obj/effect/anomaly/weather/proc/clear_weather()
	if(!is_raining)
		return

	if(selected_weather.loop_sounds)
		selected_weather.loop_sounds.stop()

	for(var/turf/turf in affected_turfs)
		selected_weather.remove_from_turf(turf)

	for(var/area in affected_areas)
		for(var/mob/mob in area)
			selected_weather.hear_sounds(mob, FALSE)

// clears the weather it caused.
/obj/effect/anomaly/weather/on_destroy(force)
	clear_weather()
	..()

/obj/effect/anomaly/weather/proc/update_reagent(reagent)
	selected_weather.update_reagent(reagent)

/obj/effect/anomaly/weather/anomalyPulse()
	if(!..())
		return
	switch(stats.severity)
		if(0 to 15)
			fx_sparks(src, 3)
			LAZYCLEARLIST(affected_areas)
			rel_clear(src, nameof(affected_turfs))
		if(16 to 33)
			clear_weather()
			rel_clear(src, nameof(affected_turfs))
			if(!istype(selected_weather, /datum/anomalous_weather/rain))
				rel_set(src, nameof(selected_weather), new /datum/anomalous_weather/rain) // disposes of the old weather
			update_reagent(REAGENT_ID_WATER)
			add_turfs(circleviewturfs(src, 3))
			start_weather()
		if(34 to 65)
			clear_weather()
			rel_clear(src, nameof(affected_turfs))
			if(!istype(selected_weather, /datum/anomalous_weather/rain))
				rel_set(src, nameof(selected_weather), new /datum/anomalous_weather/rain)
			update_reagent(pick(REAGENT_ID_WATER, REAGENT_ID_ICE, REAGENT_ID_ORANGEJUICE))
			add_turfs(circlerangeturfs(src, 4))
			start_weather()
		else
			clear_weather()
			rel_clear(src, nameof(affected_turfs))
			if(!istype(selected_weather, /datum/anomalous_weather/rain/storm))
				rel_set(src, nameof(selected_weather), new /datum/anomalous_weather/rain/storm)

			var/reagent_id = pick(SSchemistry.ready().chemical_reagents)
			if(reagent_id in GLOB.obtainable_chemical_blacklist)
				update_reagent(REAGENT_ID_WATER) // You get WATER.
			else
				update_reagent(reagent_id)

			add_turfs(circlerangeturfs(src, 5))
			start_weather()

/obj/effect/anomaly/weather/rain
	selected_weather = /datum/anomalous_weather/rain

/*
/obj/effect/anomaly/weather/acidrain
	selected_weather = /datum/anomalous_weather/rain/acid
*/
/obj/effect/anomaly/weather/storm
	selected_weather = /datum/anomalous_weather/rain/storm

/obj/effect/anomaly/weather/bloodrain
	selected_weather = /datum/anomalous_weather/rain/blood

/obj/effect/anomaly/weather/ashstorm
	selected_weather = /datum/anomalous_weather/ash_storm

/obj/effect/anomaly/weather/hail
	selected_weather = /datum/anomalous_weather/hail

/// The weather (owns_one(starts =)): the type set in selected_weather, else any.
/obj/effect/anomaly/weather/proc/make_weather(current)
	var/weather_path = ispath(current) ? current : pick(subtypesof(/datum/anomalous_weather))
	return new weather_path
