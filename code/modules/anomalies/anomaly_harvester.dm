CAPABILITIES(/obj/machinery/anomaly_harvester)
	started_work(step = PROC_REF(work_step), starts = PROC_REF(step_start_condition))
	op("release_all", ui_act(), then(PROC_REF(ui_act_release_all)))
	interface("AnomalyHarvester", state = nameof(GLOB.tgui_default_state))
	without("ui_open")
	op("release_sample", ui_act("release_sample", arg("ref", schema_ref(/obj/item/research_sample))), then(PROC_REF(ui_act_release_sample)))
	extend("machine_anchor", then(PROC_REF(rewrenched)))
	extend("machine_unanchor", then(PROC_REF(rewrenched)))
	default_parts()
	op("part_replacement", item(/obj/item/storage/part_replacer), priority(OP_PRIORITY_DEFAULT - 1), label("Replace parts"), then(PROC_REF(interaction_part_replacement_impl)))
	op("attach_scanner", item(/obj/item/anomaly_scanner), priority(OP_PRIORITY_DEFAULT - 2), label("Attach anomaly"), then(PROC_REF(interaction_attach_scanner)))

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

	/// Relation view: the anomaly this harvester is attached to.
	var/obj/effect/anomaly/harvested

/obj/machinery/anomaly_harvester/RefreshParts()
	var/efficient = get_part_rating(/obj/item/stock_parts/manipulator) - 2 * get_part_count(/obj/item/stock_parts/manipulator)
	var/rating = get_part_rating(/obj/item/stock_parts/micro_laser) - 2 * get_part_count(/obj/item/stock_parts/micro_laser)

	efficiency = max(1, (efficient/10+1))
	points_to_create = min(100, (100 - (rating * 5)))

/obj/machinery/anomaly_harvester/proc/work_step(datum/act/timer/A)
	if(!operable() || !anchored)
		set_use_power(USE_POWER_OFF)
	else
		set_use_power(USE_POWER_IDLE)
		harvest_anomaly()
		if(points && points >= points_to_create)
			points -= points_to_create
			generate_sample()

/obj/machinery/anomaly_harvester/proc/add_points(add_points)
	add_points *= efficiency
	points += add_points
	return

/obj/machinery/anomaly_harvester/proc/harvest_anomaly()
	if(!harvested)
		return

	var/obj/effect/anomaly/anom = harvested
	if(!istype(anom))
		return

	var/datum/anomaly_stats/stats = anom.stats

	if(stats.stability == ANOMALY_DECAYING)
		play_sfx(src, SFX_MACHINES_2BEEPHIGH)
	else if (stats.stability == ANOMALY_GROWING)
		play_sfx(src, SFX_MACHINES_BUZZBEEP, 1.5)

/obj/machinery/anomaly_harvester/proc/interaction_part_replacement_impl(datum/act/op/A)
	add_fingerprint(A.actor)
	return default_part_replacement(A.actor, A.held) ? OP_OK : OP_DECLINE

/obj/machinery/anomaly_harvester/proc/interaction_attach_scanner(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/anomaly_scanner/scanner = A.held
	add_fingerprint(user)
	if(!anchored)
		to_chat(user, span_danger("The [src] is not anchored!"))
		return OP_OK
	if(scanner.buffered_anomaly)
		task_timed(user, 2 SECONDS, src, src, PROC_REF(attach_scanned_anomaly), list(scanner))
	return OP_OK

/obj/machinery/anomaly_harvester/proc/attach_scanned_anomaly(obj/item/anomaly_scanner/scanner)
	if(scanner.buffered_anomaly)
		attach_anomaly(scanner.buffered_anomaly)

/obj/machinery/anomaly_harvester/proc/attach_anomaly(obj/effect/anomaly/anomaly)
	// The scanner's buffered_anomaly and the stats' attached_harvester are relation views.
	var/obj/effect/anomaly/anom = anomaly
	if(!istype(anom))
		return

	var/datum/anomaly_stats/stats = anom.stats
	if(stats.attached_harvester)
		var/obj/machinery/anomaly_harvester/harvester = stats.attached_harvester
		if(harvester)
			rel_clear(harvester, nameof(harvester.harvested))
		rel_clear(stats, nameof(stats.attached_harvester))
	rel_set(src, nameof(harvested), anom)
	rel_set(stats, nameof(stats.attached_harvester), src)
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

/// Running or not, and the stability of the anomaly it holds.
/obj/machinery/anomaly_harvester/draw(datum/look/look)
	..()
	look.overlay((!operable() || !anchored) ? "harvester_off" : "harvester_on")

	var/obj/effect/anomaly/anom = harvested
	if(istype(anom))
		switch(anom.look_stability(look))
			if(ANOMALY_STABLE)
				look.overlay("harvester_stable")
			if(ANOMALY_DECAYING)
				look.overlay("harvester_decay")
			else
				look.overlay("harvester_grow")

/// /obj/machinery/anomaly_harvester's window data.
/obj/machinery/anomaly_harvester/ui_data(datum/act/eval/A)
	var/list/sample_data = list()
	FOR_REAL_CONTENTS(var/obj/item/research_sample/sample, src)
		UNTYPED_LIST_ADD(sample_data, list(
			"name" = sample.name,
			"icon" = sample.icon,
			"icon_state" = sample.icon_state,
			"ref" = REF(sample)
		))

	var/obj/effect/anomaly/anom = harvested
	var/list/data = list(
		"name" = anom,
		"points" = points,
		"pointsToGenerate" = points_to_create,
		"samples" = sample_data
	)

	return data

/obj/machinery/anomaly_harvester/proc/ui_act_release_sample(datum/act/op/A, ref)
	if(!isnull(ref) && !(ref in contents_of(src)))
		return FALSE
	var/obj/item/research_sample/sample = ref
	if(!istype(sample) || (sample.loc != src))
		return FALSE
	sample.forceMove(get_turf(src))
	return TRUE

/obj/machinery/anomaly_harvester/proc/ui_act_release_all(datum/act/op/A)
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/item/research_sample/sample in contents_of(src)) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		sample.forceMove(get_turf(src))
	return OP_OK

/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/anomaly_harvester/step_start_condition()
	return anchored

/// After the wrench (secure or unsecure): the harvested anomaly is let go.
/obj/machinery/anomaly_harvester/proc/rewrenched(datum/act/op/A)
	rel_clear(src, nameof(harvested))
