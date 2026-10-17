// Non-steady-state load on the full map (doc/rewrite/load_lag_1017.md): what a round costs while something big happens and
// after it. Every scenario boots Southern Cross, spawns a crowd in a hallway, then measures two windows:
//   <name>_event      the first `event_seconds` (10) after the trigger
//   <name>_after      the next `after_seconds` (50)
// Run: tools/build/build.sh bench --scenario=load_explosion [--profile] [--arg=size=large] -DCITESTING_FULL_MAP
// Scenarios: load_explosion (size small|medium|large|huge), load_fire, load_breach, load_outage, load_mobs.

/// The area of the live-server bomb test (a hallway on the second deck).
#define LOAD_LAG_AREA "Second Deck Aft Port Central Hallway"

/// The floor turfs of the first area named `name`.
/proc/load_lag_area_floors(name)
	. = list()
	for(var/area/A in world)
		if(!findtext(A.name, name))
			continue
		for(var/turf/simulated/floor/F in A)
			if(!F.density)
				. += F
		if(length(.))
			return

/datum/benchmark/proc/load_lag_crowd(list/turfs, count)
	. = list()
	for(var/i in 1 to count)
		var/mob/living/carbon/human/H = new(pick(turfs))
		H.set_low_priority(FALSE)
		. += H
		if(i <= 2)
			GLOB.refresh_traced[REF(H)] = list() // what marks a crowd human: reported with each window
		CHECK_TICK

/// The busiest churn keys of each kind since the last call, and the mark trace of the traced humans.
/datum/benchmark/proc/load_lag_churn(name)
	var/list/kinds = GLOB.churn_census.take()
	var/list/top = list()
	for(var/kind in kinds)
		var/list/counts = kinds[kind]
		counts = sortTim(counts.Copy(), GLOBAL_PROC_REF(cmp_numeric_desc), associative = TRUE)
		if(length(counts) > 12)
			counts.Cut(13)
		top[kind] = counts
	detail("[name]_churn", top)
	var/list/traces = list()
	for(var/ref_text in GLOB.refresh_traced)
		var/list/lines = GLOB.refresh_traced[ref_text]
		if(islist(lines))
			traces[ref_text] = lines.Copy()
			lines.Cut()
	detail("[name]_mark_trace", traces)

/// Runs `trigger` (a proc ref on this datum) and measures the event window and the aftermath window under `name`.
/datum/benchmark/proc/load_lag_measure(name, trigger)
	var/event_seconds = param("event_seconds", 10)
	var/after_seconds = param("after_seconds", 50)
	begin_window()
	log_world("LOAD_LAG [name]: trigger")
	GLOB.stall_log.Cut()
	GLOB.churn_census.take()
	call(src, trigger)()
	wait_seconds(event_seconds)
	end_window("[name]_event")
	load_lag_churn("[name]_event")
	detail("[name]_event_stalls", GLOB.stall_log.Copy())
	begin_window()
	GLOB.stall_log.Cut()
	wait_seconds(after_seconds)
	end_window("[name]_after")
	load_lag_churn("[name]_after")
	detail("[name]_after_stalls", GLOB.stall_log.Copy())
	log_world("LOAD_LAG [name]: done")

/// Settles the post-boot backlog so the event is measured against a quiet round.
/datum/benchmark/proc/load_lag_settle()
	wait_for_assets()
	// Production runs without the per-destroy leak postcondition that test builds switch on.
	GLOB.dq_lifecycle_leak_check = 0
	wait_seconds(param("settle_seconds", 60))

/datum/benchmark/load_explosion
	id = "load_explosion"
	description = "Explosions of bench_sizes (comma list of small, medium, large, huge) in a crowded hallway of the full map"
	var/turf/blast_center
	var/blast_size = "large"

/datum/benchmark/load_explosion/Run()
	load_lag_settle()
	var/list/floors = load_lag_area_floors(LOAD_LAG_AREA)
	if(!length(floors))
		fail("area [LOAD_LAG_AREA] not found")
	load_lag_crowd(floors, param("humans", 12))
	for(var/size in splittext(param("sizes", "large"), ","))
		blast_size = size
		blast_center = pick(floors)
		wait_seconds(5)
		load_lag_measure("explosion_[size]", PROC_REF(trigger))
		wait_seconds(param("gap_seconds", 20))

/datum/benchmark/load_explosion/proc/trigger()
	switch(blast_size)
		if("small")
			explosion(blast_center, 1, 2, 4, 6, FALSE, 0)
		if("medium")
			explosion(blast_center, 3, 6, 9, 12, FALSE, 0)
		if("huge")
			explosion(blast_center, 16, 32, 48, 64, FALSE, 0)
		else
			explosion(blast_center, 8, 16, 24, 32, FALSE, 0)

/datum/benchmark/load_fire
	id = "load_fire"
	description = "A plasma flash fire spreading through a crowded hallway and its neighbours"
	var/list/fire_turfs

/datum/benchmark/load_fire/Run()
	load_lag_settle()
	var/list/floors = load_lag_area_floors(LOAD_LAG_AREA)
	if(!length(floors))
		fail("area [LOAD_LAG_AREA] not found")
	fire_turfs = floors
	load_lag_crowd(floors, param("humans", 12))
	wait_seconds(5)
	load_lag_measure("fire", PROC_REF(trigger))

/datum/benchmark/load_fire/proc/trigger()
	for(var/turf/simulated/floor/T as anything in fire_turfs)
		T.air.set_moles(/datum/gas/plasma, param("plasma", 40))
		T.air_update_turf(FALSE, FALSE)
	for(var/turf/simulated/floor/T as anything in fire_turfs)
		T.hotspot_expose(PLASMA_MINIMUM_BURN_TEMPERATURE + 500, CELL_VOLUME, TRUE)
		break

/datum/benchmark/load_breach
	id = "load_breach"
	description = "Hull breach: bench_holes exterior walls near a hallway replaced by space, decompressing several rooms"
	var/list/hull_holes

/datum/benchmark/load_breach/Run()
	load_lag_settle()
	var/list/floors = load_lag_area_floors(LOAD_LAG_AREA)
	if(!length(floors))
		fail("area [LOAD_LAG_AREA] not found")
	var/turf/anchor = floors[1]
	var/list/candidates = list()
	for(var/turf/simulated/wall/W in block(locate(max(anchor.x - 40, 1), max(anchor.y - 40, 1), anchor.z), locate(min(anchor.x + 40, world.maxx), min(anchor.y + 40, world.maxy), anchor.z)))
		for(var/dir in GLOB.cardinal)
			var/turf/N = get_step(W, dir)
			if(istype(N, /turf/space))
				candidates += W
				break
	if(!length(candidates))
		fail("no exterior wall within 40 tiles of [LOAD_LAG_AREA]")
	hull_holes = list()
	for(var/i in 1 to param("holes", 6))
		var/turf/best
		var/best_dist = INFINITY
		for(var/turf/W as anything in candidates)
			var/dist = get_dist(W, anchor)
			if(dist < best_dist && !(W in hull_holes))
				best = W
				best_dist = dist
		if(!best)
			break
		hull_holes += best
	load_lag_crowd(floors, param("humans", 12))
	wait_seconds(5)
	load_lag_measure("breach", PROC_REF(trigger))

/datum/benchmark/load_breach/proc/trigger()
	for(var/turf/W as anything in hull_holes)
		W.ChangeTurf(/turf/space)

/datum/benchmark/load_outage
	id = "load_outage"
	description = "Station power outage: every SMES output off, APC cells drained, then SMES back on"

/datum/benchmark/load_outage/Run()
	load_lag_settle()
	var/list/floors = load_lag_area_floors(LOAD_LAG_AREA)
	if(length(floors))
		load_lag_crowd(floors, param("humans", 12))
	wait_seconds(5)
	load_lag_measure("outage_off", PROC_REF(smes_off))
	load_lag_measure("outage_dead", PROC_REF(cells_drained))
	load_lag_measure("outage_restore", PROC_REF(smes_on))

/datum/benchmark/load_outage/proc/smes_off()
	for(var/obj/machinery/power/smes/S in REGISTRY_MEMBERS(REGISTRY_SMES))
		S.set_output_on(FALSE)

/datum/benchmark/load_outage/proc/cells_drained()
	for(var/obj/machinery/power/apc/A in REGISTRY_MEMBERS(REGISTRY_APCS))
		if(A.cell)
			A.cell.charge = 0

/datum/benchmark/load_outage/proc/smes_on()
	for(var/obj/machinery/power/smes/S in REGISTRY_MEMBERS(REGISTRY_SMES))
		S.set_output_on(TRUE)

/datum/benchmark/load_mobs
	id = "load_mobs"
	description = "bench_humans humans and bench_carp hostile carp loose on the station with AI awake, plus synthetic input"

/datum/benchmark/load_mobs/Run()
	load_lag_settle()
	var/list/floors = list()
	for(var/turf/simulated/floor/F in world)
		if(F.z <= 3 && !F.density)
			floors += F
		CHECK_TICK
	load_lag_crowd(floors, param("humans", 40))
	for(var/i in 1 to param("carp", 40))
		var/mob/living/simple_mob/animal/space/carp/C = new(pick(floors))
		C.set_low_priority(FALSE)
		CHECK_TICK
	wait_seconds(5)
	begin_window()
	wait_seconds_with_input(param("seconds", 60), param("clicks", 4), param("verbs", 4))
	end_window("mobs_window")
	load_lag_churn("mobs")
	detail("mobs_stalls", GLOB.stall_log.Copy())

/// Unit costs behind the load scenarios: one log timestamp, one log line, a human's first and repeated draw.
/datum/benchmark/load_probe
	id = "load_probe"
	description = "Per-call cost of a log timestamp, a log_world line, and a human's first and later draws"

/datum/benchmark/load_probe/Run()
	wait_for_assets()
	GLOB.dq_lifecycle_leak_check = 0
	var/calls = param("calls", 2000)
	var/start = REALTIMEOFDAY
	for(var/i in 1 to calls)
		rustg_formatted_timestamp("%Y-%m-%d %H:%M:%S%.3f")
	metric("probe_timestamp_us", (REALTIMEOFDAY - start) * 100000 / calls, "us")
	start = REALTIMEOFDAY
	for(var/i in 1 to calls)
		log_world("LOAD_PROBE line [i]")
	metric("probe_log_world_us", (REALTIMEOFDAY - start) * 100000 / calls, "us")
	start = REALTIMEOFDAY
	for(var/i in 1 to calls)
		world.time + i
		time2text(world.realtime, "hh:mm:ss")
	metric("probe_time2text_us", (REALTIMEOFDAY - start) * 100000 / calls, "us")
	var/list/floors = load_lag_area_floors(LOAD_LAG_AREA)
	var/list/humans = load_lag_crowd(floors, 4)
	var/mob/living/carbon/human/H = humans[1]
	var/draw_start = TICK_USAGE
	draw_now(H)
	metric("probe_human_first_draw_ms", TICK_USAGE_TO_MS(draw_start), "ms")
	var/total = 0
	for(var/i in 1 to 20)
		H.body?.invalidate(BODY_DIRTY_ORGANS)
		draw_start = TICK_USAGE
		draw_now(H)
		total += TICK_USAGE_TO_MS(draw_start)
	metric("probe_human_repeat_draw_ms", total / 20, "ms")

#undef LOAD_LAG_AREA
