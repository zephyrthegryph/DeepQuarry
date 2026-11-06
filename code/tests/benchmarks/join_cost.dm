// The cost of a join, phase by phase, in a production-style build (no unit-test shared-cache verification, which inflates every
// property read): the body, the job's equipment, the draws that follow, and the manifest record. The first join of the round is
// reported apart from the later ones.
//   tools/build/build.sh bench --scenario=join_cost [--arg=joins=6]

/datum/benchmark/join_cost
	id = "join_cost"
	description = "Phase cost of a late join: body, equip, first draws, manifest record; the first join apart from the rest"

/datum/benchmark/join_cost/Run()
	wait_for_assets()
	var/list/join = SSjob.late_spawn(null, JOB_INTERN)
	var/turf/T = join?["turf"]
	if(!isturf(T))
		fail("the job system gave a late joiner no arrivals turf")
	var/joins = param("joins", 6)
	var/list/sums = list("body" = 0, "equip" = 0, "draws" = 0, "register" = 0)
	var/list/made = list()
	begin_window()
	for(var/n in 1 to joins)
		var/stamp = TICK_USAGE_REAL
		var/mob/living/carbon/human/H = new(T)
		var/body_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - stamp)
		H.mind_initialize()
		stamp = TICK_USAGE_REAL
		SSjob.equip_rank(H, JOB_INTERN, TRUE, FALSE)
		var/equip_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - stamp)
		stamp = TICK_USAGE_REAL
		refresh_flush()
		var/draws_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - stamp)
		stamp = TICK_USAGE_REAL
		latejoin_register(H, JOB_INTERN, "has arrived", "Common", H.z)
		var/register_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - stamp)
		var/list/row = list("body" = body_ms, "equip" = equip_ms, "draws" = draws_ms, "register" = register_ms)
		if(n == 1)
			for(var/phase in row)
				metric("first_[phase]_ms", row[phase], "ms")
		else
			for(var/phase in row)
				sums[phase] += row[phase]
		made += H
		stoplag()
	end_window("joins")
	for(var/phase in sums)
		metric("warm_[phase]_ms", sums[phase] / max(1, joins - 1), "ms")
	for(var/mob/living/carbon/human/H as anything in made)
		qdel(H)
