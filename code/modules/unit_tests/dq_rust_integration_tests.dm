/// Rust integration lane: bulk gas solve, no DM copies of Rust state, one change adapter,
/// error naming, and the always-on FFI call counter.

/// vg_transfer_to_pressure moves exactly the moles that bring the sink to the target.
/datum/unit_test/dq_rust_transfer_to_pressure_lands_on_target

/datum/unit_test/dq_rust_transfer_to_pressure_lands_on_target/Run()
	var/datum/gas_mixture/source = new(1000)
	source.adjust_gas(/datum/gas/oxygen, 80)
	source.adjust_gas(/datum/gas/nitrogen, 20)
	heat_set(source, 350, HEAT_SOURCE_OTHER)
	var/datum/gas_mixture/sink = new(200)
	sink.adjust_gas(/datum/gas/oxygen, 10)
	heat_set(sink, T20C, HEAT_SOURCE_OTHER)
	var/before_total = source.total_moles() + sink.total_moles()
	var/moved = source.transfer_to_pressure(sink, 300)
	TEST_ASSERT(moved > 0, "nothing moved toward a higher target pressure")
	TEST_ASSERT(abs(sink.return_pressure() - 300) < 1, "sink ended at [sink.return_pressure()] kPa, wanted 300")
	TEST_ASSERT(abs(source.total_moles() + sink.total_moles() - before_total) < 0.01, "the transfer did not conserve moles")
	TEST_ASSERT_EQUAL(source.transfer_to_pressure(sink, 300), 0, "a sink already at target still received gas")
	// The cap and the gas mask are honoured.
	var/datum/gas_mixture/other_sink = new(200)
	heat_set(other_sink, T20C, HEAT_SOURCE_OTHER)
	var/nitrogen_before = source.get_moles(/datum/gas/nitrogen)
	var/capped = source.transfer_to_pressure(other_sink, 1000, 2, (1 << GAS_ID_OXYGEN))
	TEST_ASSERT(abs(capped - 2) < 0.001, "max_moles cap ignored: moved [capped]")
	TEST_ASSERT_EQUAL(source.get_moles(/datum/gas/nitrogen), nitrogen_before, "a masked transfer took an unmasked gas")

/// calculate_transfer_moles is now one Rust solve and agrees with what the transfer moves.
/datum/unit_test/dq_rust_calculate_transfer_moles_matches_transfer

/datum/unit_test/dq_rust_calculate_transfer_moles_matches_transfer/Run()
	var/datum/gas_mixture/source = new(1000)
	source.adjust_gas(/datum/gas/oxygen, 100)
	heat_set(source, T20C + 40, HEAT_SOURCE_OTHER)
	var/datum/gas_mixture/sink = new(500)
	sink.adjust_gas(/datum/gas/nitrogen, 5)
	heat_set(sink, T20C, HEAT_SOURCE_OTHER)
	var/wanted = calculate_transfer_moles(source, sink, 50)
	TEST_ASSERT(wanted > 0, "no transfer computed toward a higher pressure")
	source.transfer_to(sink, wanted)
	var/expected_kpa = 5 * R_IDEAL_GAS_EQUATION * T20C / 500 + 50
	TEST_ASSERT(abs(sink.return_pressure() - expected_kpa) < 1, "sink at [sink.return_pressure()] kPa, wanted [expected_kpa]")

/// A pipenet's volume is read from the Rust mixture, never stored in DM.
/datum/unit_test/dq_rust_pipenet_volume_reads_the_mixture

/datum/unit_test/dq_rust_pipenet_volume_reads_the_mixture/Run()
	var/datum/pipe_network/net = new
	TEST_ASSERT_EQUAL(net.volume(), 0, "a network with no air has volume")
	rel_set(net, "air", new /datum/gas_mixture(70))
	TEST_ASSERT_EQUAL(net.volume(), 70, "volume() did not read the mixture")
	net.air.set_volume(90)
	TEST_ASSERT_EQUAL(net.volume(), 90, "volume() lagged a Rust volume change")
	qdel(net)

/// native_changed raises the channel through om_changed and counts by source; the counters and
/// the per-bind FFI call counts ride along in verdigris_metrics_list().
/datum/unit_test/dq_rust_native_adapter_and_ffi_counter

/datum/unit_test/dq_rust_native_adapter_and_ffi_counter/Run()
	var/before = GLOB.native_deliveries[NATIVE_SRC_GAS_EVENT] || 0
	var/datum/gas_mixture/probe = new(100)
	TEST_ASSERT(native_changed(probe, CHANGE_TURF_GAS_VISUAL, NATIVE_SRC_GAS_EVENT), "native_changed refused a live target")
	TEST_ASSERT_EQUAL(GLOB.native_deliveries[NATIVE_SRC_GAS_EVENT], before + 1, "delivery was not counted")
	TEST_ASSERT(!native_changed(null, CHANGE_TURF_GAS_VISUAL), "native_changed accepted a null target")
	var/list/metrics = verdigris_metrics_list()
	TEST_ASSERT_NOTNULL(metrics, "verdigris_metrics returned nothing")
	TEST_ASSERT(metrics["ffi.calls_total"] > 0, "the FFI call counter is not counting")
	var/calls_before = metrics["ffi.calls_total"]
	probe.total_moles()
	probe.total_moles()
	var/list/after = verdigris_metrics_list()
	TEST_ASSERT(after["ffi.calls_total"] >= calls_before + 2, "two binds moved the counter by [after["ffi.calls_total"] - calls_before]")
	TEST_ASSERT_NOTNULL(after["dm.deliveries.gas_event"], "DM delivery counts missing from the metrics list")

/// A Rust error names its bind.
/datum/unit_test/dq_rust_error_names_the_bind

/datum/unit_test/dq_rust_error_names_the_bind/Run()
	TEST_ASSERT_EQUAL(vg_error_bind_name("in verdigris bind `read_mixtures`: boom"), "read_mixtures", "bind name not parsed")
	TEST_ASSERT_EQUAL(vg_error_bind_name("some other error"), "unknown", "a non-bind message was attributed to a bind")

/// SMES charge is read through Rust, and a set is a delta on Rust's value.
/datum/unit_test/dq_rust_smes_charge_reads_through

/datum/unit_test/dq_rust_smes_charge_reads_through/Run()
	var/obj/machinery/power/smes/S
	for(var/obj/machinery/power/smes/candidate as anything in REGISTRY_MEMBERS(REGISTRY_SMES))
		if(candidate.vg_entity && !candidate.broken_now())
			S = candidate
			break
	if(!S)
		TEST_NOTICE(src, "no registered SMES on the test map")
		return
	var/old = S.stored_charge()
	S.set_stored_charge(1234)
	TEST_ASSERT_EQUAL(S.stored_charge(), 1234, "stored_charge() did not read what was set")
	TEST_ASSERT_EQUAL(S.get_charge(), 1234, "Rust does not hold the charge DM set")
	S.adjust_stored_charge(-34)
	TEST_ASSERT_EQUAL(S.get_charge(), 1200, "adjust_stored_charge did not reach Rust")
	S.set_stored_charge(old)

/// One call binds many DeviceFlow rows, each readable back through its accessors.
/datum/unit_test/dq_rust_bulk_device_flow_bind

/datum/unit_test/dq_rust_bulk_device_flow_bind/Run()
	var/list/handles = rust_bind_device_flow_list(list(
		0, 7, 0, RUST_FLOW_VOLUME, 200, RUST_DIR_FORCED, RUST_SIDE_B, RUST_STOP_AT_LEAST, 101,
		0, 8, 0, RUST_FLOW_FRACTION, 0.25, RUST_DIR_FORCED, RUST_SIDE_A, RUST_STOP_NONE, 0,
	))
	TEST_ASSERT_EQUAL(length(handles), 2, "the bulk bind did not return one handle per row")
	TEST_ASSERT_EQUAL(get_device_flow_device(handles[1]), 7, "row 1 device")
	TEST_ASSERT_EQUAL(get_device_flow_rate_kind(handles[2]), RUST_FLOW_FRACTION, "row 2 kind is not Rate::Fraction")
	TEST_ASSERT(abs(get_device_flow_rate(handles[2]) - 0.25) < 0.001, "row 2 rate")
	for(var/handle in handles)
		vg_entity_unbind(handle)
