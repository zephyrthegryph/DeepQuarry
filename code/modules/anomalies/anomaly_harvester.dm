/obj/machinery/anomaly_harvester
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	maintenance_wrench_time = 2 SECONDS
	name = "anomaly harvester"
	desc = "A strange device that condenses anomalous energy into tangible material."
	icon = 'icons/obj/machines/anomaly_harvester.dmi'
	icon_state = "harvester"
	density = TRUE
	circuit = /obj/item/circuitboard/anomaly_harvester
	active_power_usage = 40000
	idle_power_usage = 1000

	var/points = 0
	var/points_to_create = 100
	var/efficiency = 1

	var/harvested

/obj/machinery/anomaly_harvester/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/anomaly_harvester/RefreshParts()
	var/efficient = get_part_rating(/obj/item/stock_parts/manipulator) - 2 * get_part_count(/obj/item/stock_parts/manipulator)
	var/rating = get_part_rating(/obj/item/stock_parts/micro_laser) - 2 * get_part_count(/obj/item/stock_parts/micro_laser)

	efficiency = max(1, (efficient/10+1))
	points_to_create = min(100, (100 - (rating * 5)))

/obj/machinery/anomaly_harvester/machine_step()
	..()
	if(!operable() || !anchored)
		set_use_power(USE_POWER_OFF)
	else
		set_use_power(USE_POWER_IDLE)
		harvest_anomaly()
		if(points && points >= points_to_create)
			points -= points_to_create
			generate_sample()
	update_icon()

/obj/machinery/anomaly_harvester/proc/add_points(add_points)
	add_points *= efficiency
	points += add_points
	return

/obj/machinery/anomaly_harvester/proc/harvest_anomaly()
	if(!harvested)
		return

	var/obj/effect/anomaly/anom = om_resolve(harvested)
	if(!istype(anom))
		return

	var/datum/anomaly_stats/stats = anom.stats

	if(stats.stability == ANOMALY_DECAYING)
		play_sfx(src, SFX_MACHINES_2BEEPHIGH)
	else if (stats.stability == ANOMALY_GROWING)
		play_sfx(src, SFX_MACHINES_BUZZBEEP, 1.5)

/obj/machinery/anomaly_harvester/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/anomaly_harvester_part_replacement,
		/datum/interaction/machine_item/anomaly_harvester_attach_scanner,
		/datum/interaction/machine_hand/open_ui,
	)
	..()

/// Old attackby added a fingerprint before the shared part-replacement check.
/datum/interaction/machine_item/anomaly_harvester_part_replacement
	id = "anomaly_harvester_part_replacement"
	name = "Replace parts"
	category = INTERACTION_CAT_MAINTAIN
	held_type = /obj/item/storage/part_replacer
	effect = /obj/machinery/anomaly_harvester/proc/interaction_part_replacement_impl

/obj/machinery/anomaly_harvester/proc/interaction_part_replacement_impl(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	return default_part_replacement(user, held) ? TRUE : FALSE

/datum/interaction/machine_item/anomaly_harvester_attach_scanner
	id = "anomaly_harvester_attach_scanner"
	name = "Attach anomaly"
	held_type = /obj/item/anomaly_scanner
	effect = /obj/machinery/anomaly_harvester/proc/interaction_attach_scanner

/obj/machinery/anomaly_harvester/proc/interaction_attach_scanner(mob/user, obj/item/anomaly_scanner/scanner, datum/interaction/interaction)
	add_fingerprint(user)
	if(!anchored)
		to_chat(user, span_danger("The [src] is not anchored!"))
		return TRUE
	if(scanner.buffered_anomaly)
		om_task_timed(user, 2 SECONDS, src, src, PROC_REF(attach_scanned_anomaly), list(scanner))
	return TRUE

/obj/machinery/anomaly_harvester/proc/attach_scanned_anomaly(obj/item/anomaly_scanner/scanner)
	if(scanner.buffered_anomaly)
		attach_anomaly(scanner.buffered_anomaly)

/obj/machinery/anomaly_harvester/wrench_act(mob/user, obj/item/tool)
	. = ..()
	if(. & ITEM_INTERACT_SUCCESS)
		harvested = null

/obj/machinery/anomaly_harvester/proc/attach_anomaly(anomaly)
	var/obj/effect/anomaly/anom = om_resolve(anomaly)
	if(!istype(anom))
		return

	var/datum/anomaly_stats/stats = anom.stats
	if(stats.attached_harvester)
		var/obj/machinery/anomaly_harvester/harvester = om_resolve(stats.attached_harvester)
		if(harvester)
			harvester.harvested = null
			harvester.update_icon()
		stats.attached_harvester = null
	harvested = anomaly
	stats.attached_harvester = om_handle(src)
	play_sfx(src, SFX_MACHINES_BOOBEEBEEP, 1.5, vary = TRUE)
	return TRUE

/obj/machinery/anomaly_harvester/proc/generate_sample()
	set_use_power(USE_POWER_ACTIVE)
	play_sfx(src, SFX_MACHINES_PING, vary = TRUE)
	switch(rand(1, 100))
		if(1 to 50)
			new /obj/item/research_sample/common(src)
		if(51 to 80)
			new /obj/item/research_sample/uncommon(src)
		if(81 to 95)
			new /obj/item/research_sample/rare(src)
		if(96 to 100)
			new /obj/item/research_sample/bluespace(src)
		else
			new /obj/item/research_sample/common(src)

DECLARE_APPEARANCE_PROC(/obj/machinery/anomaly_harvester, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/anomaly_harvester/appearance_overlays()
	. = list()
	if(!operable() || !anchored)
		. += "harvester_off"
	else
		. += "harvester_on"

	if(harvested)
		var/obj/effect/anomaly/anom = om_resolve(harvested)
		if(!istype(anom))
			return .

		var/datum/anomaly_stats/stats = anom.stats

		switch(stats.stability)
			if(ANOMALY_STABLE)
				. += "harvester_stable"
			if(ANOMALY_DECAYING)
				. += "harvester_decay"
			else
				. += "harvester_grow"

/obj/machinery/anomaly_harvester/tgui_state(mob/user)
	return GLOB.tgui_default_state

/obj/machinery/anomaly_harvester/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AnomalyHarvester", name)
		ui.open()

/obj/machinery/anomaly_harvester/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/sample_data = list()
	FOR_REAL_CONTENTS(var/obj/item/research_sample/sample, src)
		UNTYPED_LIST_ADD(sample_data, list(
			"name" = sample.name,
			"icon" = sample.icon,
			"icon_state" = sample.icon_state,
			"ref" = REF(sample)
		))

	var/obj/effect/anomaly/anom = om_resolve(harvested)
	var/list/data = list(
		"name" = anom,
		"points" = points,
		"pointsToGenerate" = points_to_create,
		"samples" = sample_data
	)

	return data

/obj/machinery/anomaly_harvester/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return

	switch(action)
		if("release_sample")
			var/obj/item/research_sample/sample = locate_within(src, params["ref"])
			if(!istype(sample) || (sample.loc != src))
				return FALSE
			sample.forceMove(get_turf(src))
			return TRUE
		if("release_all")
			latent_materialize_all() // a walk needs real things (C5)
			for(var/obj/item/research_sample/sample in contents_of(src)) // ALLOW(latent): materialized above
				sample.forceMove(get_turf(src))
			return TRUE

/// Its declared start condition (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/anomaly_harvester/step_start_condition()
	return anchored
