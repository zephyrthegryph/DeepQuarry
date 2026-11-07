// Active play on the mapped station: the server cost of what players do, phase by phase, each in its own window (so a
// --profile run dumps one proc profile per phase). Ops are run synchronously where they do not sleep and timed inline
// (ms per op); the window adds what the op left behind for the tick (draws, lighting, atmos, timers).
//   tools/build/build.sh bench --scenario=active_play [--arg=walkers=20] [--arg=steps=40] [--profile]

/datum/benchmark/active_play
	id = "active_play"
	description = "Active play on the station: walking, item use, window data, melee hits, doors, a hull breach"

/datum/benchmark/active_play/Run()
	wait_for_assets()
	wait_fires(SSair, 5)
	var/list/turf/simulated/floor/floors = active_play_station_floors()
	count_metric("ap_station_floors", length(floors), "turfs", "none")
	if(length(floors) < 50)
		fail("too few open station floors ([length(floors)])")
	var/list/mob/living/carbon/human/crew = list()
	for(var/i in 1 to param("walkers", 20))
		var/mob/living/carbon/human/H = new(pick(floors))
		H.mind_initialize()
		crew += H
		CHECK_TICK
	wait_seconds(5)
	// Which global indexes name the turf and area hops: each one sends every nested content of a mover down own_field_changed()'s full path.
	var/list/hop_flags = list()
	for(var/hop in list(HOP_TURF, HOP_AREA))
		hop_flags[hop] = list(
			"stat_input_keys" = !!GLOB.stat_input_keys?[hop],
			"stat_hop_index" = !!GLOB.stat_hop_index?[hop],
			"stat_sys_vars" = !!GLOB.stat_sys_vars?[hop],
			"derived_read_vars" = !!GLOB.derived_read_vars?[hop],
			"change_hop_keys" = !!GLOB.change_hop_keys?[hop],
			"draw_hop" = !!draw_hop_reads_var(hop),
		)
	detail("ap_hop_flags", hop_flags)
	var/list/nested = list()
	for(var/atom/movable/AM as anything in hop_nested_contents(crew[1]))
		nested["[AM.type]"]++
	detail("ap_walker_nested", nested)
	count_metric("ap_walker_nested_count", length(hop_nested_contents(crew[1])), "atoms", "none")

	// Walking: each crew member takes a step every tick in a direction that stays open.
	var/steps = param("steps", 40)
	var/moved = 0
	var/move_ms = 0
	begin_window()
	for(var/n in 1 to steps)
		for(var/mob/living/carbon/human/H as anything in crew)
			var/turf/from = H.loc
			var/dir = H.dir
			var/turf/next = get_step(H, dir)
			if(!active_play_walkable(next))
				dir = pick(GLOB.cardinal)
				next = get_step(H, dir)
			if(!active_play_walkable(next))
				continue
			var/stamp = TICK_USAGE_REAL
			H.Move(next, dir)
			move_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - stamp)
			if(H.loc != from)
				moved++
		stoplag()
	end_window("ap_walk")
	count_metric("ap_walk_steps", moved, "steps", "none")
	metric("ap_walk_us_per_step", moved ? move_ms * 1000 / moved : 0, "us")

	// Item use: pick up a flashlight, toggle it twice, drop it. Each step is timed on its own (pickup, the two toggles, the drop), and the
	// toggles' outcomes are counted (a toggle the light refuses or declines costs the same resolution but runs no effect).
	var/item_ops = 0
	var/item_ms = 0
	var/pickup_ms = 0
	var/toggle_ms = 0
	var/drop_ms = 0
	var/toggled = 0
	var/list/obj/item/flashlight/lights = list()
	for(var/mob/living/carbon/human/H as anything in crew)
		lights += new /obj/item/flashlight(H.loc)
	var/list/op_counts = active_play_op_counts()
	begin_window()
	for(var/n in 1 to param("item_rounds", 10))
		for(var/i in 1 to length(crew))
			var/mob/living/carbon/human/H = crew[i]
			var/obj/item/flashlight/F = lights[i]
			if(F.loc != H.loc)
				F.forceMove(H.loc)
			var/stamp = TICK_USAGE_REAL
			H.put_in_hands(F)
			var/picked = TICK_USAGE_REAL
			var/was_on = F.on
			F.attack_self(H)
			if(F.on != was_on)
				toggled++
			was_on = F.on
			F.attack_self(H)
			if(F.on != was_on)
				toggled++
			var/switched = TICK_USAGE_REAL
			H.drop_from_inventory(F, H.loc)
			var/dropped = TICK_USAGE_REAL
			item_ms += TICK_DELTA_TO_MS(dropped - stamp)
			pickup_ms += TICK_DELTA_TO_MS(picked - stamp)
			toggle_ms += TICK_DELTA_TO_MS(switched - picked)
			drop_ms += TICK_DELTA_TO_MS(dropped - switched)
			item_ops++
		stoplag()
	end_window("ap_items")
	metric("ap_item_us_per_use", item_ops ? item_ms * 1000 / item_ops : 0, "us")
	metric("ap_item_pickup_us", item_ops ? pickup_ms * 1000 / item_ops : 0, "us")
	metric("ap_item_toggle_us", item_ops ? toggle_ms * 1000 / (2 * item_ops) : 0, "us")
	metric("ap_item_drop_us", item_ops ? drop_ms * 1000 / item_ops : 0, "us")
	count_metric("ap_item_toggles_switched", toggled, "toggles", "none")
	active_play_op_count_metrics("ap_items", op_counts, item_ops)
	for(var/obj/item/flashlight/F as anything in lights)
		qdel(F)

	// Window data: what one tgui update of a station machine computes, for a viewer standing next to it.
	var/list/obj/machinery/hosts = list()
	for(var/obj/machinery/M in world)
		var/datum/type_table/table = table_of(M)
		if(isStationLevel(M.z) && length(table.items))
			hosts += M
		CHECK_TICK
	shuffle_inplace(hosts)
	if(length(hosts) > 200)
		hosts.Cut(201)
	count_metric("ap_ui_hosts", length(hosts), "machines", "none")
	var/ui_ms = 0
	var/ui_ops = 0
	var/list/ui_by_type = list()
	var/mob/living/carbon/human/viewer = crew[1]
	begin_window()
	for(var/n in 1 to param("ui_rounds", 5))
		for(var/obj/machinery/M as anything in hosts)
			if(QDELETED(M))
				continue
			viewer.forceMove(get_turf(M))
			var/stamp = TICK_USAGE_REAL
			present_tgui_data(M, viewer, list())
			var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - stamp)
			ui_ms += ms
			ui_by_type["[M.type]"] += ms
			ui_ops++
			CHECK_TICK
		stoplag()
	end_window("ap_ui")
	metric("ap_ui_us_per_update", ui_ops ? ui_ms * 1000 / ui_ops : 0, "us")
	ui_by_type = sortTim(ui_by_type, GLOBAL_PROC_REF(cmp_numeric_desc), associative = TRUE)
	if(length(ui_by_type) > 15)
		ui_by_type.Cut(16)
	detail("ap_ui_ms_by_type", ui_by_type)

	// Melee: pairs of crew trade toolbox hits.
	var/list/obj/item/storage/toolbox/boxes = list()
	for(var/i in 1 to length(crew) step 2)
		var/mob/living/carbon/human/A = crew[i]
		var/mob/living/carbon/human/B = crew[min(i + 1, length(crew))]
		B.forceMove(get_turf(A))
		var/obj/item/storage/toolbox/mechanical/T = new(A.loc)
		A.put_in_hands(T)
		A.set_combat_mode(TRUE)
		boxes += T
	var/hits = 0
	var/landed = 0
	var/hit_ms = 0
	var/list/outcomes = list()
	op_counts = active_play_op_counts()
	begin_window()
	for(var/n in 1 to param("hit_rounds", 6))
		for(var/i in 1 to length(crew) step 2)
			var/mob/living/carbon/human/A = crew[i]
			var/mob/living/carbon/human/B = crew[min(i + 1, length(crew))]
			var/obj/item/T = A.get_active_hand()
			if(!T || A == B)
				continue
			STATE_SET(A, cooldowns, next_click, 0)
			var/stamp = TICK_USAGE_REAL
			var/datum/op_result/result = op_resolve_click(A, B, T, GESTURE_CLICK, ORIGIN_CLICK)
			hit_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - stamp)
			hits++
			if(result)
				landed++
				outcomes["[result.outcome]: [reason_text(result.reason) || "-"]"]++
			else
				outcomes["none"]++
		stoplag()
	end_window("ap_melee")
	count_metric("ap_melee_resolved", landed, "hits", "none")
	metric("ap_melee_us_per_hit", hits ? hit_ms * 1000 / hits : 0, "us")
	detail("ap_melee_outcomes", outcomes)
	active_play_op_count_metrics("ap_melee", op_counts, hits)

	// Menu read: the right-click menu of a crewmate (what the interaction menu's window data computes), with the menu cache cold (a state
	// change of the target since the last read) and warm (read again at once).
	var/menu_reads = 0
	var/menu_cold_ms = 0
	var/menu_warm_ms = 0
	var/menu_rows = 0
	var/builds_before = GLOB.op_menu_builds
	op_counts = active_play_op_counts()
	begin_window()
	for(var/n in 1 to param("menu_rounds", 5))
		for(var/i in 1 to length(crew) step 2)
			var/mob/living/carbon/human/A = crew[i]
			var/mob/living/carbon/human/B = crew[min(i + 1, length(crew))]
			if(A == B)
				continue
			op_changed(B)
			var/stamp = TICK_USAGE_REAL
			var/list/data = interaction_menu_data(A, B)
			var/cold_done = TICK_USAGE_REAL
			interaction_menu_data(A, B)
			var/warm_done = TICK_USAGE_REAL
			menu_cold_ms += TICK_DELTA_TO_MS(cold_done - stamp)
			menu_warm_ms += TICK_DELTA_TO_MS(warm_done - cold_done)
			menu_rows += length(data["available"]) + length(data["blocked"])
			menu_reads++
		stoplag()
	end_window("ap_menu")
	metric("ap_menu_cold_us", menu_reads ? menu_cold_ms * 1000 / menu_reads : 0, "us")
	metric("ap_menu_warm_us", menu_reads ? menu_warm_ms * 1000 / menu_reads : 0, "us")
	count_metric("ap_menu_rows", menu_reads ? menu_rows / menu_reads : 0, "rows", "none")
	count_metric("ap_menu_builds", GLOB.op_menu_builds - builds_before, "builds")
	active_play_op_count_metrics("ap_menu", op_counts, menu_reads)
	for(var/obj/item/T as anything in boxes)
		qdel(T)

	// Doors: station airlocks open and close (async: the animation sleeps).
	var/list/obj/machinery/door/airlock/doors = list()
	for(var/obj/machinery/door/airlock/D in world)
		if(isStationLevel(D.z) && D.density && !D.bolted_at_start)
			doors += D
		CHECK_TICK
	shuffle_inplace(doors)
	if(length(doors) > param("doors", 60))
		doors.Cut(param("doors", 60) + 1)
	count_metric("ap_doors", length(doors), "doors", "none")
	begin_window()
	for(var/n in 1 to param("door_cycles", 3))
		for(var/obj/machinery/door/airlock/D as anything in doors)
			INVOKE_ASYNC(D, TYPE_PROC_REF(/obj/machinery/door/airlock, open), TRUE)
		wait_seconds(2)
		for(var/obj/machinery/door/airlock/D as anything in doors)
			INVOKE_ASYNC(D, TYPE_PROC_REF(/obj/machinery/door/airlock, close), TRUE)
		wait_seconds(2)
	end_window("ap_doors")

	// Breach: open a few station floors that touch space to vacuum and let the air run.
	var/list/turf/breaches = active_play_breach_sites(floors, param("breaches", 3))
	count_metric("ap_breaches", length(breaches), "turfs", "none")
	begin_window()
	for(var/turf/T as anything in breaches)
		T.ChangeTurf(/turf/space)
	wait_seconds(param("breach_seconds", 20))
	end_window("ap_breach")

	for(var/mob/living/carbon/human/H as anything in crew)
		qdel(H)
		CHECK_TICK

/proc/active_play_station_floors()
	. = list()
	for(var/turf/simulated/floor/F in world)
		if(isStationLevel(F.z) && active_play_walkable(F))
			. += F
		CHECK_TICK

/proc/active_play_walkable(turf/T)
	if(!istype(T, /turf/simulated/floor) || T.density)
		return FALSE
	for(var/atom/movable/A as anything in T)
		if(A.density)
			return FALSE
	return TRUE

/// Station floors with space next to them, `count` of them, spread over the list.
/proc/active_play_breach_sites(list/turf/floors, count)
	. = list()
	for(var/turf/simulated/floor/F as anything in shuffle(floors.Copy()))
		for(var/dir in GLOB.cardinal)
			if(istype(get_step(F, dir), /turf/space))
				. += F
				break
		if(length(.) >= count)
			return

/// The resolver's work counters now (resolve.dm): candidates made, reach gates, when() tests, requirement checks, full and compiled resolutions.
/proc/active_play_op_counts()
	return list(
		"cands" = GLOB.op_count_cands,
		"reach" = GLOB.op_count_reach,
		"whens" = GLOB.op_count_whens,
		"requires" = GLOB.op_count_requires,
		"resolves" = GLOB.op_count_resolves,
	)

/// The resolver's work since `before`, per input (`per` inputs), as count metrics under `prefix`.
/datum/benchmark/proc/active_play_op_count_metrics(prefix, list/before, per)
	var/list/now = active_play_op_counts()
	for(var/name in now)
		count_metric("[prefix]_op_[name]_per", per ? (now[name] - before[name]) / per : 0, name)
