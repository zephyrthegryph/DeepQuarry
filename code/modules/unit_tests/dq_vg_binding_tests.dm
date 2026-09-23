// R10 binding layer tests (doc/rewrite/rust_bindings.md §12), pump as the
// reference component (§14).

/datum/unit_test/dq_vg_pump_read_your_writes

/datum/unit_test/dq_vg_pump_read_your_writes/Run()
	var/turf/T = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	TEST_ASSERT_NOTNULL(T, "no floor for the vg pump test")
	var/obj/machinery/atmospherics/binary/pump/P = new(T)
	TEST_ASSERT(P.vg_entity, "pump did not get a vg_entity from on_materialize()")

	// A set is visible to the very next read (§5/§6: the overlay is this
	// tick's writes over the pinned frame).
	var/stored = P.set_target_pressure(4200)
	TEST_ASSERT_EQUAL(stored, 4200, "set_target_pressure did not return the stored value")
	TEST_ASSERT_EQUAL(P.get_target_pressure(), 4200, "read right after write did not see the write")

	// clamp (on_invalid = clamp, VG_PUMP_TARGET_PRESSURE_MAX 15000): the
	// setter returns what was actually stored, not what was asked for.
	var/clamped = P.set_target_pressure(999999)
	TEST_ASSERT_EQUAL(clamped, VG_PUMP_TARGET_PRESSURE_MAX, "an out-of-range value was not clamped")
	TEST_ASSERT_EQUAL(P.get_target_pressure(), VG_PUMP_TARGET_PRESSURE_MAX, "the clamped value did not stick")

	P.set_on(TRUE)
	TEST_ASSERT_EQUAL(P.get_on(), 1, "set_on(TRUE)/get_on() did not round-trip")
	P.set_on(FALSE)
	TEST_ASSERT_EQUAL(P.get_on(), 0, "set_on(FALSE)/get_on() did not round-trip")

	qdel(P)

/datum/unit_test/dq_vg_pump_binds_at_materialize_unbinds_at_dematerialize

/datum/unit_test/dq_vg_pump_binds_at_materialize_unbinds_at_dematerialize/Run()
	var/turf/T = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	TEST_ASSERT_NOTNULL(T, "no floor for the vg pump lifecycle test")
	var/before = vg_entity_count()

	var/obj/machinery/atmospherics/binary/pump/P = new(T)
	TEST_ASSERT(P.vg_entity, "pump was not bound by on_materialize()")
	TEST_ASSERT(P in SSvg.bound, "pump did not register with SSvg on materialize")
	TEST_ASSERT_EQUAL(vg_entity_count(), before + 1, "bind did not add exactly one Rust entity")

	var/entity = P.vg_entity
	TEST_ASSERT(vg_entity_is_valid(entity, VG_DOMAIN_GAS, VG_GAS_PUMP), "a freshly bound pump's handle was not valid")
	qdel(P)
	TEST_ASSERT_EQUAL(P.vg_entity, 0, "vg_entity was not cleared on dematerialize")
	TEST_ASSERT_EQUAL(vg_entity_count(), before, "unbind did not remove the Rust entity")
	TEST_ASSERT(!(P in SSvg.bound), "SSvg kept a deleted pump registered")

	// The handle is stale now (§9): resolving it must never silently
	// succeed or alias whatever slot got reused next. entity_is_valid() is
	// the safe probe for this (get_*()/etc runtime instead, by design; this
	// codebase's test harness fails a "clean" run on any runtime at all).
	TEST_ASSERT(!vg_entity_is_valid(entity, VG_DOMAIN_GAS, VG_GAS_PUMP), "a stale/unbound entity handle read as valid")

/datum/unit_test/dq_vg_pump_wrong_component_handle_errors

/datum/unit_test/dq_vg_pump_wrong_component_handle_errors/Run()
	var/turf/T = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	TEST_ASSERT_NOTNULL(T, "no floor for the vg wrong-handle test")
	var/obj/machinery/atmospherics/binary/pump/P = new(T)
	TEST_ASSERT(P.vg_entity, "pump did not bind")

	// A handle that is not a live pump component (0/unbound, or a stray
	// number) must never resolve — entity_is_valid() is the safe check
	// (the real accessors runtime instead, by design, §5/§9).
	TEST_ASSERT(!vg_entity_is_valid(0, VG_DOMAIN_GAS, VG_GAS_PUMP), "the unbound sentinel (0) read as a valid pump handle")
	TEST_ASSERT(!vg_entity_is_valid(P.vg_entity, VG_DOMAIN_GAS, VG_GAS_PUMP + 1), "a live pump handle read as valid for a kind it isn't")

	qdel(P)

/datum/unit_test/dq_vg_reconciler_catches_injected_desync

/datum/unit_test/dq_vg_reconciler_catches_injected_desync/Run()
	var/turf/T = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	TEST_ASSERT_NOTNULL(T, "no floor for the vg reconciler test")
	var/obj/machinery/atmospherics/binary/pump/P = new(T)
	P.anchored = TRUE
	P.stat &= ~BROKEN
	// Bring Rust's operable up to date with the honest input before
	// desyncing it, so the mismatch below is caused by the bypass alone.
	P.pump_reconcile()
	TEST_ASSERT_EQUAL(P.pump_input_operable(), P.get_operable(), "operable was not in sync before the injected desync")

	// Bypass every setter (rust_bindings.md §12's injected-desync test):
	// flip the DM-owned source directly through vars[], which is exactly
	// the class-5 path the reconciler exists to catch. No push happens.
	P.vars["anchored"] = FALSE
	TEST_ASSERT_NOTEQUAL(P.pump_input_operable(), P.get_operable(), "vars[] bypass did not actually desync operable")

	var/list/findings = vg_reconcile_all()
	var/found = FALSE
	for(var/line in findings)
		if(findtext(line, "operable", 1, 0))
			found = TRUE
	TEST_ASSERT(found, "the reconciler did not report the injected operable desync")

	// And it must have repaired it, not just logged it (§7).
	TEST_ASSERT_EQUAL(P.pump_input_operable(), P.get_operable(), "the reconciler reported but did not repair the desync")

	qdel(P)

/datum/unit_test/dq_vg_pump_high_power_seeds_differ

/datum/unit_test/dq_vg_pump_high_power_seeds_differ/Run()
	var/turf/T = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	TEST_ASSERT_NOTNULL(T, "no floor for the vg high_power seed test")
	var/obj/machinery/atmospherics/binary/pump/P = new(T)
	var/obj/machinery/atmospherics/binary/pump/high_power/H = new(T)
	TEST_ASSERT_EQUAL(P.get_power_rating(), initial(P.init_power_rating), "base pump did not seed from its init_power_rating")
	TEST_ASSERT_EQUAL(H.get_power_rating(), 15000, "high_power pump did not seed its own init_power_rating")
	TEST_ASSERT_NOTEQUAL(P.get_power_rating(), H.get_power_rating(), "high_power's seed did not differ from the base pump's")
	qdel(P)
	qdel(H)
