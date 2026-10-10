// Time dilation and sendmaps tracking (was SStime_track): sampled every 10 s into the perf log.
SYSTEM_DEF(time_track)
	name = "Time Tracking"
	needs = list(/datum/system/dbcore)
	periodic_runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT

	var/time_dilation_current = 0

	var/time_dilation_avg_fast = 0
	var/time_dilation_avg = 0
	var/time_dilation_avg_slow = 0

	var/first_run = TRUE
	/// Stops sampling after a malformed sendmaps profile (was can_fire = FALSE).
	var/disabled = FALSE

	var/last_tick_realtime = 0
	var/last_tick_byond_time = 0
	var/last_tick_tickcount = 0
	var/list/sendmaps_names_map = list(
		"SendMaps" = "send_maps",
		"SendMaps: Initial housekeeping" = "initial_house",
		"SendMaps: Cleanup" = "cleanup",
		"SendMaps: Client loop" = "client_loop",
		"SendMaps: Per client" = "per_client",
		"SendMaps: Per client: Deleted images" = "deleted_images",
		"SendMaps: Per client: HUD update" = "hud_update",
		"SendMaps: Per client: Statpanel update" = "statpanel_update",
		"SendMaps: Per client: Map data" = "map_data",
		"SendMaps: Per client: Map data: Check eye position" = "check_eye_pos",
		"SendMaps: Per client: Map data: Update chunks" = "update_chunks",
		"SendMaps: Per client: Map data: Send turfmap updates" = "turfmap_updates",
		"SendMaps: Per client: Map data: Send changed turfs" = "changed_turfs",
		"SendMaps: Per client: Map data: Send turf chunk info" = "turf_chunk_info",
		"SendMaps: Per client: Map data: Send obj changes" = "obj_changes",
		"SendMaps: Per client: Map data: Send mob changes" = "mob_changes",
		"SendMaps: Per client: Map data: Send notable turf visual contents" = "send_turf_vis_conts",
		"SendMaps: Per client: Map data: Send pending animations" = "pending_animations",
		"SendMaps: Per client: Map data: Look for movable changes" = "look_for_movable_changes",
		"SendMaps: Per client: Map data: Look for movable changes: Check notable turf visual contents" = "check_turf_vis_conts",
		"SendMaps: Per client: Map data: Look for movable changes: Check HUD/image visual contents" = "check_hud/image_vis_contents",
		"SendMaps: Per client: Map data: Look for movable changes: Loop through turfs in range" = "turfs_in_range",
		"SendMaps: Per client: Map data: Look for movable changes: Movables examined" = "movables_examined",
	)

/// Samples every 10 s.
/datum/system/time_track/reactions()
	. = ..()
	. += every(10 SECONDS, PROC_REF(sample_time), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/datum/system/time_track/initialize()
	initialized = TRUE
	//GLOB.perf_log = "[GLOB.log_directory]/perf-[GLOB.round_id ? GLOB.round_id : "NULL"]-[SSmapping.current_map.map_name].csv"
	GLOB.perf_log = "[GLOB.log_directory]/perf-[GLOB.round_id ? GLOB.round_id : "NULL"]-[using_map.name].csv"
	world.Profile(PROFILE_RESTART, type = "sendmaps")
	//Need to do the sendmaps stuff in its own file, since it works different then everything else
	var/list/sendmaps_headers = list()
	for(var/proper_name in sendmaps_names_map)
		sendmaps_headers += sendmaps_names_map[proper_name]
		sendmaps_headers += "[sendmaps_names_map[proper_name]]_count"
	log_perf(
		list(
			"time",
			"players",
			"tidi",
			"tidi_fastavg",
			"tidi_avg",
			"tidi_slowavg",
			"maptick",
			"num_timers",
			"air_turf_cost",
			"air_gas_events_cost",
			"air_highpressure_cost",
			"air_superconductivity_cost",
			"air_pipenets_cost",
			"air_rebuilds_cost",
			"air_gas_frames",
			"air_gas_events",
			"air_gas_reactions",
			"air_gas_visuals",
			"air_gas_pressure_pushes",
			"air_hotspot_count",
			"air_network_count",
			"air_delta_count",
			"air_subsystem_cost",
			"air_subsystem_ticks",
			"air_subsystem_overrun",
			"machine_cost",
			"powernet_cost",
			"power_object_cost",
			"machine_active_count",
			"powernet_count",
			"machines_subsystem_cost",
			"machines_subsystem_ticks",
			"machines_subsystem_overrun",
			"machines_dirty_gases",
			"machines_gas_wakes",
			"behaviours_subsystem_cost",
			"behaviours_subsystem_ticks",
			"behaviours_subsystem_overrun",
			"mob_count",
			"ai_subsystem_cost",
			"timers_subsystem_cost",
			"all_queries",
			"queries_active",
			"queries_standby"
		) + sendmaps_headers
	)

/datum/system/time_track/proc/sample_time(dt)
	if(disabled)
		return STEP_DONE

	var/current_realtime = REALTIMEOFDAY
	var/current_byondtime = world.time
	var/current_tickcount = world.time/world.tick_lag

	if (!first_run)
		var/tick_drift = max(0, (((current_realtime - last_tick_realtime) - (current_byondtime - last_tick_byond_time)) / world.tick_lag))

		time_dilation_current = tick_drift / (current_tickcount - last_tick_tickcount) * 100

		time_dilation_avg_fast = KERNEL_AVERAGE_FAST(time_dilation_avg_fast, time_dilation_current)
		time_dilation_avg = KERNEL_AVERAGE(time_dilation_avg, time_dilation_avg_fast)
		time_dilation_avg_slow = KERNEL_AVERAGE_SLOW(time_dilation_avg_slow, time_dilation_avg)
		//GLOB.glide_size_multiplier = (current_byondtime - last_tick_byond_time) / (current_realtime - last_tick_realtime)
	else
		first_run = FALSE
	last_tick_realtime = current_realtime
	last_tick_byond_time = current_byondtime
	last_tick_tickcount = current_tickcount

	var/sendmaps_json = world.Profile(PROFILE_REFRESH, type = "sendmaps", format="json")
	var/list/send_maps_data = null
	try
		send_maps_data = json_decode(sendmaps_json)
	catch
		text2file(sendmaps_json,"bad_sendmaps.json")
		disabled = TRUE
		log_world("Time tracking stopped: malformed sendmaps profile JSON (bad_sendmaps.json).")
		return STEP_DONE
	var/send_maps_sort = send_maps_data.Copy() //Doing it like this guarantees us a properly sorted list

	for(var/list/packet in send_maps_data)
		send_maps_sort[packet["name"]] = packet

	var/list/send_maps_values = list()
	for(var/entry_name in sendmaps_names_map)
		var/list/packet = send_maps_sort[entry_name]
		if(!packet) //If the entry does not have a value for us, just put in 0 for both
			send_maps_values += 0
			send_maps_values += 0
			continue
		send_maps_values += packet["value"]
		send_maps_values += packet["calls"]

	log_perf(
		list(
			world.time,
			length(GLOB.clients),
			time_dilation_current,
			time_dilation_avg_fast,
			time_dilation_avg,
			time_dilation_avg_slow,
			MAPTICK_LAST_INTERNAL_TICK_USAGE,
			0, // SStimer timers: gone (om_after timers live on their owners)
			SSair.cost_turfs,
			SSair.cost_gas_events,
			SSair.cost_highpressure,
			SSair.cost_superconductivity,
			SSair.cost_pipenets,
			SSair.cost_rebuilds,
			SSair.gas_frames,
			SSair.gas_events_last,
			SSair.gas_reactions_last,
			SSair.gas_visuals_last,
			SSair.gas_pressure_last,
			length(SSair.hotspots),
			length(SSair.networks),
			length(SSair.high_pressure_delta),
			SSair.fire_cost,
			SSair.ticks,
			SSair.tick_overrun,
			machines_cost_machinery(),
			machines_cost_powernets(),
			0, // power objects: gone (powersinks drain on their own periodic step)
			0, // parked machines: none (a machine's work is a stat-gated every())
			length(machines_power_grids()),
			SSmachines.fire_cost,
			SSmachines.times_fired,
			0, // tick overrun: the machine service runs inside SSbehaviours' budget
			machines_gas_dirty_last(),
			machines_gas_woken_last(),
			SSbehaviours.fire_cost,
			SSbehaviours.ticks,
			SSbehaviours.tick_overrun,
			REGISTRY_COUNT(REGISTRY_MOBS),
			round(GLOB.ai_brain_cost_ms, 0.01),
			0, // SStimer cost: gone
			0, // all_queries: the query pump is gone (I/O lane jobs are counted by SSdb)
			0, // queries_active
			0 // queries_standby
		) + send_maps_values
	)

	return STEP_DONE

/// Time dilation for the server metrics (code/modules/metrics/): how far game time falls behind real time.
/datum/metrics_source/time_dilation

/datum/metrics_source/time_dilation/collect(datum/system/server_metrics/M, dt)
	M.gauge("server/time_dilation/current", SStime_track.time_dilation_current, METRICS_CAT_SERVER, "time_dilation", "%")
	M.gauge("server/time_dilation/avg", SStime_track.time_dilation_avg, METRICS_CAT_SERVER, "time_dilation", "%")
