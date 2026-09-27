// A whole-pipeline load: real humans run their ordinary Life schedule while body inputs change.
// Fixed indices and amounts make event counts and factor output reproducible.
// The windows include change production, monitor reads, Life, and the rest
// of the world's normal subsystem traffic. Compare identical runs on both trees.

// These producers use only the pre-object-model body API so this exact fixture
// also compiles at the pre-migration baseline commit.
/datum/modifier/benchmark_life_pipeline
	name = "benchmark Life factor source"
	factors = alist(BF_HEALING_RECEIVED = 2)

/datum/affliction/benchmark_life_pipeline
	name = "benchmark Life factor source"
	progression_rate = 0
	min_symptoms = 0
	max_symptoms = 0
	spontaneous_emote_prob = 0
	factors = alist(BF_HEART_RATE = 20)

/datum/benchmark/mob_life_body_pipeline
	id = "mob_life_body_pipeline"
	description = "Human Life, injuries, factor changes, monitor reads, and teardown"
	var/list/mob/living/carbon/human/subjects
	var/list/datum/affliction/benchmark_life_pipeline/sources
	var/list/datum/modifier/benchmark_life_pipeline/modifiers
	var/events = 0
	var/reads = 0
	var/checksum = 0

/datum/benchmark/mob_life_body_pipeline/Run()
	wait_for_assets()
	var/population = clamp(round(param("mobs", 64)), 8, 256)
	var/cycles = clamp(round(param("cycles", 12)), 2, 100)
	var/list/turf/open/floors = build_floor_fixture(max(12, round(sqrt(population)) + 4))
	subjects = list()
	sources = list()
	modifiers = list()
	mark("empty")
	var/spawn_start = REALTIMEOFDAY
	for(var/i in 1 to population)
		var/mob/living/carbon/human/H = new(floors[((i - 1) % length(floors)) + 1])
		var/datum/affliction/benchmark_life_pipeline/A = H.body.afflict(/datum/affliction/benchmark_life_pipeline)
		var/datum/modifier/benchmark_life_pipeline/M = H.add_modifier(/datum/modifier/benchmark_life_pipeline)
		if(!A || !M)
			fail("fixture body source creation failed at [i]")
		A.set_severity(100)
		subjects += H
		sources += A
		modifiers += M
		CHECK_TICK
	metric("spawn_seconds", (REALTIMEOFDAY - spawn_start) / 10, "s")
	metric("population", population, "mobs", "none")
	metric("cycles", cycles, "cycles", "none")
	mark("spawned")
	// Allow Life and caches to reach their ordinary idle state before sampling.
	wait_fires(SSmobs, SSmobs.life_slices * 3)
	metric("idle_hibernating", benchmark_count_hibernating(subjects), "mobs", "higher")
	var/idle_frames_before = count_life_frames()
	var/idle_biology_before = count_biology_steps()
	begin_window()
	wait_fires(SSmobs, SSmobs.life_slices * cycles)
	end_window("idle")
	metric("idle_life_frames", count_life_frames() - idle_frames_before, "frames", "none")
	metric("idle_biology_steps", count_biology_steps() - idle_biology_before, "steps", "none")
	mark("idle_complete")

	// Ordinary traffic: a small rotating subset changes once per Life cycle.
	measure_traffic("normal", cycles, max(1, round(population / 16)), FALSE)
	mark("normal_complete")
	// A monitoring consumer polls every other body after each event. Both trees
	// support this API, so its cost can be compared directly.
	measure_traffic("monitored_normal", cycles, max(1, round(population / 16)), TRUE)
	measure_traffic("monitored_heavy", cycles, max(1, round(population / 2)), TRUE)
	mark("traffic_complete")

	// Keep bodies alive through another idle window. A rising footprint here
	// suggests retained per-event state or accumulating timers.
	wait_fires(SSmobs, SSmobs.life_slices * cycles)
	mark("soak_complete")
	metric("events", events, "changes", "none")
	metric("monitor_reads", reads, "reads", "none")
	metric("factor_checksum", checksum, "factor units", "none")
	if(events <= 0 || reads <= 0 || checksum <= 0)
		fail("traffic phases did not exercise their inputs and outputs")
	if(count_life_frames() != count_biology_steps())
		fail("ordinary-rate biology steps diverged from Life frames")
	var/despawn_start = REALTIMEOFDAY
	begin_window()
	for(var/mob/living/carbon/human/H as anything in subjects)
		qdel(H)
		CHECK_TICK
	end_window("despawn")
	metric("despawn_seconds", (REALTIMEOFDAY - despawn_start) / 10, "s")
	subjects.Cut()
	sources.Cut()
	modifiers.Cut()
	mark("released")

/datum/benchmark/mob_life_body_pipeline/proc/measure_traffic(prefix, cycles, touches, observe)
	var/population = length(subjects)
	var/events_before = events
	var/reads_before = reads
	var/checksum_before = checksum
	var/frames_before = count_life_frames()
	var/biology_before = count_biology_steps()
	begin_window()
	for(var/cycle in 1 to cycles)
		for(var/step in 1 to touches)
			var/i = ((cycle - 1) * touches + step - 1) % population + 1
			var/mob/living/carbon/human/H = subjects[i]
			var/datum/affliction/benchmark_life_pipeline/A = sources[i]
			var/datum/modifier/benchmark_life_pipeline/M = modifiers[i]
			var/severity = (cycle % 2) ? 50 : 100
			var/healing = (cycle % 2) ? 0.5 : 2
			var/old_severity = A.severity
			var/old_heart = H.factor(BF_HEART_RATE)
			var/old_heal = H.factor(BF_HEALING_RECEIVED)
			var/old_modifier_heal = M.factors[BF_HEALING_RECEIVED]
			A.set_severity(severity)
			M.set_factors(alist(BF_HEALING_RECEIVED = healing))
			var/heart = H.factor(BF_HEART_RATE)
			var/heal = H.factor(BF_HEALING_RECEIVED)
			if(abs((heart - old_heart) - (severity - old_severity) * 0.2) > 0.01 || abs((heal - old_heal) - (healing - old_modifier_heal)) > 0.01)
				fail("stale factor value at [prefix] cycle [cycle] subject [i]: [heart], [heal]")
			checksum += heart + heal
			events++
			if(observe && i % 2 == 0)
				var/monitor_heart = H.factor(BF_HEART_RATE)
				var/monitor_heal = H.factor(BF_HEALING_RECEIVED)
				if(abs(monitor_heart - heart) > 0.01 || abs(monitor_heal - heal) > 0.01)
					fail("stale monitored factor value at [prefix] cycle [cycle] subject [i]")
				checksum += monitor_heart + monitor_heal
				reads++
			H.injure(INJURY_BLUNT, 1, BP_TORSO, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
			H.mend(TREAT_TISSUE_REPAIR, 1, BP_TORSO)
		wait_fires(SSmobs, SSmobs.life_slices)
	end_window(prefix)
	metric("[prefix]_events", events - events_before, "changes", "none")
	metric("[prefix]_monitor_reads", reads - reads_before, "reads", "none")
	metric("[prefix]_factor_checksum", checksum - checksum_before, "factor units", "none")
	metric("[prefix]_hibernating", benchmark_count_hibernating(subjects), "mobs", "higher")
	metric("[prefix]_life_frames", count_life_frames() - frames_before, "frames", "none")
	metric("[prefix]_biology_steps", count_biology_steps() - biology_before, "steps", "none")

/datum/benchmark/mob_life_body_pipeline/proc/count_life_frames()
	var/total = 0
	for(var/mob/living/carbon/human/H as anything in subjects)
		total += H.life_cycle
	return total

/datum/benchmark/mob_life_body_pipeline/proc/count_biology_steps()
	var/total = 0
	for(var/mob/living/carbon/human/H as anything in subjects)
		total += H.biological_cycle
	return total
