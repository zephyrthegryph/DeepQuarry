// Boot binds and shared appearance caches (doc/rewrite/init_and_turfs.md sec 3.5, 4.4, 4.6).

/// A reserved heat body is usable at once, is configured before it is read, keeps writes made
/// while pending, and leaves the queue when it is released.
/datum/unit_test/dq_boot_bind_heat_reserve

/datum/unit_test/dq_boot_bind_heat_reserve/Run()
	var/turf/T = test_floor()
	var/obj/item/stack/rods/plain = allocate(/obj/item/stack/rods, T)
	var/obj/item/stack/rods/written = allocate(/obj/item/stack/rods, T)
	var/obj/item/stack/rods/released = allocate(/obj/item/stack/rods, T)
	var/ambient = plain.get_ambient_temperature()
	dq_heat_bind_begin()
	TEST_ASSERT(plain.create_heat_body(TRUE), "a body is created inside a bind scope")
	TEST_ASSERT(!isnull(plain.heat_body), "with a handle at once")
	TEST_ASSERT(GLOB.dq_heat_bind_pending[plain], "its configuration is queued")
	TEST_ASSERT(vg_heat_body_keep(plain.heat_body, TRUE), "the reserved handle takes writes at once")
	TEST_ASSERT(written.create_heat_body(TRUE), "a second reserved body")
	TEST_ASSERT_NOTEQUAL(written.heat_body, plain.heat_body, "reserved handles are distinct")
	vg_heat_body_couple(written.heat_body, 0, HEAT_TARGET_NONE, 0, 0)
	vg_heat_body_set_temperature(written.heat_body, 350)
	TEST_ASSERT(released.create_heat_body(TRUE), "a third reserved body")
	released.release_heat_body()
	TEST_ASSERT(!GLOB.dq_heat_bind_pending[released], "a body released while pending leaves the queue")
	// A read configures just that body first.
	var/read = plain.get_temperature()
	TEST_ASSERT(abs(read - ambient) < 1, "a read of a pending body sees its configured temperature ([read] vs [ambient]), not the placeholder")
	TEST_ASSERT(!GLOB.dq_heat_bind_pending[plain], "and it is no longer pending")
	TEST_ASSERT(GLOB.dq_heat_bind_pending[written], "the others still are")
	dq_heat_bind_end()
	TEST_ASSERT(!length(GLOB.dq_heat_bind_pending), "the scope's end configures everything queued")
	TEST_ASSERT(!length(GLOB.dq_heat_body_pool), "and returns the unused handles")
	TEST_ASSERT(abs(written.get_temperature() - 350) < 0.5, "a temperature set while pending survives the configure ([written.get_temperature()])")
	TEST_ASSERT(!isnull(vg_heat_body_temperature(plain.heat_body)), "the configured handle stays live")

/// Outside a bind scope create_heat_body() binds at once, as before.
/datum/unit_test/dq_boot_bind_heat_direct

/datum/unit_test/dq_boot_bind_heat_direct/Run()
	TEST_ASSERT_EQUAL(GLOB.dq_heat_bind_depth, 0, "no scope is left open between tests")
	var/obj/item/stack/rods/R = allocate(/obj/item/stack/rods, test_floor())
	TEST_ASSERT(R.create_heat_body(TRUE), "a body")
	TEST_ASSERT(!GLOB.dq_heat_bind_pending[R], "is not queued outside a scope")
	TEST_ASSERT(!isnull(vg_heat_body_temperature(R.heat_body)), "and is live at once")

/// Power machines queued by a map-load batch bind in one call and end as a direct bind would.
/datum/unit_test/dq_boot_bind_power_machines

/datum/unit_test/dq_boot_bind_power_machines/Run()
	var/obj/machinery/power/terminal/term = allocate(/obj/machinery/power/terminal, test_floor())
	TEST_ASSERT(term.vg_entity, "the terminal has an entity")
	term.disconnect_from_network()
	var/list/saved = SSatoms.deferred_machine_binds
	SSatoms.deferred_machine_binds = list()
	term.set_anchored(TRUE)
	term.connect_to_network(FALSE)
	TEST_ASSERT(SSatoms.deferred_machine_binds[term], "inside a batch the node is queued")
	term.disconnect_from_network()
	TEST_ASSERT(!SSatoms.deferred_machine_binds[term], "disconnecting drops it from the queue")
	term.connect_to_network(FALSE)
	var/list/queued = SSatoms.deferred_machine_binds
	SSatoms.deferred_machine_binds = saved
	TEST_ASSERT_EQUAL(power_bind_machines(queued), 1, "the batch binds the queued machine in one call")
	term.power_bind_now()
	TEST_ASSERT(vg_power_region_of(term.vg_entity), "the node is placed in Rust")

/// Floors, windows and materials share their per-state caches.
/datum/unit_test/dq_boot_bind_appearance_caches

/datum/unit_test/dq_boot_bind_appearance_caches/Run()
	var/datum/decl/flooring/tiling/tiles = GET_DECL(/datum/decl/flooring/tiling)
	var/list/edges = tiles.get_edge_overlays(NORTH | EAST, 1 << 3)
	TEST_ASSERT(edges == tiles.get_edge_overlays(NORTH | EAST, 1 << 3), "one edge overlay list per flooring state")
	TEST_ASSERT_EQUAL(length(edges), 4, "two edges, the NE outer corner and the SW inner corner")
	TEST_ASSERT(edges != tiles.get_edge_overlays(NORTH, 0), "different states get different lists")

	var/obj/structure/window/reinforced/full/A = allocate(/obj/structure/window/reinforced/full, test_floor())
	var/list/connections = list("0", "0", "0", "0")
	TEST_ASSERT(A.window_overlay_images(connections) == A.window_overlay_images(list("0", "0", "0", "0")), "one window overlay list per window state")

	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	var/expected = clamp(2.718281828 ** (-(max(0, steel.radiation_resistance + steel.density / 8) * 60 / 100)), 0, 1)
	TEST_ASSERT(abs(steel.radiation_transmission(60) - expected) < 0.000001, "the cached transmission is the formula's")
	var/datum/shared_cache/rad = SHARED_CACHE(material_radiation_transmission)
	TEST_ASSERT(rad.entry_count() > 0, "and is cached per thickness")
	steel.material_facts_changed()
	TEST_ASSERT_EQUAL(rad.entry_count(), 0, "material_facts_changed() drops the cache")

/// A batched destroy disarms its material services' gas watches as one set.
/datum/unit_test/dq_boot_bind_material_service_batch

/datum/unit_test/dq_boot_bind_material_service_batch/Run()
	var/obj/machinery/portable_atmospherics/canister/air/C = allocate(/obj/machinery/portable_atmospherics/canister/air, test_floor())
	var/datum/material_service/service = C.enable_material_service()
	TEST_ASSERT(service, "the canister has a material service")
	service.rebind()
	TEST_ASSERT(length(service.gas_watches), "which watches its gas")
	var/list/watches = service.gas_watches.Copy()
	qdel_batch(list(C))
	TEST_ASSERT(QDELETED(service), "the batch destroys the service with its owner")
	for(var/datum/native_watch/gas/W as anything in watches)
		TEST_ASSERT(QDELETED(W) || !W.handle, "and its gas watches are cancelled with it")
