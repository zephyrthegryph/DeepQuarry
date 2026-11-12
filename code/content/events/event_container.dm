/datum/event_container
	var/severity = -1
	var/delayed = 0
	var/delay_modifier = 1
	COOLDOWN_DECLARE(next_event_time)
	/// Every event_meta this container made (owned); available_events and next_event name members of it.
	var/list/event_pool
	var/list/available_events
	/// event_meta handle -> world.time the event last fired.
	var/alist/last_event_time
	var/tmp/datum/event_meta/next_event

	var/last_world_time = 0

/// The random-event clock runs (the events service sets it when it makes the container).
/datum/event_container/var/clock_running = FALSE
CAPABILITIES(/datum/event_container)
	every(2 SECONDS, then(PROC_REF(event_clock_step)), when = nameof(clock_running))
	owns_many(nameof(event_pool))
	ref_one(nameof(next_event), /datum/event_meta)
	ref_many(nameof(available_events))

/// The random-event clock: every 2 s it advances (or, paused, pushes back) the next event.
/datum/event_container/proc/event_clock_step(datum/act/timer/A)
	if(!GLOB.round_start_time)
		return //don't do events if the round hasn't even started yet

	if(!next_event_time)
		set_event_delay()

	if(delayed || !CONFIG_GET(flag/allow_random_events))
		set_next_event_time(next_event_time + ((world.time - last_world_time)))
	else if(ELAPSED(src, next_event_time, CLOCK_WORLD) > 0)
		start_event()

	STAMP(src, last_world_time, CLOCK_WORLD)

/datum/event_container/proc/start_event()
	if(!next_event())	// If non-one has explicitly set an event, randomly pick one
		rel_set(src, nameof(next_event), acquire_event())

	// Has an event been acquired?
	if(next_event())
		// Set when the event of this type was last fired, and prepare the next event start
		ALAZYSET(last_event_time, handle_of(next_event()), world.time)
		set_event_delay()
		next_event().set_enabled(!next_event().one_shot)	// This event will no longer be available in the random rotation if one shot

		var/new_event_type_path = next_event().event_type
		new new_event_type_path(next_event())	// Events are added and removed from the processing queue in their New/kill procs

		log_game("Starting event '[next_event().name]' of severity [GLOB.severity_to_string[severity]].")
		rel_clear(src, nameof(next_event))						// When set to null, a random event will be selected next time
	else
		// If not, wait for one minute, instead of one tick, before checking again.
		set_next_event_time(next_event_time + ((60 * 10)))


/datum/event_container/proc/acquire_event()
	if(!length(available_events))
		return
	var/active_with_role = number_active_with_role()

	var/list/possible_events = list()
	for(var/datum/event_meta/EM in available_events)
		var/event_weight = get_weight(EM, active_with_role)
		if(event_weight > 0)
			possible_events[EM] = event_weight

	if(possible_events.len == 0)
		return null

	// Select an event and remove it from the pool of available events
	var/picked_event = pickweight(possible_events)
	rel_remove(src, nameof(available_events), picked_event)
	return picked_event

/datum/event_container/proc/get_weight(datum/event_meta/EM, list/active_with_role)
	if(!EM.enabled)
		return 0

	if(!(EM.minimum_active(active_with_role)))
		return 0

	var/weight = EM.get_weight(active_with_role)
	var/last_time = ALAZYACCESS(last_event_time, handle_of(EM))
	if(last_time)
		var/time_passed = world.time - last_time
		var/weight_modifier = max(0, round((CONFIG_GET(number/expected_round_length) - time_passed) / 300))
		weight = weight - weight_modifier

	return weight

/datum/event_container/proc/set_event_delay()
	var/list/event_delays

	switch(severity)
		if(EVENT_LEVEL_MUNDANE)
			event_delays = CONFIG_GET(keyed_list/event_first_run_mundane)
		if(EVENT_LEVEL_MODERATE)
			event_delays = CONFIG_GET(keyed_list/event_first_run_moderate)
		if(EVENT_LEVEL_MAJOR)
			event_delays = CONFIG_GET(keyed_list/event_first_run_major)

	// If the next event time has not yet been set and we have a custom first time start
	if(next_event_time == 0 && event_delays)
		var/lower = (event_delays["lower"] MINUTES)
		var/upper = (event_delays["upper"] MINUTES)
		var/event_delay = rand(lower, upper)
		COOLDOWN_START(src, next_event_time, event_delay)
	// Otherwise, follow the standard setup process
	else
		var/playercount_modifier = 1
		switch(REGISTRY_COUNT(REGISTRY_PLAYERS))
			if(0 to 10)
				playercount_modifier = 1.2
			if(11 to 15)
				playercount_modifier = 1.1
			if(16 to 25)
				playercount_modifier = 1
			if(26 to 35)
				playercount_modifier = 0.9
			if(36 to 100000)
				playercount_modifier = 0.8
		playercount_modifier = playercount_modifier * delay_modifier

		var/event_delay = rand(CONFIG_GET(number_list/event_delay_lower)[severity] MINUTES, CONFIG_GET(number_list/event_delay_upper)[severity] MINUTES) * playercount_modifier
		COOLDOWN_START(src, next_event_time, event_delay)

	log_game("Next event of severity [GLOB.severity_to_string[severity]] in [(next_event_time - world.time)/600] minutes.")

/datum/event_container/proc/SelectEvent(mob/user)
	open_request(src, /datum/prompt/choice/queue_event, PROC_REF(event_selected), answerer = user, choices = available_events?.Copy())

/// Picking the next event of its owner container: still available when answered.
/datum/prompt/choice/queue_event
	title = "Event Selection"
	question = "Select an event to queue up."
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/queue_event/recheck_extra()
	if(QDELETED(owner) || QDELETED(answerer))
		return "gone"
	if(isnull(value))
		return null
	var/datum/event_container/container = owner
	return (value && (value in container.available_events)) ? null : "not available"

/datum/event_container/proc/event_selected(datum/act/request/context)
	if(!context.answer)
		return
	var/mob/user = context.request.answerer
	var/datum/event_meta/EM = context.answer.value
	if(next_event())
		rel_add(src, nameof(available_events), next_event())
	rel_remove(src, nameof(available_events), EM)
	rel_set(src, nameof(next_event), EM)
	log_and_message_admins("has queued the [GLOB.severity_to_string[severity]] event '[EM.name]'.", user)

/datum/event_container/mundane
	severity = EVENT_LEVEL_MUNDANE
	available_events = list(
		// Severity level, event name, even type, base weight, role weights, one shot, min weight, max weight. Last two only used if set and non-zero
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Nothing",			/datum/event/nothing,			100),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "APC Damage",		/datum/event/apc_damage,		20, 	list(DEPARTMENT_ENGINEERING = 20)),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Brand Intelligence",/datum/event/brand_intelligence,20, 	list(JOB_JANITOR = 25),	1),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Camera Damage",		/datum/event/camera_damage,		20, 	list(DEPARTMENT_ENGINEERING = 20)),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Economic News",		/datum/event/economic_event,	300),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Lost Carp",			/datum/event/carp_migration, 	20, 	list(DEPARTMENT_SECURITY = 10), 1),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Money Hacker",		/datum/event/money_hacker, 		0, 		list(DEPARTMENT_ANY = 4), 1, 10, 25),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Money Lotto",		/datum/event/money_lotto, 		0, 		list(DEPARTMENT_ANY = 1), 1, 5, 15),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Shipping Error",	/datum/event/shipping_error	, 	30, 	list(DEPARTMENT_ANY = 2), 0),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Space Dust",		/datum/event/dust	, 			60, 	list(DEPARTMENT_ENGINEERING = 20), 0, 0, 50),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Trivial News",		/datum/event/trivial_news, 		400),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Lore News",			/datum/event/lore_news, 		400),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Vermin Infestation",/datum/event/infestation, 		100,	list(JOB_JANITOR = 100)),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Wallrot",			/datum/event/wallrot, 			0,		list(DEPARTMENT_ENGINEERING = 30, JOB_BOTANIST = 50)),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Aurora Caelus",		/datum/event/aurora_caelus,		2,		list(), 1),
	)

/datum/event_container/moderate
	severity = EVENT_LEVEL_MODERATE
	available_events = list(
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Nothing",					/datum/event/nothing,					800),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Appendicitis", 			/datum/event/spontaneous_appendicitis, 	0,		list(DEPARTMENT_MEDICAL = 30), 1),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Carp School",				/datum/event/carp_migration,			100, 	list(DEPARTMENT_ENGINEERING = 20, DEPARTMENT_SECURITY = 30), 1),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Communication Blackout",	/datum/event/communications_blackout,	500,	list(JOB_AI = 150, DEPARTMENT_SECURITY = 120)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Electrical Storm",			/datum/event/electrical_storm, 			250,	list(DEPARTMENT_ENGINEERING = 20, JOB_JANITOR = 150)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Gravity Failure",			/datum/event/gravity,	 				75,		list(DEPARTMENT_ENGINEERING = 60)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Grid Check",				/datum/event/grid_check, 				200,	list(DEPARTMENT_RESEARCH = 10)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Ion Storm",				/datum/event/ionstorm, 					0,		list(JOB_AI = 80, JOB_CYBORG = 50, DEPARTMENT_ENGINEERING = 15, DEPARTMENT_RESEARCH = 5)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Meteor Shower",			/datum/event/meteor_wave,				30,		list(DEPARTMENT_ENGINEERING = 20)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Prison Break",				/datum/event/prison_break,				10,		list(DEPARTMENT_SECURITY = 100)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Radiation Storm",			/datum/event/radiation_storm, 			50,		list(DEPARTMENT_MEDICAL = 50), 1),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Random Antagonist",		/datum/event/random_antag,		 		2.5,	list(DEPARTMENT_SECURITY = 1), 1, 0, 5),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Rogue Drones",				/datum/event/rogue_drone, 				20,		list(DEPARTMENT_SECURITY = 60)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Solar Storm",				/datum/event/solar_storm, 				30,		list(DEPARTMENT_ENGINEERING = 40, DEPARTMENT_SECURITY = 30), 1),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Space Dust",				/datum/event/dust,	 					80, 	list(DEPARTMENT_ENGINEERING = 30)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Spider Infestation",		/datum/event/spider_infestation, 		100,	list(DEPARTMENT_SECURITY = 40), 1),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Virology Breach",			/datum/event/prison_break/virology,		0,		list(DEPARTMENT_MEDICAL = 100)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Xenobiology Breach",		/datum/event/prison_break/xenobiology,	0,		list(DEPARTMENT_RESEARCH = 100)),
	)

/datum/event_container/major
	severity = EVENT_LEVEL_MAJOR
	available_events = list(
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Nothing",				/datum/event/nothing,			900),
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Blob",				/datum/event/blob, 				10,	list(DEPARTMENT_ENGINEERING = 60), 1),
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Carp Migration",		/datum/event/carp_migration,	10,	list(DEPARTMENT_SECURITY = 10), 1),
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Containment Breach",	/datum/event/prison_break/station,0,list(DEPARTMENT_ANY = 5)),
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Meteor Wave",			/datum/event/meteor_wave,		30,	list(DEPARTMENT_ENGINEERING = 30),	1),
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Space Vines",			/datum/event/spacevine, 		20,	list(DEPARTMENT_ENGINEERING = 15), 1),
	)

/// Accessor for the next_event var.
/datum/event_container/proc/next_event() as /datum/event_meta
	return next_event

// The rotation each container starts with: its New() replaces the lists of available events (the container types above define no New()),
// moving the events that are not wanted down into the disabled list.

// Adds a list of pre-disabled events to the available events list.
// This keeps them in the rotation, but disabled, so they can be enabled with a click if desired that round.
/datum/event_container/proc/add_disabled_events(list/disabled_events)
	for(var/datum/event_meta/EM in disabled_events)
		EM.set_enabled(0)
		rel_add(src, nameof(event_pool), EM)
		rel_add(src, nameof(available_events), EM)

/// Replaces the rotation with `metas`: the container owns each one (event_pool) and
/// lists it as available (a relation, so a queued or fired meta stays owned).
/datum/event_container/proc/set_available_events(list/metas)
	rel_clear(src, nameof(available_events))
	for(var/datum/event_meta/EM as anything in metas)
		rel_add(src, nameof(event_pool), EM)
		rel_add(src, nameof(available_events), EM)

/datum/event_container/mundane/New()
	set_available_events(list(
		// Severity level, event name, even type, base weight, role weights, one shot, min weight, max weight. Last two only used if set and non-zero
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Nothing",				/datum/event/nothing,						400),
		// Bluescreens APCs, but they still work
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "APC Damage",			/datum/event/apc_damage,					20, 	list(DEPARTMENT_ENGINEERING = 20, JOB_CHIEF_ENGINEER = 10), min_jobs = list(DEPARTMENT_ENGINEERING = 1)),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Aurora Caelus",			/datum/event/aurora_caelus,					2,		list(), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Brand Intelligence",	/datum/event/brand_intelligence,			20, 	list(JOB_JANITOR = 25),	TRUE, min_jobs = list(DEPARTMENT_ENGINEERING = 1)),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Canister Leak",			/datum/event/canister_leak,					10, 	list(DEPARTMENT_ENGINEERING = 20)),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Economic News",			/datum/event/economic_event,				300),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Electrified Door",		/datum/event/electrified_door,				-5, 	list(DEPARTMENT_MEDICAL = 5, DEPARTMENT_ENGINEERING = 20, JOB_CHIEF_ENGINEER = 10, JOB_AI = 10)),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Jellyfish School",		/datum/event/jellyfish_migration,			5,		list(DEPARTMENT_ANY = 1, DEPARTMENT_SECURITY = 5, DEPARTMENT_MEDICAL = 3), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Lone Spacefish",		/datum/event/spacefish_migration, 			0,		list(DEPARTMENT_SECURITY = 15, JOB_HEAD_OF_SECURITY = 5, JOB_WARDEN = 5, DEPARTMENT_ANY = 2), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Money Hacker",			/datum/event/money_hacker, 					0, 		list(DEPARTMENT_ANY = 4), TRUE, 10, 25),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Money Lotto",			/datum/event/money_lotto, 					0, 		list(DEPARTMENT_ANY = 1), TRUE, 5, 15),
		//new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Mundane News", 		/datum/event/mundane_news, 					300),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Shipping Error",		/datum/event/shipping_error	, 				30, 	list(DEPARTMENT_ANY = 2), FALSE),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Space Dust",			/datum/event/dust,	 						0, 		list(DEPARTMENT_ENGINEERING = 20), FALSE, 0, 50),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Trivial News",			/datum/event/trivial_news, 					400),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Lore News",				/datum/event/lore_news, 					400),
		// /datum/event/supply_demand was in supply_demand_vr.dm (deleted with ZAS).
		// Spawns mice, lizards, or dud spiderlings
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Vermin Infestation",	/datum/event/infestation, 					100,	list(DEPARTMENT_ANY = 5, JOB_JANITOR = 100), TRUE),
		// Rot only weakens walls, not destroy them
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Wallrot",				/datum/event/wallrot, 						0,		list(DEPARTMENT_ENGINEERING = 30, JOB_BOTANIST = 50), TRUE),
	))
	add_disabled_events(list(
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Lost Carp",				/datum/event/carp_migration, 				0, 		list(DEPARTMENT_SECURITY = 40), TRUE, min_jobs = list(DEPARTMENT_SECURITY = 1)),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Ian Storm",				/datum/event/ianstorm,	 					1,		list(), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MUNDANE, "PDA Spam",				/datum/event/pda_spam, 						0, 		list(DEPARTMENT_ANY = 4), TRUE, 25, 50),
// new /datum/event_meta(EVENT_LEVEL_MUNDANE, "Lost Spiders", /datum/event/spider_migration, 0, list(DEPARTMENT_SECURITY = 10), 1), // // Moved to disabled and commented. This just spawns spiders on carp spawns.
	))

/datum/event_container/moderate/New()
	set_available_events(list(
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Nothing",					/datum/event/nothing,					1600),
		// Leaks gas into an unoccupied room.
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Appendicitis", 			/datum/event/spontaneous_appendicitis, 	-30,	list(DEPARTMENT_MEDICAL = 30, JOB_CHIEF_MEDICAL_OFFICER = 10, DEPARTMENT_ANY = 2), TRUE, min_jobs = list(DEPARTMENT_MEDICAL = 2)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Bluespace Anomaly",		/datum/event/anomaly/bluespace,			20,		list(DEPARTMENT_RESEARCH = 40, JOB_RESEARCH_DIRECTOR = 20, DEPARTMENT_ANY = 2), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Bluespace Lockers",		/datum/event/bluespace_locker,			10,		list(DEPARTMENT_RESEARCH = 30, JOB_RESEARCH_DIRECTOR = 20, DEPARTMENT_ANY = 2), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Bioscrambler Anomaly",		/datum/event/anomaly/bioscrambler,		10,		list(DEPARTMENT_MEDICAL = 30, JOB_CHIEF_MEDICAL_OFFICER = 10, DEPARTMENT_RESEARCH = 20, JOB_RESEARCH_DIRECTOR = 10, DEPARTMENT_ANY = 2), TRUE, min_jobs = list(DEPARTMENT_MEDICAL = 1)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Atmos Leak",				/datum/event/atmos_leak, 				30,		list(DEPARTMENT_ENGINEERING = 25, DEPARTMENT_ANY = 2), TRUE),
		// Just disables comms for a short while.
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Communication Blackout",	/datum/event/communications_blackout,	250,	list(JOB_AI = 100, DEPARTMENT_SECURITY = 50, DEPARTMENT_ANY = 2), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Dimensional Anomaly",		/datum/event/anomaly/dimensional,		40,		list(DEPARTMENT_RESEARCH = 30, JOB_RESEARCH_DIRECTOR = 20, DEPARTMENT_ANY = 2), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Drone Pod Drop",			/datum/event/drone_pod_drop,			10,		list(DEPARTMENT_RESEARCH = 40, DEPARTMENT_ANY = 2), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Dust Anomaly",				/datum/event/anomaly/dust, 				30,		list(JOB_JANITOR = 30, DEPARTMENT_RESEARCH = 20, JOB_RESEARCH_DIRECTOR = 15, DEPARTMENT_ANY = 2), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Flux Anomaly",				/datum/event/anomaly/flux,				20,		list(DEPARTMENT_ENGINEERING = 30, JOB_CHIEF_ENGINEER = 20, DEPARTMENT_RESEARCH = 25, JOB_RESEARCH_DIRECTOR = 15, DEPARTMENT_ANY = 2), TRUE),
		// Just blows out a few lights
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Electrical Storm",			/datum/event/electrical_storm, 			250,	list(DEPARTMENT_ENGINEERING = 20, JOB_JANITOR = 150, DEPARTMENT_ANY = 2), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Exotic Infestation",		/datum/event/dangerinfestation, 		-30,	list(DEPARTMENT_ENGINEERING = 20, DEPARTMENT_RESEARCH = 5, DEPARTMENT_ANY = 2)),
		//Escaped slime event itself needs to be rejiggered because of the mob refactor.
		//new /datum/event_meta(EVENT_LEVEL_MODERATE, "Escaped Slimes",			/datum/event/escaped_slimes, 			-40,	list(DEPARTMENT_RESEARCH = 30, DEPARTMENT_SECURITY = 20)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Gravity Anomaly", 			/datum/event/anomaly/grav, 				20,		list(DEPARTMENT_ENGINEERING = 30, JOB_CHIEF_ENGINEER = 20, DEPARTMENT_RESEARCH = 20, JOB_RESEARCH_DIRECTOR = 10, DEPARTMENT_ANY = 2), TRUE),
		// This one is just too fun.
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Gravity Failure",			/datum/event/gravity,	 				75,		list(DEPARTMENT_ENGINEERING = 60, DEPARTMENT_ANY = 2), TRUE),
		// Temporary power failure, but mitigatead by subgrids
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Grid Check",				/datum/event/grid_check, 				0,		list(DEPARTMENT_RESEARCH = 10, DEPARTMENT_ENGINEERING = 25, DEPARTMENT_ANY = 2), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Grub Infestation",			/datum/event/grub_infestation,			-20,	list(DEPARTMENT_SECURITY = 40, DEPARTMENT_ENGINEERING = 40, DEPARTMENT_ANY = 2), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Hallucination Anomaly",	/datum/event/anomaly/hallucination,		10,		list(DEPARTMENT_MEDICAL = 20, JOB_CHIEF_MEDICAL_OFFICER = 10, DEPARTMENT_RESEARCH = 20, JOB_RESEARCH_DIRECTOR = 10, DEPARTMENT_ANY = 2), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Hostile Runtime",			/datum/event/hostile_runtime,			-20,	list(DEPARTMENT_ENGINEERING = 40, JOB_CHIEF_ENGINEER = 30, DEPARTMENT_ANY = 2), min_jobs = list(DEPARTMENT_ENGINEERING = 1)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Infected Room",			/datum/event/disease_outbreak/floor,	-30,	list(DEPARTMENT_MEDICAL = 25, JOB_CHIEF_MEDICAL_OFFICER = 15, JOB_JANITOR = 10, DEPARTMENT_ANY = 2), TRUE, min_jobs = list(DEPARTMENT_MEDICAL = 2)),
		// Pure RP fun, no mechanical effects.
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Ion Storm",				/datum/event/ionstorm, 					-100,	list(JOB_AI = 80, JOB_CYBORG = 50, DEPARTMENT_ENGINEERING = 15, DEPARTMENT_RESEARCH = 5, DEPARTMENT_ANY = 2), min_jobs = list(JOB_CYBORG = 1, JOB_ROBOTICIST = 1)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Maintenance Critter",		/datum/event/maintenance_critter,		175,	list(DEPARTMENT_ANY = 5), FALSE),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Meteor Shower",			/datum/event/meteor_wave,				-50,	list(DEPARTMENT_ENGINEERING = 45, DEPARTMENT_ANY = 2), TRUE, min_jobs = list(DEPARTMENT_ENGINEERING = 2)),
		//New event. Mice and lizards grow into rats and lizardmen respectively.
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Mutants",					/datum/event/mutants,					20,		list(DEPARTMENT_ANY = 15, DEPARTMENT_SECURITY = 25), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Pyroclastic Anomaly", 		/datum/event/anomaly/pyro,				-40,	list(DEPARTMENT_ENGINEERING = 30, JOB_CHIEF_ENGINEER = 20, DEPARTMENT_RESEARCH = 20, JOB_RESEARCH_DIRECTOR = 10, DEPARTMENT_ANY = 2), TRUE, min_jobs = list(DEPARTMENT_ENGINEERING = 2)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Radiation Storm",			/datum/event/radiation_storm, 			50,		list(DEPARTMENT_MEDICAL = 50, DEPARTMENT_ANY = 2), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Rogue Drones",				/datum/event/rogue_drone, 				-30,	list(DEPARTMENT_SECURITY = 25, JOB_HEAD_OF_SECURITY = 35, JOB_WARDEN = 35, DEPARTMENT_ANY = 2), min_jobs = list(DEPARTMENT_SECURITY = 2)),
		// Radiation, but only in space.
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Solar Storm",				/datum/event/solar_storm, 				20,		list(DEPARTMENT_ENGINEERING = 40, DEPARTMENT_SECURITY = 20, DEPARTMENT_ANY = 2), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Spacefish Migration",		/datum/event/spacefish_migration,		0, 		list(DEPARTMENT_SECURITY = 40, JOB_HEAD_OF_SECURITY = 20, JOB_WARDEN = 20, DEPARTMENT_MEDICAL = 10, DEPARTMENT_ANY = 2), TRUE, min_jobs = list(DEPARTMENT_SECURITY = 1)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Spider Infestation",		/datum/event/spider_infestation, 		-20,	list(DEPARTMENT_SECURITY = 30, JOB_HEAD_OF_SECURITY = 20, JOB_WARDEN = 20, DEPARTMENT_ANY = 2), FALSE, min_jobs = list(DEPARTMENT_SECURITY = 1)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Spontaneous Malignant Organ", 	/datum/event/spontaneous_malignant_organ, 	-30,	list(DEPARTMENT_MEDICAL = 30, JOB_CHIEF_MEDICAL_OFFICER = 20, DEPARTMENT_ANY = 2), TRUE, min_jobs = list(DEPARTMENT_MEDICAL = 2)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Weather Anomaly",			/datum/event/anomaly/weather,			20,		list(DEPARTMENT_RESEARCH = 40, JOB_RESEARCH_DIRECTOR = 20, DEPARTMENT_ANY = 2), TRUE),
	))
	add_disabled_events(list(
		new /datum/event_meta(EVENT_LEVEL_MUNDANE,  "Camera Damage",			/datum/event/camera_damage,				20, 	list(DEPARTMENT_SECURITY = 5, DEPARTMENT_ENGINEERING = 20), min_jobs = list(DEPARTMENT_ENGINEERING = 1)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Meteor Shower",			/datum/event/meteor_wave,				30,		list(DEPARTMENT_ENGINEERING = 20), min_jobs = list(DEPARTMENT_ENGINEERING = 3)),
		// Rework these at one point
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Meaty Ore Shower",			/datum/event/meteor_wave/meatyores,		-50,	list(DEPARTMENT_ENGINEERING = 45), TRUE, min_jobs = list(DEPARTMENT_ENGINEERING = 2)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Prison Break",				/datum/event/prison_break,				-10,	list(DEPARTMENT_SECURITY = 30, DEPARTMENT_ENGINEERING = 20), TRUE, min_jobs = list(DEPARTMENT_SECURITY = 2)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Random Antagonist",		/datum/event/random_antag,		 		2.5,	list(DEPARTMENT_SECURITY = 1), TRUE, 0, 5),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Carp School",				/datum/event/carp_migration,			-20, 	list(DEPARTMENT_ENGINEERING = 10, DEPARTMENT_SECURITY = 30, JOB_HEAD_OF_SECURITY = 10, JOB_WARDEN = 5), TRUE, min_jobs = list(DEPARTMENT_SECURITY = 2)),
		// /datum/event/supply_demand deleted with supply_demand_vr.dm.
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Space Dust",				/datum/event/dust,	 					0,		list(DEPARTMENT_ENGINEERING = 20), TRUE, 0, 50),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Disease Outbreak",			/datum/event/disease_outbreak,			-30,	list(DEPARTMENT_MEDICAL = 30, DEPARTMENT_ANY = 1), TRUE, min_jobs = list(DEPARTMENT_MEDICAL = 2)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Virology Breach",			/datum/event/prison_break/virology,		0,		list(DEPARTMENT_MEDICAL = 100), TRUE, min_jobs = list(DEPARTMENT_MEDICAL = 1)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Wormholes",				/datum/event/wormholes,	 				20,		list(DEPARTMENT_ANY = 5)),
		new /datum/event_meta(EVENT_LEVEL_MODERATE, "Xenobiology Breach",		/datum/event/prison_break/xenobiology,	0,		list(DEPARTMENT_RESEARCH = 100), TRUE, min_jobs = list(DEPARTMENT_RESEARCH = 1, DEPARTMENT_SECURITY =1)),
// new /datum/event_meta(EVENT_LEVEL_MODERATE, "Lost Spiders", /datum/event/spider_migration, 0, list(DEPARTMENT_SECURITY = 30), 1), // // Moved to disabled. This is a YW feature that spawns spiders on carp spawns.
	))

/datum/event_container/major/New()
	set_available_events(list(
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Nothing",						/datum/event/nothing,					900),
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Atmos Leak",					/datum/event/atmos_leak, 				5,		list(DEPARTMENT_ENGINEERING = 35, JOB_CHIEF_ENGINEER = 25, DEPARTMENT_ANY = 2), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Blob",						/datum/event/blob, 						-100,	list(DEPARTMENT_SECURITY = 40, JOB_HEAD_OF_SECURITY = 10, JOB_WARDEN = 10, DEPARTMENT_ENGINEERING = 5, DEPARTMENT_ANY = 2), TRUE, min_jobs = list(DEPARTMENT_SECURITY = 1)),
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Carp Migration",				/datum/event/carp_migration,			-100,	list(DEPARTMENT_SECURITY = 50, JOB_HEAD_OF_SECURITY = 10, JOB_WARDEN = 10, DEPARTMENT_ANY = 2), TRUE, min_jobs = list(DEPARTMENT_SECURITY = 1)),
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Electrical Fire",				/datum/event/electrical_fire,	 		-20,	list(DEPARTMENT_ENGINEERING = 15, JOB_CYBORG = 5, DEPARTMENT_ANY = 2), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Electrical Storm",			/datum/event/electrical_storm, 			20,		list(DEPARTMENT_ENGINEERING = 20, JOB_CHIEF_ENGINEER = 10, JOB_JANITOR = 75, DEPARTMENT_ANY = 2), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Exotic Horde Infestation",	/datum/event/highdangerinfestation, 	-50,	list(DEPARTMENT_ENGINEERING = 20, JOB_CHIEF_ENGINEER = 10, DEPARTMENT_RESEARCH = 5, DEPARTMENT_ANY = 2), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Horde Infestation",			/datum/event/horde_infestation, 		-30,	list(DEPARTMENT_SECURITY = 20, JOB_HEAD_OF_SECURITY = 10, JOB_WARDEN = 10, DEPARTMENT_ANY = 3), FALSE),
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Hostile Runtime",				/datum/event/hostile_runtime,			-20,	list(DEPARTMENT_ENGINEERING = 40, JOB_CHIEF_ENGINEER = 30), TRUE, min_jobs = list(DEPARTMENT_ENGINEERING = 1)),
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Infected Room",				/datum/event/disease_outbreak/floor,	-50,	list(DEPARTMENT_MEDICAL = 25, JOB_CHIEF_MEDICAL_OFFICER = 15, JOB_JANITOR = 10, DEPARTMENT_ANY = 2), TRUE, min_jobs = list(DEPARTMENT_MEDICAL = 2)),
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Meteor Wave",					/datum/event/meteor_wave,				-70,	list(DEPARTMENT_ENGINEERING = 50, DEPARTMENT_MEDICAL = 10, DEPARTMENT_ANY = 2),	TRUE, min_jobs = list(DEPARTMENT_ENGINEERING = 1)),
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Spacefish Swarm",				/datum/event/spacefish_migration,		10,		list(DEPARTMENT_SECURITY = 15, JOB_HEAD_OF_SECURITY = 10, JOB_WARDEN = 10, DEPARTMENT_MEDICAL = 5), TRUE),
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Space Vines",					/datum/event/spacevine, 				20,		list(DEPARTMENT_ENGINEERING = 15, DEPARTMENT_ANY = 2), TRUE),
	))
	add_disabled_events(list(
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Containment Breach",			/datum/event/prison_break/station,		0,		list(DEPARTMENT_ANY = 5),0),
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Disease Outbreak",			/datum/event/disease_outbreak,			-30,	list(DEPARTMENT_MEDICAL = 30, DEPARTMENT_ANY = 1), 	TRUE, min_jobs = list(DEPARTMENT_MEDICAL = 2)),
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Jellyfish Migration",			/datum/event/jellyfish_migration,		5,		list(DEPARTMENT_ANY = 1, DEPARTMENT_SECURITY = 5, DEPARTMENT_MEDICAL = 3), TRUE),
		//Spiders moved into horde infestation
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Spider Infestation",			/datum/event/spider_infestation, 		-60,	list(DEPARTMENT_SECURITY = 20, JOB_HEAD_OF_SECURITY = 10, JOB_WARDEN = 10, DEPARTMENT_ANY = 3), FALSE),
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Meaty Ores Wave",				/datum/event/meteor_wave/meatyores,		-90,	list(DEPARTMENT_ENGINEERING = 50, DEPARTMENT_MEDICAL = 10, DEPARTMENT_ANY = 1),	TRUE, min_jobs = list(DEPARTMENT_ENGINEERING = 1)),
		//Metroids moved into horde infestation
		new /datum/event_meta(EVENT_LEVEL_MAJOR, "Metroid Infestation",			/datum/event/metroid_infestation,		-100,	list(DEPARTMENT_SECURITY = 30, DEPARTMENT_RESEARCH = 20, JOB_HEAD_OF_SECURITY = 15, JOB_WARDEN = 15, DEPARTMENT_ANY = 2), TRUE, min_jobs = list(DEPARTMENT_SECURITY = 2, DEPARTMENT_RESEARCH = 1)),
		// new /datum/event_meta(EVENT_LEVEL_MAJOR, "Viral Infection",				/datum/event/viral_infection,			-50,	list(DEPARTMENT_MEDICAL = 25), 	1, min_jobs = list(DEPARTMENT_MEDICAL = 2)),

	))
