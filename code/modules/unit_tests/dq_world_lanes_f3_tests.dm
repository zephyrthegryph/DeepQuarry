// Fold wave F3 (doc/rewrite/completion_plan.md §3.6): SSchemistry, SSradiation, SSinstruments,
// SSthrowing, SSsounds, SSmotiontracker, SSreflector, SSpai, SScircuit, SSxenoarch, SSlooting,
// SSmail and SSevents are gone. World-level work runs as lanes on the OM global owner, per-object
// work as periodic behaviours on the objects, data-only services initialize lazily, and the
// global object lists are registries. These tests pin each of those down.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// None of the folded subsystems is still registered with the MC.
/datum/unit_test/dq_world_lanes_f3_no_subsystems

/datum/unit_test/dq_world_lanes_f3_no_subsystems/Run()
	var/list/gone = list("chemistry", "radiation", "instruments", "throwing", "sounds", "motiontracker", "reflector", "pai", "circuit", "xenoarch", "looting", "mail", "events")
	for(var/datum/controller/subsystem/S as anything in Master.subsystems)
		var/path = "[S.type]"
		for(var/name in gone)
			TEST_ASSERT(path != "/datum/controller/subsystem/[name]", "[path] still runs as a subsystem after the F3 fold")

/// The four world lanes are on the global owner at the old subsystems' cadence.
/datum/unit_test/dq_world_lanes_f3_attached

/datum/unit_test/dq_world_lanes_f3_attached/Run()
	var/datum/om/global_owner/owner = om_global_owner()
	var/list/cadence = list(
		/datum/om/behaviour/world/radiation = 0.5 SECONDS,
		/datum/om/behaviour/world/motiontracker = 1 SECOND,
		/datum/om/behaviour/world/pai = 4 SECONDS,
		/datum/om/behaviour/world/mail = 60 SECONDS,
	)
	for(var/lane in cadence)
		TEST_ASSERT(om_attached(owner, lane), "[lane] is not on the global owner")
		var/datum/om/behaviour/world/B = om_registry().behaviour(lane)
		TEST_ASSERT_EQUAL(B.every, cadence[lane], "[lane] lost its subsystem's cadence")
		TEST_ASSERT_NOTNULL(B.service(), "[lane] has no service")
		TEST_ASSERT_EQUAL(B.service().lane, lane, "[lane]'s service names a different lane")

/// Every data-only service initializes on first use and builds its tables.
/datum/unit_test/dq_world_lanes_f3_lazy_services

/datum/unit_test/dq_world_lanes_f3_lazy_services/Run()
	TEST_ASSERT(length(chemistry_service().chemical_reagents), "the chemistry service has no reagents")
	TEST_ASSERT(length(chemistry_service().chemical_reactions), "the chemistry service has no reactions")
	TEST_ASSERT(GLOB.chemistry_service.initialized, "chemistry_service() did not mark the service initialized")
	TEST_ASSERT(length(sound_service().talk_sound_map), "the sound service has no talk sounds")
	TEST_ASSERT(sound_service().random_available_channel(), "the sound service handed out no channel")
	TEST_ASSERT(length(circuit_service().all_components), "the circuit service has no components")
	TEST_ASSERT(length(instrument_service().instrument_data), "the instrument service has no instruments")
	TEST_ASSERT(length(instrument_service().synthesizer_instrument_ids), "the instrument service has no synthesizer ids")

	// A fresh lazy service initializes exactly once, on the first ready().
	var/datum/world_service/sounds/S = new
	TEST_ASSERT(!S.initialized, "a new sound service is already initialized")
	S.ready()
	TEST_ASSERT(S.initialized, "ready() did not initialize the service")
	var/list/channels = S.channel_list
	S.ready()
	TEST_ASSERT(S.channel_list == channels, "a second ready() initialized the service again")
	qdel(S)

/// The services SSatoms sets up once the map is loaded are initialized.
/datum/unit_test/dq_world_lanes_f3_boot_services

/datum/unit_test/dq_world_lanes_f3_boot_services/Run()
	TEST_ASSERT(GLOB.pai_service.initialized, "the pAI service never initialized (SSatoms)")
	TEST_ASSERT(length(GLOB.pai_service.get_chassis_list()), "the pAI service has no chassis")
	TEST_ASSERT(length(GLOB.pai_software_by_key), "the pAI service registered no software")
	TEST_ASSERT(GLOB.xenoarch_service.initialized, "the xenoarch service never initialized (SSatoms)")
	TEST_ASSERT(GLOB.event_service.initialized, "the event service never initialized (SSatoms)")
	for(var/i = EVENT_LEVEL_MUNDANE to EVENT_LEVEL_MAJOR)
		var/datum/event_container/EC = GLOB.event_service.event_containers[i]
		TEST_ASSERT(EC.periodic_pipe == PERIODIC_SLOW, "event container [i] is not on the slow lane")

/// Mail accrues one step's worth per lane step.
/datum/unit_test/dq_world_lanes_f3_mail

/datum/unit_test/dq_world_lanes_f3_mail/Run()
	var/datum/world_service/mail/S = GLOB.mail_service
	var/saved = S.mail_waiting
	S.mail_waiting = 0
	TEST_ASSERT(S.run_step(), "the mail step yielded")
	TEST_ASSERT_EQUAL(S.mail_waiting, S.mail_per_process, "the mail step did not accrue mail")
	S.mail_waiting = saved

/// The radiation lane drains its queue, and a disabled service queues nothing.
/datum/unit_test/dq_world_lanes_f3_radiation

/datum/unit_test/dq_world_lanes_f3_radiation/Run()
	var/datum/world_service/radiation/S = GLOB.radiation_service
	var/obj/item/source = allocate(/obj/item/stack/rods, run_loc_floor_bottom_left)
	S.enabled = FALSE
	TEST_ASSERT(!radiation_pulse(source, 3, 0.1), "a disabled radiation service queued a pulse")
	S.enabled = TRUE
	var/queued = length(S.processing)
	TEST_ASSERT(radiation_pulse(source, 3, 0.1), "radiation_pulse() refused a pulse")
	TEST_ASSERT_EQUAL(length(S.processing), queued + 1, "the pulse was not queued on the service")
	var/steps = 0
	while(length(S.processing) && steps++ < 200)
		S.run_step()
	TEST_ASSERT(!length(S.processing), "the radiation step never drained its queue")
	TEST_ASSERT(!S.resuming, "a drained radiation step is still resuming")

/// Queued motion echoes are drawn and cleared by one step.
/datum/unit_test/dq_world_lanes_f3_motiontracker

/datum/unit_test/dq_world_lanes_f3_motiontracker/Run()
	var/datum/world_service/motiontracker/S = GLOB.motiontracker_service
	var/echoes = S.all_echos_round
	// A stale client handle: the echo is queued and drawn for nobody (no client in a test run).
	S.queue_echo(run_loc_floor_bottom_left, run_loc_floor_top_right, 1, "0:0")
	TEST_ASSERT_EQUAL(S.all_echos_round, echoes + 1, "queue_echo() did not queue an echo")
	var/steps = 0
	while(!S.run_step() && steps++ < 50)
		continue
	TEST_ASSERT(!S.queued_echo_turfs[REF(run_loc_floor_top_right)], "the motion tracker step left the echo queued")

/// A throw runs on the continuous throwing lane and parks when it lands.
/datum/unit_test/dq_world_lanes_f3_throwing

/datum/unit_test/dq_world_lanes_f3_throwing/Run()
	var/obj/item/stack/rods/R = allocate(/obj/item/stack/rods, run_loc_floor_bottom_left)
	var/turf/target = locate(run_loc_floor_bottom_left.x + 2, run_loc_floor_bottom_left.y, run_loc_floor_bottom_left.z)
	R.throw_at(target, 2, 1)
	var/datum/thrownthing/TT = R.throwing
	TEST_ASSERT_NOTNULL(TT, "throw_at() made no thrownthing")
	TEST_ASSERT(TT.periodic_pipe == PERIODIC_THROWING, "a throw is not on the throwing lane")
	var/steps = 0
	while(!QDELETED(TT) && steps++ < 100)
		// world.time is frozen inside a test; a throw's pace is measured from its start_time,
		// so age the throw by one server tick per step as the lane would.
		TT.start_time -= world.tick_lag
		if(TT.periodic_step(1) == PROCESS_KILL)
			break
	TEST_ASSERT(QDELETED(TT), "the throw never landed")
	TEST_ASSERT_NULL(R.throwing, "the landed item still points at its throw")
	TEST_ASSERT_NULL(TT.periodic_pipe, "a landed throw kept its lane")

/// A reflector starts its clocked lane when it catches a beam and parks once it has re-fired.
/datum/unit_test/dq_world_lanes_f3_reflector

/datum/unit_test/dq_world_lanes_f3_reflector/Run()
	var/datum/om/pipeline/periodic/reflectors/P = om_registry().behaviour(PERIODIC_REFLECTORS)
	TEST_ASSERT_EQUAL(P.clock, CLOCK_MACHINE, "the reflector lane is not on the machine clock")
	TEST_ASSERT_EQUAL(P.every, 0.5 SECONDS, "the reflector lane lost SSreflector's cadence")
	var/obj/structure/reflector/box/B = allocate(/obj/structure/reflector/box, run_loc_floor_bottom_left)
	TEST_ASSERT_NULL(B.periodic_pipe, "an idle reflector is running")
	var/obj/item/projectile/beam/beam = allocate(/obj/item/projectile/beam, run_loc_floor_bottom_left)
	B.redirect_projectile(beam, 0)
	TEST_ASSERT(B.periodic_pipe == PERIODIC_REFLECTORS, "catching a beam did not start the reflector lane")
	TEST_ASSERT_EQUAL(B.periodic_step(5), PROCESS_KILL, "a reflector that fired did not park")
	TEST_ASSERT(!LAZYLEN(B.has_projectiles), "the reflector kept the beams it fired")

/// The loot icon lane runs in the lobby too, like SSlooting did.
/datum/unit_test/dq_world_lanes_f3_loot_lane

/datum/unit_test/dq_world_lanes_f3_loot_lane/Run()
	var/datum/om/pipeline/periodic/loot_icons/P = om_registry().behaviour(PERIODIC_LOOT_ICONS)
	TEST_ASSERT(P.runlevels & RUNLEVEL_LOBBY, "the loot icon lane does not run in the lobby")
	TEST_ASSERT_EQUAL(P.every, 0.5 SECONDS, "the loot icon lane lost SSlooting's cadence")

/// Songs are REGISTRY_SONGS and running events are REGISTRY_ACTIVE_EVENTS.
/datum/unit_test/dq_world_lanes_f3_registries

/datum/unit_test/dq_world_lanes_f3_registries/Run()
	var/obj/item/stack/rods/holder = allocate(/obj/item/stack/rods, run_loc_floor_bottom_left)
	var/datum/song/S = new(holder, null)
	TEST_ASSERT(S in REGISTRY_MEMBERS(REGISTRY_SONGS), "a new song is not in the song registry")
	qdel(S)
	TEST_ASSERT(!(S in REGISTRY_MEMBERS(REGISTRY_SONGS)), "a deleted song stayed in the song registry")

	var/datum/event_meta/EM = new(EVENT_LEVEL_MUNDANE, "Registry test", /datum/event/nothing, 0, add_to_queue = FALSE)
	var/datum/event/E = new /datum/event/nothing(EM)
	TEST_ASSERT(E in GLOB.event_service.active_events(), "a new event is not active")
	E.kill()
	TEST_ASSERT(!(E in GLOB.event_service.active_events()), "a killed event is still active")
	own_remove(GLOB.event_service, nameof(/datum/world_service/events::finished_events), E) // the service owns finished events

#endif
