// Fold wave F3 (doc/rewrite/completion_plan.md §3.6): SSchemistry, SSradiation, SSinstruments,
// SSthrowing, SSsounds, SSmotiontracker, SSreflector, SSpai, SScircuit, SSxenoarch, SSlooting,
// SSmail and SSevents are gone. World-level work runs as lanes on the OM global owner, per-object
// work as periodic behaviours on the objects, data-only services initialize lazily, and the
// global object lists are registries. These tests pin each of those down.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Every data-only service initializes on first use and builds its tables.
/datum/unit_test/dq_world_lanes_f3_lazy_services

/datum/unit_test/dq_world_lanes_f3_lazy_services/Run()
	TEST_ASSERT(length(SSchemistry.ready().chemical_reagents), "the chemistry service has no reagents")
	TEST_ASSERT(length(SSchemistry.ready().chemical_reactions), "the chemistry service has no reactions")
	TEST_ASSERT(SSchemistry.initialized, "SSchemistry.ready() did not mark the service initialized")
	TEST_ASSERT(length(SSsounds.ready().talk_sound_map), "the sound service has no talk sounds")
	TEST_ASSERT(SSsounds.ready().random_available_channel(), "the sound service handed out no channel")
	TEST_ASSERT(length(SScircuit.ready().all_components), "the circuit service has no components")
	TEST_ASSERT(length(SSinstruments.ready().instrument_data), "the instrument service has no instruments")
	TEST_ASSERT(length(SSinstruments.ready().synthesizer_instrument_ids), "the instrument service has no synthesizer ids")

	// A lazy system initializes exactly once: a second ready() leaves its tables alone.
	var/list/channels = SSsounds.ready().channel_list
	SSsounds.ready()
	TEST_ASSERT(SSsounds.channel_list == channels, "a second ready() initialized the system again")

/// The services SSatoms sets up once the map is loaded are initialized.
/datum/unit_test/dq_world_lanes_f3_boot_services

/datum/unit_test/dq_world_lanes_f3_boot_services/Run()
	TEST_ASSERT(SSpai.initialized, "the pAI service never initialized (SSatoms)")
	TEST_ASSERT(length(SSpai.get_chassis_list()), "the pAI service has no chassis")
	TEST_ASSERT(length(GLOB.pai_software_by_key), "the pAI service registered no software")
	TEST_ASSERT(SSxenoarch.initialized, "the xenoarch service never initialized (SSatoms)")
	TEST_ASSERT(SSevents.initialized, "the event service never initialized (SSatoms)")
	for(var/i = EVENT_LEVEL_MUNDANE to EVENT_LEVEL_MAJOR)
		var/datum/event_container/EC = SSevents.event_containers[i]
		TEST_ASSERT(EC.clock_running, "event container [i] is not keeping its clock")

/// The radiation lane drains its queue, and a disabled service queues nothing.
/datum/unit_test/dq_world_lanes_f3_radiation

/datum/unit_test/dq_world_lanes_f3_radiation/Run()
	var/datum/system/radiation/S = SSradiation
	var/obj/item/source = allocate(/obj/item/stack/rods, run_loc_floor_bottom_left)
	S.enabled = FALSE
	TEST_ASSERT(!radiation_pulse(source, 3, 0.1), "a disabled radiation service queued a pulse")
	S.enabled = TRUE
	var/queued = length(S.processing)
	TEST_ASSERT(radiation_pulse(source, 3, 0.1), "radiation_pulse() refused a pulse")
	TEST_ASSERT_EQUAL(length(S.processing), queued + 1, "the pulse was not queued on the service")
	var/steps = 0
	var/result = STEP_YIELD
	while(length(S.processing) && steps++ < 200)
		result = S.radiation_step(0)
	TEST_ASSERT(!length(S.processing), "the radiation step never drained its queue")
	TEST_ASSERT_EQUAL(result, STEP_DONE, "a drained radiation step is still yielding")

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

/// A reflector arms its every() when it catches a beam and parks once it has re-fired.
/datum/unit_test/dq_world_lanes_f3_reflector

/datum/unit_test/dq_world_lanes_f3_reflector/Run()
	var/obj/structure/reflector/box/B = allocate(/obj/structure/reflector/box, run_loc_floor_bottom_left)
	TEST_ASSERT(!B.refiring, "an idle reflector is running")
	var/obj/item/projectile/beam/beam = allocate(/obj/item/projectile/beam, run_loc_floor_bottom_left)
	B.redirect_projectile(beam, 0)
	TEST_ASSERT(B.refiring, "catching a beam did not arm the reflector every()")
	B.reflector_step(null)
	TEST_ASSERT(!B.refiring, "a reflector that fired did not park")
	TEST_ASSERT(!LAZYLEN(B.has_projectiles), "the reflector kept the beams it fired")

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
	TEST_ASSERT(E in SSevents.active_events(), "a new event is not active")
	E.kill()
	TEST_ASSERT(!(E in SSevents.active_events()), "a killed event is still active")
	own_remove(SSevents, nameof(/datum/system/events::finished_events), E) // the service owns finished events

#endif
