// The cost of one radio broadcast on the mapped station, stage by stage: asking every radio on Common whether it receives (what
// collecting the radios cost before the listeners were placed first), finding the players who hear it (radio_hearers(), the
// bodies standing in for players), and the whole Broadcast_Message (categorising, formatting, delivery); then the arrival
// announcement. Headless, so nobody has a client: delivery is not in these numbers.
//   tools/build/build.sh bench --scenario=radio_broadcast -DCITESTING_FULL_MAP [--arg=messages=20] [--arg=mobs=4]

/datum/benchmark/radio_broadcast
	id = "radio_broadcast"
	description = "One Common broadcast on the full map by stage (radio collection, hearer search, whole message) and an arrival announcement"

/datum/benchmark/radio_broadcast/Run()
	wait_for_assets()
	var/messages = param("messages", 20)
	var/list/join = SSjob.late_spawn(null, JOB_INTERN)
	var/turf/T = join?["turf"]
	if(!isturf(T))
		fail("the job system gave a late joiner no arrivals turf")
	// A few bodies stand in for players: listening and registered as players, as a login makes them.
	var/list/made = list()
	for(var/n in 1 to param("mobs", 4))
		var/mob/living/carbon/human/H = new(T)
		H.mind_initialize()
		SSjob.equip_rank(H, JOB_INTERN, TRUE, FALSE)
		H.set_recursive_listening(LISTENING_PLAYER)
		registry_join(REGISTRY_PLAYERS, H)
		made += H
	refresh_flush()
	var/obj/item/radio/announcer = GLOB.global_announcer
	var/datum/radio_frequency/connection = announcer.radio_connection()
	var/list/levels = list(0)
	var/list/devices = connection.devices["[RADIO_CHAT]"]
	count_metric("devices_on_common", length(devices), "radios")

	begin_window()
	var/list/radios
	var/stamp = TICK_USAGE_REAL
	for(var/i in 1 to messages)
		radios = list()
		for(var/obj/item/radio/R in devices)
			if(R.receive_range(PUB_FREQ, levels) > -1)
				radios |= R
	metric("collect_ms", TICK_DELTA_TO_MS(TICK_USAGE_REAL - stamp) / messages, "ms")
	count_metric("receiving_radios", length(radios), "radios")

	// The bodies have no client, so a real broadcast leaves them out: this stage places them as listeners itself.
	var/list/hearers
	stamp = TICK_USAGE_REAL
	for(var/i in 1 to messages)
		hearers = radio_hearers(devices, made, PUB_FREQ, levels)
	metric("hearers_ms", TICK_DELTA_TO_MS(TICK_USAGE_REAL - stamp) / messages, "ms")
	count_metric("hearers", length(hearers), "mobs")

	stamp = TICK_USAGE_REAL
	for(var/i in 1 to messages)
		announcer.autosay("Benchmark broadcast [i].", "Benchmark", "Common")
	metric("broadcast_ms", TICK_DELTA_TO_MS(TICK_USAGE_REAL - stamp) / messages, "ms")

	var/mob/living/carbon/human/joiner = made[1]
	stamp = TICK_USAGE_REAL
	for(var/i in 1 to messages)
		AnnounceArrival(joiner, JOB_INTERN, "has arrived", "Common", joiner.z)
	metric("arrival_ms", TICK_DELTA_TO_MS(TICK_USAGE_REAL - stamp) / messages, "ms")
	end_window("radio")

	for(var/mob/living/carbon/human/H as anything in made)
		registry_leave(REGISTRY_PLAYERS, H)
		qdel(H)
