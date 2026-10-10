// Phase 1S, worker A: the first half of the world services, ported to systems (SYSTEM_DEF). One focused test per
// system: it is the registered singleton, it booted, its declared work is a kernel work item with the cadence the
// service had, and its step does the service's job through the step protocol.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// The work item `S` registered for `handler` (a PROC_REF name), or null.
/proc/dq_system_work(datum/system/S, handler)
	return kernel().work_by_key["[S.type]:[handler]"]

/// Common checks for a ported system: singleton, booted.
/datum/unit_test/proc/assert_system_ported(datum/system/S, path)
	TEST_ASSERT_NOTNULL(S, "[path]: the SS accessor is unset")
	TEST_ASSERT_EQUAL(system(path), S, "[path]: system(path) is not the SS accessor's datum")
	TEST_ASSERT_EQUAL(S.type, path, "[path]: the accessor holds a different type")
	TEST_ASSERT(S.initialized, "[path]: the system never booted")

/// The work item of `S` for `handler`: declared, with its cadence and lane.
/datum/unit_test/proc/assert_work_declared(datum/system/S, handler, interval, lane = null)
	var/datum/work_item/W = dq_system_work(S, handler)
	TEST_ASSERT_NOTNULL(W, "[S.type] declares no work item for [handler]")
	TEST_ASSERT_EQUAL(W.interval, interval, "[S.type]:[handler] lost the service's cadence")
	TEST_ASSERT_EQUAL(W.run_when, nameof(/datum/system/proc/work_ready), "[S.type]:[handler] is not gated on work_ready()")
	if(!isnull(lane))
		TEST_ASSERT_EQUAL(W.lane, lane, "[S.type]:[handler] runs in the wrong lane")
	return W

/// The AFK kick system: one pass per minute on the background lane, nothing to do while the config is off.
/datum/unit_test/dq_system_inactivity

/datum/unit_test/dq_system_inactivity/Run()
	assert_system_ported(SSinactivity, /datum/system/inactivity)
	assert_work_declared(SSinactivity, nameof(/datum/system/inactivity/proc/kick_step), 1 MINUTE, LANE_BACKGROUND)
	TEST_ASSERT_EQUAL(SSinactivity.periodic_runlevels, RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT, "the AFK kick lost its lobby runlevel")
	TEST_ASSERT_EQUAL(SSinactivity.kick_step(0), STEP_DONE, "a pass with the config off must finish at once")

/// The lobby window watchdog: every 2 s, finishes in one pass, shows the restart animation on shutdown.
/datum/unit_test/dq_system_lobby_monitor

/datum/unit_test/dq_system_lobby_monitor/Run()
	assert_system_ported(SSlobby_monitor, /datum/system/lobby_monitor)
	assert_work_declared(SSlobby_monitor, nameof(/datum/system/lobby_monitor/proc/watch_lobby), 2 SECONDS)
	TEST_ASSERT_EQUAL(SSlobby_monitor.periodic_runlevels, 0, "the lobby monitor runs in every runlevel")
	var/list/saved = SSlobby_monitor.to_reinitialize
	SSlobby_monitor.to_reinitialize = list()
	TEST_ASSERT_EQUAL(SSlobby_monitor.watch_lobby(0), STEP_DONE, "the lobby pass did not finish")
	SSlobby_monitor.to_reinitialize = saved

/// The soft ping: every 4 s, nothing to ping without clients.
/datum/unit_test/dq_system_ping

/datum/unit_test/dq_system_ping/Run()
	assert_system_ported(SSping, /datum/system/ping)
	assert_work_declared(SSping, nameof(/datum/system/ping/proc/ping_clients), 4 SECONDS)
	TEST_ASSERT_EQUAL(SSping.periodic_runlevels, RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT, "the ping lost its lobby runlevel")
	SSping.currentrun = list()
	TEST_ASSERT_EQUAL(SSping.ping_clients(0), STEP_DONE, "a ping pass over no clients must finish")

/// The PTO accrual: every 15 minutes, a pass with the time-off config off or no database is a no-op that finishes.
/datum/unit_test/dq_system_persist

/datum/unit_test/dq_system_persist/Run()
	assert_system_ported(SSpersist, /datum/system/persist)
	assert_work_declared(SSpersist, nameof(/datum/system/persist/proc/accrue_pto), 15 MINUTES, LANE_BACKGROUND)
	TEST_ASSERT_EQUAL(SSpersist.accrual_interval, 15 MINUTES, "the accrual period no longer matches the work interval")
	TEST_ASSERT_EQUAL(SSpersist.periodic_runlevels, RUNLEVEL_GAME | RUNLEVEL_POSTGAME, "PTO accrues outside the game")
	TEST_ASSERT(SSpersist.update_department_hours(FALSE), "an accrual pass with nothing to do yielded")

/// Mail accrues one step's worth per pass, every minute on the background lane.
/datum/unit_test/dq_system_mail

/datum/unit_test/dq_system_mail/Run()
	assert_system_ported(SSmail, /datum/system/mail)
	assert_work_declared(SSmail, nameof(/datum/system/mail/proc/accrue_mail), 60 SECONDS, LANE_BACKGROUND)
	var/saved = SSmail.mail_waiting
	SSmail.mail_waiting = 0
	TEST_ASSERT_EQUAL(SSmail.accrue_mail(0), STEP_DONE, "the mail step did not finish")
	TEST_ASSERT_EQUAL(SSmail.mail_waiting, SSmail.mail_per_process, "the mail step did not accrue mail")
	SSmail.mail_waiting = saved

/// A queued asset that records its build.
/datum/asset/dq_system_probe
	var/generated = 0

/datum/asset/dq_system_probe/New()
	return // not a registered asset: the test owns it

/datum/asset/dq_system_probe/queued_generation()
	generated++

/// Deferred asset generation: builds what is queued, parks when the queue is done, wakes when something is queued.
/datum/unit_test/dq_system_asset_loading

/datum/unit_test/dq_system_asset_loading/Run()
	assert_system_ported(SSasset_loading, /datum/system/asset_loading)
	var/datum/work_item/W = assert_work_declared(SSasset_loading, nameof(/datum/system/asset_loading/proc/generate_step), 2, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SSasset_loading.periodic_runlevels, RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT, "asset loading lost its lobby runlevel")
	var/list/saved_queue = SSasset_loading.generate_queue
	var/saved_len = SSasset_loading.last_queue_len
	// A world that is still building spritesheets in the background (rust-g jobs) holds `assets_generating` up, and the loader does not park until
	// they end: this test is about the queue, so it runs with none in flight.
	var/saved_generating = SSasset_loading.assets_generating
	SSasset_loading.generate_queue = list()
	SSasset_loading.last_queue_len = 0
	SSasset_loading.assets_generating = 0
	TEST_ASSERT_EQUAL(SSasset_loading.generate_step(0), STEP_PARK, "an idle asset loader must park")
	var/datum/asset/dq_system_probe/probe = new
	W.parked = TRUE
	SSasset_loading.queue_asset(probe)
	TEST_ASSERT(!W.parked, "queueing an asset did not wake the parked item")
	TEST_ASSERT_EQUAL(length(SSasset_loading.generate_queue), 1, "the asset was not queued")
	var/result = SSasset_loading.generate_step(0)
	for(var/i in 1 to 20) // a test tick is always over budget: the step yields once per asset
		if(result != STEP_YIELD)
			break
		result = SSasset_loading.generate_step(0)
	TEST_ASSERT_EQUAL(result, STEP_PARK, "a drained queue must park the item")
	TEST_ASSERT_EQUAL(probe.generated, 1, "the queued asset was not built")
	SSasset_loading.queue_asset(probe)
	SSasset_loading.dequeue_asset(probe)
	TEST_ASSERT_EQUAL(length(SSasset_loading.generate_queue), 0, "dequeue_asset() left the asset queued")
	SSasset_loading.generate_queue = saved_queue
	SSasset_loading.last_queue_len = saved_len
	SSasset_loading.assets_generating = saved_generating
	W.parked = FALSE
	qdel(probe)

/// A preferences stand-in that records its save.
/datum/dq_prefs_probe
	var/saves = 0

/datum/dq_prefs_probe/proc/client()
	return TRUE

/datum/dq_prefs_probe/proc/save_preferences()
	saves++

/// Preference saves: queued saves are written on the next pass, then the item parks.
/datum/unit_test/dq_system_character_setup

/datum/unit_test/dq_system_character_setup/Run()
	assert_system_ported(SScharacter_setup, /datum/system/character_setup)
	var/datum/work_item/W = assert_work_declared(SScharacter_setup, nameof(/datum/system/character_setup/proc/save_queued), 1 SECOND, LANE_BACKGROUND)
	TEST_ASSERT_EQUAL(SScharacter_setup.periodic_runlevels, RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT, "character setup lost its lobby runlevel")
	TEST_ASSERT_EQUAL(SScharacter_setup.save_queued(0), STEP_PARK, "an empty save queue must park the item")
	var/datum/dq_prefs_probe/probe = new
	W.parked = TRUE
	SScharacter_setup.queue_preferences_save(probe)
	TEST_ASSERT(!W.parked, "queueing a save did not wake the parked item")
	TEST_ASSERT(probe in SScharacter_setup.save_queue, "the save was not queued")
	var/result = SScharacter_setup.save_queued(0)
	for(var/i in 1 to 20) // a test tick is always over budget: the step yields once per save
		if(result != STEP_YIELD)
			break
		result = SScharacter_setup.save_queued(0)
	TEST_ASSERT_EQUAL(result, STEP_PARK, "a drained save queue must park the item")
	TEST_ASSERT_EQUAL(probe.saves, 1, "the queued save was not written")
	SScharacter_setup.queue_preferences_save(null)
	TEST_ASSERT_EQUAL(length(SScharacter_setup.save_queue), 0, "a null save was queued")
	W.parked = FALSE
	qdel(probe)

/// Chat delivery: every tick while payloads are queued, parked when idle, woken by a queued message, drops a client that left.
/datum/unit_test/dq_system_chat

/datum/unit_test/dq_system_chat/Run()
	assert_system_ported(SSchat, /datum/system/chat)
	var/datum/work_item/W = assert_work_declared(SSchat, nameof(/datum/system/chat/proc/send_queued), WORK_EVERY_TICK, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SSchat.periodic_runlevels, RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT, "chat lost its lobby runlevel")
	var/list/saved = SSchat.client_to_payloads
	SSchat.client_to_payloads = null
	TEST_ASSERT_EQUAL(SSchat.send_queued(0), STEP_PARK, "idle chat must park")
	SSchat.client_to_payloads = list("dq_gone_ckey" = list(new /datum/chat_payload))
	TEST_ASSERT_EQUAL(SSchat.send_queued(0), STEP_PARK, "a payload for a client that left is dropped and the item parks")
	TEST_ASSERT_EQUAL(length(SSchat.client_to_payloads), 0, "the departed client's payloads were kept")
	W.parked = TRUE
	SSchat.queue("dq_nobody", list("text" = "x"))
	TEST_ASSERT(!W.parked, "queueing a message did not wake the parked item")
	SSchat.client_to_payloads = saved
	W.parked = FALSE

/// The instrument tables: a lazy system, outside the boot DAG, built on the first ready().
/datum/unit_test/dq_system_instruments

/datum/unit_test/dq_system_instruments/Run()
	TEST_ASSERT(!SSinstruments.boots_in_dag(), "a lazy system must stay out of the boot DAG")
	TEST_ASSERT(!(SSinstruments in kernel_boot_systems()), "the lazy instrument system is a boot node")
	TEST_ASSERT_EQUAL(SSinstruments.ready(), SSinstruments, "ready() must return the system")
	assert_system_ported(SSinstruments, /datum/system/instruments)
	TEST_ASSERT(length(SSinstruments.instrument_data), "the instrument system has no instruments")
	TEST_ASSERT(length(SSinstruments.synthesizer_instrument_ids), "the instrument system has no synthesizer ids")
	var/id = SSinstruments.instrument_data[1]
	TEST_ASSERT_EQUAL(SSinstruments.get_instrument(id), SSinstruments.instrument_data[id], "get_instrument() did not return the table's instrument")
	var/channels = SSinstruments.current_instrument_channels
	var/datum/instrument/I = SSinstruments.instrument_data[id]
	var/reserved = SSinstruments.reserve_instrument_channel(I)
	if(!isnull(reserved))
		TEST_ASSERT_EQUAL(SSinstruments.current_instrument_channels, channels + 1, "a reserved channel was not counted")
		SSinstruments.current_instrument_channels = channels

/// The circuit tables: a lazy system, outside the boot DAG, built on the first ready().
/datum/unit_test/dq_system_circuit

/datum/unit_test/dq_system_circuit/Run()
	TEST_ASSERT(!SScircuit.boots_in_dag(), "a lazy system must stay out of the boot DAG")
	TEST_ASSERT(!(SScircuit in kernel_boot_systems()), "the lazy circuit system is a boot node")
	TEST_ASSERT_EQUAL(SScircuit.ready(), SScircuit, "ready() must return the system")
	assert_system_ported(SScircuit, /datum/system/circuit)
	TEST_ASSERT(length(SScircuit.all_components), "the circuit system has no components")
	TEST_ASSERT(length(SScircuit.all_assemblies), "the circuit system has no assemblies")
	TEST_ASSERT(length(SScircuit.circuit_fabricator_recipe_list["Assemblies"]), "the fabricator has no assembly recipes")
	var/initialized_at = SScircuit.initialized
	SScircuit.ready()
	TEST_ASSERT_EQUAL(SScircuit.initialized, initialized_at, "a second ready() initialized the system again")

/// The reagent and reaction tables: a lazy system, outside the boot DAG, built on the first ready().
/datum/unit_test/dq_system_chemistry

/datum/unit_test/dq_system_chemistry/Run()
	TEST_ASSERT(!SSchemistry.boots_in_dag(), "a lazy system must stay out of the boot DAG")
	TEST_ASSERT(!(SSchemistry in kernel_boot_systems()), "the lazy chemistry system is a boot node")
	TEST_ASSERT_EQUAL(SSchemistry.ready(), SSchemistry, "ready() must return the system")
	assert_system_ported(SSchemistry, /datum/system/chemistry)
	TEST_ASSERT(length(SSchemistry.chemical_reagents), "the chemistry system has no reagents")
	TEST_ASSERT(length(SSchemistry.chemical_reactions), "the chemistry system has no reactions")
	TEST_ASSERT(length(SSchemistry.instant_reactions_by_reagent), "no reaction is indexed by its first reagent")
	var/reagents = length(SSchemistry.chemical_reagents)
	SSchemistry.ready()
	TEST_ASSERT_EQUAL(length(SSchemistry.chemical_reagents), reagents, "a second ready() built the reagent table again")

/// Motion echoes: queued by listeners, drawn and cleared by one step; a hide-and-seek round swallows pings.
/datum/unit_test/dq_system_motiontracker

/datum/unit_test/dq_system_motiontracker/Run()
	assert_system_ported(SSmotiontracker, /datum/system/motiontracker)
	assert_work_declared(SSmotiontracker, nameof(/datum/system/motiontracker/proc/draw_echoes), 1 SECOND, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SSmotiontracker.periodic_runlevels, RUNLEVEL_GAME | RUNLEVEL_POSTGAME, "echoes draw outside the game")
	var/echoes = SSmotiontracker.all_echos_round
	// A stale client handle: the echo is queued and drawn for nobody (no client in a test run).
	SSmotiontracker.queue_echo(run_loc_floor_bottom_left, run_loc_floor_top_right, 1, "0:0")
	TEST_ASSERT_EQUAL(SSmotiontracker.all_echos_round, echoes + 1, "queue_echo() did not queue an echo")
	var/steps = 0
	while(SSmotiontracker.draw_echoes(0) != STEP_DONE && steps++ < 50)
		continue
	TEST_ASSERT(!SSmotiontracker.queued_echo_turfs[REF(run_loc_floor_top_right)], "the motion tracker step left the echo queued")
	var/pings = SSmotiontracker.all_pings_round
	var/hidden = SSmotiontracker.hide_all
	SSmotiontracker.hide_all = TRUE
	SSmotiontracker.ping(run_loc_floor_bottom_left, 100)
	TEST_ASSERT_EQUAL(SSmotiontracker.all_pings_round, pings, "a hide-and-seek round let a ping through")
	SSmotiontracker.hide_all = hidden

/// Night shift: boots after atoms, checks every minute, a manual shift does nothing on the timer.
/datum/unit_test/dq_system_nightshift

/datum/unit_test/dq_system_nightshift/Run()
	assert_system_ported(SSnightshift, /datum/system/nightshift)
	TEST_ASSERT(/datum/system/atoms in SSnightshift.needs, "the night shift boots after atoms")
	assert_work_declared(SSnightshift, nameof(/datum/system/nightshift/proc/nightshift_step), 60 SECONDS, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SSnightshift.periodic_runlevels, RUNLEVELS_DEFAULT, "the night shift runs in the lobby")
	var/automatic = SSnightshift.automatic
	SSnightshift.automatic = FALSE
	TEST_ASSERT_EQUAL(SSnightshift.nightshift_step(0), STEP_DONE, "a manual night shift must leave the timer alone")
	SSnightshift.automatic = automatic
	TEST_ASSERT_EQUAL(night_shift_active(), SSnightshift.nightshift_active, "the generated accessor reads the system's flag")

/// Explosions: an epoch steps every 0.5 s, parks when idle, and wakeup() wakes the parked item.
/datum/unit_test/dq_system_explosions

/datum/unit_test/dq_system_explosions/Run()
	assert_system_ported(SSexplosions, /datum/system/explosions)
	var/datum/work_item/W = assert_work_declared(SSexplosions, nameof(/datum/system/explosions/proc/explosion_step), 0.5 SECONDS, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SSexplosions.periodic_runlevels, RUNLEVEL_GAME | RUNLEVEL_POSTGAME, "explosions resolve outside the game")
	SSexplosions.awake = FALSE
	TEST_ASSERT_EQUAL(SSexplosions.explosion_step(0), STEP_PARK, "an idle epoch must park the item")
	W.parked = TRUE
	SSexplosions.wakeup()
	TEST_ASSERT(SSexplosions.awake, "wakeup() did not start the epoch")
	TEST_ASSERT(!W.parked, "wakeup() did not wake the parked item")
	TEST_ASSERT_EQUAL(SSexplosions.explosion_step(0), STEP_PARK, "an epoch with nothing queued ends, goes to sleep and parks the item")
	TEST_ASSERT(!SSexplosions.awake, "an epoch with nothing queued must go to sleep")
	W.parked = FALSE

/// The antagonist templates: boots after atoms, holds one template per antagonist type and the syndicate code phrases.
/datum/unit_test/dq_system_antag

/datum/unit_test/dq_system_antag/Run()
	assert_system_ported(SSantag, /datum/system/antag)
	TEST_ASSERT(/datum/system/atoms in SSantag.needs, "the antag system boots after atoms")
	TEST_ASSERT(length(SSantag.all_antag_types), "the antag system has no templates")
	TEST_ASSERT(length(SSantag.syndicate_code_phrase), "the syndicate code phrase was not generated")
	var/id = SSantag.all_antag_types[1]
	TEST_ASSERT_EQUAL(SSantag.get_antag_data(id), SSantag.all_antag_types[id], "get_antag_data() did not return the template")
	TEST_ASSERT(islist(SSantag.get_antags(id)), "get_antags() must always answer a list")
	TEST_ASSERT(!SSantag.player_is_antag(null), "no mind is an antagonist")

/// The event system: boots after atoms, three containers on the slow lane, finished events are owned.
/datum/unit_test/dq_system_events

/datum/unit_test/dq_system_events/Run()
	assert_system_ported(SSevents, /datum/system/events)
	TEST_ASSERT(/datum/system/atoms in SSevents.needs, "the event system boots after atoms")
	TEST_ASSERT(length(SSevents.allEvents), "the event system lists no event types")
	TEST_ASSERT_EQUAL(length(SSevents.event_containers), 3, "the event system lost a container")
	TEST_ASSERT(islist(SSevents.active_events()), "active_events() must answer a list")

/// The emergency shuttle: boots after the shuttles, counts down every second, parks when nothing is in flight, wakes on a countdown.
/datum/unit_test/dq_system_emergency_shuttle

/datum/unit_test/dq_system_emergency_shuttle/Run()
	assert_system_ported(SSemergency_shuttle, /datum/system/emergency_shuttle)
	TEST_ASSERT(/datum/system/shuttles in SSemergency_shuttle.needs, "the emergency shuttle boots after the shuttles")
	var/datum/work_item/W = assert_work_declared(SSemergency_shuttle, nameof(/datum/system/emergency_shuttle/proc/shuttle_step), 1 SECOND, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SSemergency_shuttle.periodic_runlevels, RUNLEVEL_GAME, "the launch countdown runs outside the game")
	var/waiting = SSemergency_shuttle.wait_for_launch
	SSemergency_shuttle.wait_for_launch = FALSE
	TEST_ASSERT_EQUAL(SSemergency_shuttle.shuttle_step(0), STEP_PARK, "an idle emergency shuttle must park the item")
	W.parked = TRUE
	SSemergency_shuttle.set_launch_countdown(60)
	TEST_ASSERT(!W.parked, "starting a countdown did not wake the parked item")
	SSemergency_shuttle.stop_launch_countdown()
	var/autopilot = SSemergency_shuttle.autopilot
	SSemergency_shuttle.set_autopilot(FALSE)
	TEST_ASSERT(!SSemergency_shuttle.autopilot, "set_autopilot() did not hold the shuttle")
	SSemergency_shuttle.set_autopilot(autopilot)
	SSemergency_shuttle.wait_for_launch = waiting
	W.parked = FALSE

/// The pAI candidate list: boots after atoms, refreshed every 4 s from the observers in one pass.
/datum/unit_test/dq_system_pai

/datum/unit_test/dq_system_pai/Run()
	assert_system_ported(SSpai, /datum/system/pai)
	TEST_ASSERT(/datum/system/atoms in SSpai.needs, "the pAI system boots after atoms")
	assert_work_declared(SSpai, nameof(/datum/system/pai/proc/refresh_candidates), 4 SECONDS, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SSpai.periodic_runlevels, RUNLEVELS_DEFAULT, "the pAI refresh runs in the lobby")
	TEST_ASSERT(length(SSpai.get_chassis_list()), "the pAI system has no chassis")
	TEST_ASSERT_EQUAL(SSpai.refresh_candidates(0), STEP_DONE, "the candidate refresh did not finish in one pass")

/// Mob deaths: reported every 2 s, the queue drains into one insert per pass.
/datum/unit_test/dq_system_mobs

/datum/unit_test/dq_system_mobs/Run()
	assert_system_ported(SSmobs, /datum/system/mobs)
	assert_work_declared(SSmobs, nameof(/datum/system/mobs/proc/report_step), 2 SECONDS, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SSmobs.periodic_runlevels, RUNLEVEL_GAME | RUNLEVEL_POSTGAME, "mob reports run outside the game")
	var/list/saved = SSmobs.death_list
	SSmobs.death_list = list(list("name" = "dq test"))
	TEST_ASSERT_EQUAL(SSmobs.report_step(0), STEP_DONE, "the mob step did not finish")
	TEST_ASSERT_EQUAL(length(SSmobs.death_list), 0, "the mob step did not drain the death queue")
	SSmobs.death_list = saved

/// Machines: booted by hand from SSair (outside the DAG), steps every MACHINE_SERVICE_INTERVAL, finishes an unbudgeted step.
/datum/unit_test/dq_system_machines

/datum/unit_test/dq_system_machines/Run()
	assert_system_ported(SSmachines, /datum/system/machines)
	TEST_ASSERT(!SSmachines.boots_in_dag(), "SSair boots the machine system by hand")
	assert_work_declared(SSmachines, nameof(/datum/system/machines/proc/machine_step), MACHINE_SERVICE_INTERVAL, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(MACHINE_SERVICE_INTERVAL, 2 SECONDS, "machine timing changed")
	TEST_ASSERT(SSmachines.members_ready, "the boot pass ran on_members_ready() for the machine system")

/// Expedition: boots after mapping, polls sites every 2 s and parks while none is live.
/datum/unit_test/dq_system_expedition

/datum/unit_test/dq_system_expedition/Run()
	assert_system_ported(SSexpedition, /datum/system/expedition)
	TEST_ASSERT(/datum/system/mapping in SSexpedition.needs, "expeditions boot after mapping")
	var/datum/work_item/W = assert_work_declared(SSexpedition, nameof(/datum/system/expedition/proc/poll_sites), 2 SECONDS, LANE_SIMULATION)
	var/list/saved = SSexpedition.sites
	SSexpedition.sites = list()
	TEST_ASSERT_EQUAL(SSexpedition.poll_sites(0), STEP_PARK, "with no live site the poll must park")
	W.parked = TRUE
	SSexpedition.demand()
	TEST_ASSERT(!W.parked, "demand() did not wake the parked poll")
	SSexpedition.sites = saved
	W.parked = FALSE

/// Flight operations: boots after shuttles and expeditions, processes plans every second.
/datum/unit_test/dq_system_flight

/datum/unit_test/dq_system_flight/Run()
	assert_system_ported(SSflight, /datum/system/flight)
	TEST_ASSERT(/datum/system/shuttles in SSflight.needs, "flight boots after the shuttles")
	TEST_ASSERT(/datum/system/expedition in SSflight.needs, "flight boots after expeditions")
	assert_work_declared(SSflight, nameof(/datum/system/flight/proc/plan_step), 1 SECOND, LANE_SIMULATION)
	TEST_ASSERT_EQUAL(SSflight.periodic_runlevels, RUNLEVEL_GAME | RUNLEVEL_POSTGAME, "flight plans run outside the game")
	TEST_ASSERT(islist(SSflight.plans), "the plan table exists")

#endif
