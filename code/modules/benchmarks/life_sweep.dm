// Mob Life scheduler cost across mob counts (doc/rewrite/life_on_om_benchmark.md).
//
// The same file runs on both schedulers being compared; each branch supplies the three
// adapter procs in life_sweep_adapter.dm:
//   life_bench_frames()  Life frames delivered to living mobs so far
//   life_bench_ms()      milliseconds spent so far in the subsystem that runs Life
//   life_bench_scheduler() a label
// One boot measures every configuration in turn: spawn, settle, measure a window, delete.
//   tools/build/build.sh bench --scenario=life_sweep -DLIFE_NO_PROFILE [--arg=seconds=40]

/datum/benchmark/life_sweep
	id = "life_sweep"
	description = "Mob Life cost for 32/128/512 humans and a simple-mob mix with hibernation"

/datum/benchmark/life_sweep/Run()
	wait_for_assets()
	var/list/turf/open/turfs = build_floor_fixture(param("width", 26))
	var/seconds = param("seconds", 40)
	detail("life_sweep_scheduler", life_bench_scheduler())
	// name = list(humans, busy mice, idle mice)
	var/list/configs = list(
		"h32" = list(32, 0, 0),
		"h128" = list(128, 0, 0),
		"h512" = list(512, 0, 0),
		"mix" = list(64, 96, 288),
	)
	for(var/name in configs)
		var/list/config = configs[name]
		run_config(name, turfs, config[1], config[2], config[3], seconds)

/datum/benchmark/life_sweep/proc/run_config(name, list/turfs, humans, busy_mice, idle_mice, seconds)
	var/list/mob/living/mobs = list()
	var/living_count = 0
	mark("[name]_before")
	for(var/i in 1 to humans)
		var/mob/living/carbon/human/H = new(pick(turfs))
		// Humans are low priority: without this they'd skip Life on a z-level with no players.
		H.low_priority = FALSE
		mobs += H
		CHECK_TICK
	for(var/i in 1 to busy_mice + idle_mice)
		var/mob/living/simple_mob/animal/passive/mouse/M = new(pick(turfs))
		benchmark_quiet_simple_mob(M)
		M.low_priority = FALSE
		if(i <= busy_mice)
			// A long sleep keeps its status systems (and so its Life) running on both schedulers.
			M.status_flags |= CANSTUN
			M.SetSleeping(100000)
		mobs += M
		CHECK_TICK
	living_count = length(mobs)
	metric("[name]_mobs", living_count, "mobs", "none")
	mark("[name]_spawned")
	// Settle: let idle mobs hibernate and every mob reach its steady state.
	wait_seconds(12)
	var/frames_before = life_bench_frames()
	var/ms_before = life_bench_ms()
	begin_window()
	wait_seconds(seconds)
	var/list/tick = end_window(name)
	var/frames = life_bench_frames() - frames_before
	var/ms = life_bench_ms() - ms_before
	var/elapsed = max(seconds, 1)
	metric("[name]_life_frames", frames, "frames", "none")
	metric("[name]_life_frames_per_mob_s", frames / living_count / elapsed, "frames", "none")
	metric("[name]_life_ms", ms, "ms")
	metric("[name]_life_ms_per_s", ms / elapsed, "ms/s")
	metric("[name]_life_us_per_frame", frames ? ms * 1000 / frames : 0, "us")
	var/hibernating = 0
	for(var/mob/living/L as anything in mobs)
		if(L.life_hibernating)
			hibernating++
	metric("[name]_hibernating", hibernating, "mobs", "none")
	detail("[name]_tick", tick)
	for(var/mob/living/L as anything in mobs)
		qdel(L)
		CHECK_TICK
	wait_seconds(5)
