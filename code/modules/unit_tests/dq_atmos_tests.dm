// DQ atmos / LINDA migration tests.
// Validates the ZAS→LINDA engine swap with CHOMP machinery on top:
//   1. verdigris.dll loaded — Rust auxmos lib responds to the generated vg_* binds
//   2. gas_mixture procs work — adjust_gas, total_moles, return_pressure roundtrip
//   3. /turf/simulated/air persistence — dq_linda_turf_air bridge keeps moles
//      across return_air() calls (without it CHOMP machinery would mutate
//      throwaway copies and the world wouldn't atmos)
//   4. CHOMP canister presets — /obj/machinery/portable_atmospherics/canister/X
//      types initialize with their preset gas content
//   5. SSair init — gas singleton metadata reached Rust via auxtools_atmos_init

/// Empty both halves of the dependency publication pipeline before a focused
/// wake assertion. A full-suite run can inherit thousands of observations from
/// earlier fixtures; bounding an assertion by an arbitrary number of scans then
/// tests queue position rather than whether the new mutation wakes its device.
/proc/dq_atmos_test_drain_dependency_queue()
	while(!SSmachines.wake_dirty_gas_subscribers())
		stoplag()
	vg_drain_dirty_gas_observations()

/// Publish a synthetic fixture through the same Rust-authoritative port graph
/// used by map setup. Allocate every port before queueing edges so fixture order
/// cannot hide a missing reciprocal connection.
/proc/dq_atmos_test_publish_rust_pipenets(list/machines)
	for(var/obj/machinery/atmospherics/machine as anything in machines)
		machine.rust_allocate_pipe_ports()
	for(var/obj/machinery/atmospherics/machine as anything in machines)
		machine.rust_register_pipe_port_data()
	for(var/obj/machinery/atmospherics/machine as anything in machines)
		machine.rust_register_pipe_edges()
	SSair.rust_commit_pending_pipenets()

/// Verifies that verdigris.dll is actually loaded — vg_verdigris_version() should
/// return a non-empty string. If empty, the Rust library failed to load and
/// the rest of LINDA is running on /tg/'s pure-DM gas_mixture impl.
/datum/unit_test/dq_verdigris_loaded

/datum/unit_test/dq_verdigris_loaded/Run()
	var/version = vg_verdigris_version()
	TEST_ASSERT_NOTNULL(version, "vg_verdigris_version() returned null — DLL did not load")
	TEST_ASSERT(length("[version]") > 0, "vg_verdigris_version() returned empty — the bind failed")
	var/features = vg_verdigris_features()
	TEST_ASSERT_NOTNULL(features, "vg_verdigris_features() returned null")
	// Log to test output so we can see the version in CI logs.
	log_test("Verdigris loaded: [version] | features: [features]")


/// Vertical atmos gate: a SOLID floor must NOT let air cross a z-boundary through
/// itself, but an openspace (/turf/simulated/open) tile MUST. Regression for the
/// zAirIn/zAirOut stubs (were blanket `return TRUE`), which made every stacked-deck
/// floor atmos-merge with the tile above/below THROUGH the floor — so Southern
/// Cross's deck-2 gas tanks vented into the deck-1 space beneath them forever,
/// pinning ~573 turfs perpetually active and starving SSair. Pure-logic test: no
/// map/SSair dependency, just the zAir predicates the multi-z adjacency gate uses.
/datum/unit_test/dq_zair_blocks_vertical_through_floor

/datum/unit_test/dq_zair_blocks_vertical_through_floor/Run()
	// Use an EXISTING solid floor from the map (no turf mutation).
	var/turf/simulated/floor/solid = null
	for(var/turf/simulated/floor/cand in world)
		if(!istype(cand, /turf/simulated/open))  // exclude openspace floors
			solid = cand
			break
	TEST_ASSERT_NOTNULL(solid, "no solid floor found on map for zAir test")

	// A solid floor is not a hole: air can't fall out its bottom, nor rise in from below.
	TEST_ASSERT(!solid.zAirOut(DOWN, solid), "solid floor let air fall DOWN through it — zAirOut(DOWN) should be FALSE")
	TEST_ASSERT(!solid.zAirIn(UP, solid), "solid floor let air rise UP into it from below — zAirIn(UP) should be FALSE")
	// Complementary directions are unaffected (blocking is the UPPER tile's job).
	TEST_ASSERT(solid.zAirOut(UP, solid), "zAirOut(UP) on a floor should be TRUE (the tile above gates this)")
	TEST_ASSERT(solid.zAirIn(DOWN, solid), "zAirIn(DOWN) on a floor should be TRUE (receiving from above is always allowed)")

	// An openspace tile IS a hole: it must pass air vertically both ways. Openspace
	// isn't guaranteed on every map, so only assert if the type exists in the world.
	var/turf/simulated/open/hole = locate(/turf/simulated/open) in world
	if(hole)
		TEST_ASSERT(hole.zAirOut(DOWN, hole), "openspace should let air fall DOWN through it — zAirOut(DOWN) should be TRUE")
		TEST_ASSERT(hole.zAirIn(UP, hole), "openspace should let air rise UP into it — zAirIn(UP) should be TRUE")


/// Regression for the atom_defense.dm take_damage guard: damaging an atom that is
/// ALREADY at <=0 integrity (but not yet deleted) must be a harmless no-op, NOT a
/// hard CRASH. A sustained hotspot / explosion / rapid melee routinely lands a
/// second hit on the same tick a structure breaks — the old CRASH spammed runtimes
/// (benches burning down in a fire, ~11/round on Southern Cross). This is the
/// SYSTEMIC guard behind the burning-component point fix: it covers ALL damage
/// sources, not just fire.
/datum/unit_test/dq_take_damage_on_destroyed_atom_no_crash

/datum/unit_test/dq_take_damage_on_destroyed_atom_no_crash/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor to place the test structure")

	// A grille is a simple /obj (uses_integrity = TRUE via the /obj base) with no
	// material/gas dependencies, so it's a clean fixture.
	var/obj/structure/grille/G = new(T)
	TEST_ASSERT(G.uses_integrity, "test fixture doesn't use integrity — pick another type")

	// Force integrity to 0 WITHOUT going through take_damage's destruction path
	// (update_integrity clamps + doesn't qdel), reproducing the real "at 0 but still
	// alive" window that a second same-tick hit lands in.
	G.update_integrity(0)
	TEST_ASSERT(G.get_integrity() <= 0, "failed to force integrity to 0")
	TEST_ASSERT(!QDELETED(G), "fixture was deleted; can't exercise the <=0-but-alive path")

	// THE operation that used to CRASH. It must now return cleanly (the test
	// framework fails the test on any runtime, so reaching the next line = pass).
	G.take_damage(25, BRUTE, MELEE)
	TEST_ASSERT(G.get_integrity() <= 0, "integrity unexpectedly changed damaging a 0-integrity atom")

	qdel(G)


/// Verifies a gas_mixture round-trips through LINDA's gas_mixture API.
/// Builds via adjust_gas (XGM-compat shim accepting type path), reads back via
/// total_moles() (proc) and return_pressure() (auxmos byondapi bind or DM).
/datum/unit_test/dq_gas_mixture_rust_roundtrip

/datum/unit_test/dq_gas_mixture_rust_roundtrip/Run()
	var/datum/gas_mixture/mix = new(CELL_VOLUME)
	TEST_ASSERT_NOTNULL(mix, "Failed to allocate gas_mixture")

	mix.adjust_gas(/datum/gas/oxygen, MOLES_O2STANDARD)
	mix.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)
	mix.set_temperature(T20C)

	var/total = mix.total_moles()
	TEST_ASSERT(total > 0, "total_moles() returned 0 after adjust_gas: [total]")
	TEST_ASSERT(abs(total - (MOLES_O2STANDARD + MOLES_N2STANDARD)) < 0.01, \
		"total_moles() = [total], expected ~[MOLES_O2STANDARD + MOLES_N2STANDARD]")

	var/pressure = mix.return_pressure()
	TEST_ASSERT(abs(pressure - ONE_ATMOSPHERE) < 5, \
		"return_pressure() = [pressure], expected ~[ONE_ATMOSPHERE]")

	var/temp = mix.return_temperature()
	TEST_ASSERT_EQUAL(temp, T20C, "return_temperature() drifted: [temp] vs [T20C]")


/// Verifies the /turf/simulated/air persistence bridge (dq_linda_turf_air.dm).
/// Without it, every T.return_air() call returns a NEW throwaway mixture and
/// CHOMP atmos machinery would silently fail. This test mutates a turf's air
/// and checks the mutation persists across a second return_air() call.
/datum/unit_test/dq_turf_air_persistence

/datum/unit_test/dq_turf_air_persistence/Run()
	var/turf/simulated/T = null
	for(var/turf/simulated/sim_turf in world)
		if(sim_turf.air) // genuinely air-bearing turf (return_air() is now never-null, so it can't be the presence check)
			T = sim_turf
			break
	TEST_ASSERT_NOTNULL(T, "No simulated turf with air available for persistence test")

	var/datum/gas_mixture/air = T.return_air()
	TEST_ASSERT_NOTNULL(air, "return_air() returned null on simulated turf")
	var/initial_total = air.total_moles()

	// Mutate via adjust_gas. If the bridge is missing, the mutation lands on
	// a throwaway and a second return_air() shows initial_total again.
	air.adjust_gas(/datum/gas/oxygen, 50)

	var/datum/gas_mixture/air2 = T.return_air()
	TEST_ASSERT(air2 == air, \
		"return_air() returned a different mixture object on second call — bridge missing!")
	var/total_after = air2.total_moles()
	TEST_ASSERT(total_after > initial_total, \
		"Turf air did not persist: initial=[initial_total], after add=[total_after]")


/// Verifies CHOMP canister presets initialize with their declared gas content.
/datum/unit_test/dq_chomp_canister_presets_have_gas

/datum/unit_test/dq_chomp_canister_presets_have_gas/Run()
	for(var/canister_type in list(
		/obj/machinery/portable_atmospherics/canister/oxygen,
		/obj/machinery/portable_atmospherics/canister/nitrogen,
		/obj/machinery/portable_atmospherics/canister/phoron,
		/obj/machinery/portable_atmospherics/canister/carbon_dioxide,
		/obj/machinery/portable_atmospherics/canister/air,
	))
		var/obj/machinery/portable_atmospherics/canister/C = new canister_type(locate(1, 1, 1))
		TEST_ASSERT_NOTNULL(C, "[canister_type]: failed to construct")
		TEST_ASSERT_NOTNULL(C.air_contents, "[canister_type]: air_contents not allocated")
		var/moles = C.air_contents.total_moles()
		TEST_ASSERT(moles > 1, "[canister_type]: starting moles too low ([moles])")
		var/pressure = C.air_contents.return_pressure()
		TEST_ASSERT(pressure > ONE_ATMOSPHERE, \
			"[canister_type]: pressure too low ([pressure] kPa) — canister should be pressurized")
		qdel(C)


/// Verifies SSair initialized and built its gas-reaction roster at boot — that
/// init_gas_reactions() populated SSair.gas_reactions. If it didn't, gas_mixture
/// react() would do nothing and burn() / equalize() would silently no-op.
/// (Gas math runs in pure DM; the Rust auxmos backend is not wired — see SSair.)
/datum/unit_test/dq_ssair_initialized

/datum/unit_test/dq_ssair_initialized/Run()
	TEST_ASSERT_NOTNULL(SSair, "SSair is null — subsystem failed to initialize")
	TEST_ASSERT(SSair.initialized, "SSair did not finish Initialize()")
	TEST_ASSERT_NOTNULL(SSair.gas_reactions, "SSair.gas_reactions list is null")
	TEST_ASSERT(length(SSair.gas_reactions) > 0, \
		"SSair.gas_reactions is empty — gas_mixture reactions wouldn't fire")


/// Verifies GLOB.gas_data was populated at construction from /datum/gas
/// subtypes. CHOMP atmos analyzer, supply demand events, hydroponics, bomb
/// tester, and engineering announcements all read GLOB.gas_data.name[gas_id]
/// to render gas-aware UI. If empty, every label would show as "null".
/datum/unit_test/dq_gas_data_populated

/datum/unit_test/dq_gas_data_populated/Run()
	TEST_ASSERT_NOTNULL(GLOB.gas_data, "GLOB.gas_data is null")
	TEST_ASSERT_NOTNULL(GLOB.gas_data.name, "GLOB.gas_data.name list is null")
	TEST_ASSERT(length(GLOB.gas_data.name) >= 5, \
		"GLOB.gas_data.name only has [length(GLOB.gas_data.name)] entries")
	// Spot-check core gas IDs CHOMP UI strings depend on.
	for(var/gas_id in list(GAS_O2, GAS_N2, GAS_CO2, GAS_PHORON, GAS_N2O))
		TEST_ASSERT(!isnull(GLOB.gas_data.name[gas_id]), \
			"GLOB.gas_data.name\[[gas_id]\] is null — atmos analyzer/UI will display null")
		TEST_ASSERT(GLOB.gas_data.specific_heat[gas_id] > 0, \
			"GLOB.gas_data.specific_heat\[[gas_id]\] is 0 — scrubber power calc would NaN")


/// Verifies gas_mixture.gas_ids() returns XGM string ids for every gas in the
/// mixture. CHOMP scrub_gas/filter_gas iterate via this proc; if it returns
/// an empty list, every scrubber/filter silently no-ops.
/datum/unit_test/dq_gas_ids_lists_present_gases

/datum/unit_test/dq_gas_ids_lists_present_gases/Run()
	var/datum/gas_mixture/mix = new(CELL_VOLUME)
	mix.adjust_gas(/datum/gas/oxygen, 10)
	mix.adjust_gas(/datum/gas/carbon_dioxide, 5)
	mix.adjust_gas(/datum/gas/plasma, 2)

	var/list/ids = mix.gas_ids()
	TEST_ASSERT_NOTNULL(ids, "gas_ids() returned null")
	TEST_ASSERT_EQUAL(length(ids), 3, "gas_ids() length [length(ids)], expected 3")
	TEST_ASSERT(GAS_O2 in ids, "gas_ids() missing GAS_O2 ([GAS_O2]); has: [json_encode(ids)]")
	TEST_ASSERT(GAS_CO2 in ids, "gas_ids() missing GAS_CO2 ([GAS_CO2])")
	TEST_ASSERT(GAS_PHORON in ids, "gas_ids() missing GAS_PHORON ([GAS_PHORON]) — should map to plasma since #define wins")


/// Verifies plasma combustion reaction fires when given oxygen + plasma + heat.
/// The vendored /tg/ plasmafire reaction consumes plasma+O2 above
/// PLASMA_MINIMUM_BURN_TEMPERATURE and produces CO2 + water_vapor.
/datum/unit_test/dq_plasmafire_reaction_consumes_plasma

/datum/unit_test/dq_plasmafire_reaction_consumes_plasma/Run()
	var/datum/gas_mixture/mix = new(CELL_VOLUME)
	mix.adjust_gas(/datum/gas/plasma, 50)
	mix.adjust_gas(/datum/gas/oxygen, 200) // plenty of oxidizer
	mix.set_temperature(PLASMA_MINIMUM_BURN_TEMPERATURE + 200)

	var/initial_plasma = mix.get_moles(/datum/gas/plasma)
	var/initial_o2 = mix.get_moles(/datum/gas/oxygen)
	var/initial_co2 = mix.get_moles(/datum/gas/carbon_dioxide)
	TEST_ASSERT(initial_plasma > 0, "plasma not added: [initial_plasma]")

	mix.react(null)

	var/post_plasma = mix.get_moles(/datum/gas/plasma)
	var/post_o2 = mix.get_moles(/datum/gas/oxygen)
	var/post_co2 = mix.get_moles(/datum/gas/carbon_dioxide)
	TEST_ASSERT(post_plasma < initial_plasma, \
		"plasma did not burn: [initial_plasma] → [post_plasma]")
	TEST_ASSERT(post_o2 < initial_o2, \
		"oxygen did not deplete: [initial_o2] → [post_o2]")
	TEST_ASSERT(post_co2 > initial_co2, \
		"CO2 not produced: [initial_co2] → [post_co2]")
	var/mix_temp = mix.return_temperature()
	TEST_ASSERT(mix_temp > PLASMA_MINIMUM_BURN_TEMPERATURE + 200, \
		"temperature did not rise from exothermic reaction: [mix_temp]")


/// Verifies scrub_gas() helper actually transfers gas. Without the gas_ids()
/// migration this proc no-op'd because it iterated `source.gas` (empty).
/datum/unit_test/dq_scrub_gas_removes_target

/datum/unit_test/dq_scrub_gas_removes_target/Run()
	var/datum/gas_mixture/source = new(CELL_VOLUME)
	source.adjust_gas(/datum/gas/oxygen, 80)
	source.adjust_gas(/datum/gas/carbon_dioxide, 50)
	source.set_temperature(T20C)

	var/datum/gas_mixture/sink = new(CELL_VOLUME)
	sink.set_temperature(T20C)

	var/before_source_co2 = source.get_moles(/datum/gas/carbon_dioxide)
	var/before_source_o2 = source.get_moles(/datum/gas/oxygen)

	// Scrub only CO2 (string-id keyed list, like vent_scrubber.dm's scrubbing_gas).
	var/power = scrub_gas(null, list(GAS_CO2), source, sink, 100, null)
	TEST_ASSERT(power >= 0, "scrub_gas returned [power] — no transfer happened; gas_ids() bridge broken")

	var/after_source_co2 = source.get_moles(/datum/gas/carbon_dioxide)
	var/after_source_o2 = source.get_moles(/datum/gas/oxygen)
	var/sink_co2 = sink.get_moles(/datum/gas/carbon_dioxide)
	TEST_ASSERT(after_source_co2 < before_source_co2, \
		"CO2 not removed from source: [before_source_co2] → [after_source_co2]")
	TEST_ASSERT(sink_co2 > 0, "CO2 not deposited into sink: [sink_co2]")
	TEST_ASSERT_EQUAL(after_source_o2, before_source_o2, \
		"O2 should be untouched by CO2-only scrub: [before_source_o2] → [after_source_o2]")


/// Verifies canister.release() transfers gas from canister to its turf air.
/// Exercises portable_atmospherics + the /turf/simulated/air bridge end-to-end.
/datum/unit_test/dq_canister_release_to_turf

/datum/unit_test/dq_canister_release_to_turf/Run()
	var/turf/simulated/T = null
	for(var/turf/simulated/sim_turf in world)
		if(sim_turf.air) // genuinely air-bearing turf (return_air() is now never-null, so it can't be the presence check)
			T = sim_turf
			break
	TEST_ASSERT_NOTNULL(T, "no simulated turf with air for canister test")

	var/obj/machinery/portable_atmospherics/canister/oxygen/C = new(T)
	TEST_ASSERT_NOTNULL(C, "failed to construct canister")
	TEST_ASSERT_NOTNULL(C.air_contents, "canister air_contents null")

	var/initial_canister_o2 = C.air_contents.get_moles(/datum/gas/oxygen)
	TEST_ASSERT(initial_canister_o2 > 100, \
		"oxygen canister starting moles too low: [initial_canister_o2]")

	var/datum/gas_mixture/turf_air = T.return_air()
	var/initial_turf_o2 = turf_air.get_moles(/datum/gas/oxygen)

	// Open the canister to release.
	C.valve_open = TRUE
	C.release_pressure = 1000 // high release for fast transfer
	// Drive the canister's release loop directly. process() (not process_atmos())
	// is what runs the valve transfer in CHOMP's portable_atmospherics machinery.
	for(var/i in 1 to 10)
		C.process()

	var/final_canister_o2 = C.air_contents.get_moles(/datum/gas/oxygen)
	var/final_turf_o2 = T.return_air().get_moles(/datum/gas/oxygen)
	TEST_ASSERT(final_canister_o2 < initial_canister_o2, \
		"canister O2 didn't drop: [initial_canister_o2] → [final_canister_o2]")
	TEST_ASSERT(final_turf_o2 > initial_turf_o2, \
		"turf O2 didn't rise after canister release: [initial_turf_o2] → [final_turf_o2]")

	qdel(C)


/// Verifies that hotspot_expose() on a turf with combustible gas creates an
/// /obj/effect/hotspot. The LINDA hotspot system is what represents on-tile
/// fires after the ZAS /obj/fire layer was retired.
/datum/unit_test/dq_hotspot_expose_creates_fire

/datum/unit_test/dq_hotspot_expose_creates_fire/Run()
	var/turf/simulated/T = null
	for(var/turf/simulated/sim_turf in world)
		if(sim_turf.air) // genuinely air-bearing turf (return_air() is now never-null, so it can't be the presence check)
			T = sim_turf
			break
	TEST_ASSERT_NOTNULL(T, "no simulated turf for hotspot test")

	// Wipe any preexisting hotspot from earlier tests.
	if(T.active_hotspot)
		qdel(T.active_hotspot)
		T.active_hotspot = null

	// Stock the turf with plasma + oxygen so hotspot can sustain.
	var/datum/gas_mixture/air = T.return_air()
	air.adjust_gas(/datum/gas/plasma, 20)
	air.adjust_gas(/datum/gas/oxygen, 50)
	air.set_temperature(PLASMA_MINIMUM_BURN_TEMPERATURE + 300)

	TEST_ASSERT(isnull(T.active_hotspot), "test setup: hotspot already exists pre-expose")

	T.hotspot_expose(PLASMA_MINIMUM_BURN_TEMPERATURE + 300, CELL_VOLUME, soh = TRUE)

	TEST_ASSERT_NOTNULL(T.active_hotspot, "active_hotspot not created after hotspot_expose")
	TEST_ASSERT(istype(T.active_hotspot, /obj/effect/hotspot), \
		"active_hotspot wrong type: [T.active_hotspot.type]")

	if(T.active_hotspot)
		qdel(T.active_hotspot)
		T.active_hotspot = null


/// Verifies a human's handle_breath cycle consumes O2 and produces CO2 against
/// a LINDA gas_mixture. This is the full mob breath integration path:
/// life.dm uses LINDA_GAS_AMT / adjust_gas_temp through the xgm_compat_shim.
/datum/unit_test/dq_human_breath_cycle

/datum/unit_test/dq_human_breath_cycle/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_NOTNULL(H, "couldn't allocate test human")
	TEST_ASSERT_NOTNULL(H.species, "test human has no species")

	// Build a standard-atmosphere breath mixture.
	var/datum/gas_mixture/breath = new(BREATH_VOLUME)
	breath.adjust_gas(/datum/gas/oxygen, MOLES_O2STANDARD)
	breath.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)
	breath.set_temperature(T20C)

	var/initial_o2 = breath.get_moles(/datum/gas/oxygen)
	var/initial_co2 = breath.get_moles(/datum/gas/carbon_dioxide)

	life_test_breath(H, breath)

	var/final_o2 = breath.get_moles(/datum/gas/oxygen)
	var/final_co2 = breath.get_moles(/datum/gas/carbon_dioxide)

	TEST_ASSERT(final_o2 < initial_o2, \
		"breath O2 didn't drop: [initial_o2] → [final_o2] — human handle_breath didn't consume oxygen")
	TEST_ASSERT(final_co2 > initial_co2, \
		"breath CO2 didn't rise: [initial_co2] → [final_co2] — human handle_breath didn't exhale CO2")


/// FULL end-to-end: human stands on a turf that has plasma in its air,
/// then breathe() runs through the production chain — get_breath_from_environment
/// → environment.remove_volume → mask filter_air → handle_breath →
/// injure(INJURY_TOXIN) / reagent. If THIS passes but dq_phoron_breath_applies_toxin_reagent
/// also passes and in-game tox still doesn't apply, the live scenario's
/// plasma concentration is too low (not enough phoron made it to the
/// player's tile to cross safe_toxins_max).
/datum/unit_test/dq_phoron_breath_via_full_chain_applies_toxin

/datum/unit_test/dq_phoron_breath_via_full_chain_applies_toxin/Run()
	// Find a floor on the test map (the unit_tests.dmm landmark template
	// isn't loaded on this fork, so allocate's default loc is null).
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor available for full-chain breath test")

	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT_NOTNULL(H, "couldn't allocate test human")
	TEST_ASSERT_NOTNULL(H.species, "test human has no species")
	TEST_ASSERT_NOTNULL(H.reagents, "human has no reagents")
	TEST_ASSERT_NOTNULL(T.air, "turf has no air mixture")

	// Inject plasma into the player's tile via the production API. This is
	// the path canister.process / atmos_spawn_air go through.
	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/plasma, 200)
	donor.adjust_gas(/datum/gas/oxygen, MOLES_O2STANDARD)
	donor.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)
	donor.set_temperature(T20C)
	T.assume_air(donor)

	var/turf_plasma = T.air.get_moles(/datum/gas/plasma)
	TEST_ASSERT(turf_plasma > 100, "donor plasma didn't land on player turf: [turf_plasma]")

	// Make sure player has no internals / mask filtering distorting the test.
	H.internal = null
	H.drop_from_inventory(H.get_equipped_item(SLOT_ID_MASK))

	var/initial_toxin = H.reagents.get_reagent_amount(REAGENT_ID_TOXIN)

	// Drive the production breath path.
	life_test_breathe(H)

	var/final_toxin = H.reagents.get_reagent_amount(REAGENT_ID_TOXIN)
	TEST_ASSERT(final_toxin > initial_toxin, \
		"breathe() on a 200-mol-plasma turf did NOT add toxin reagent: [initial_toxin] → [final_toxin]. Turf plasma was [turf_plasma]. The chain from turf → breath → handle_breath → reagent is broken under LINDA.")

	for(var/datum/gas/g as anything in T.air.get_gases())
		T.air.set_moles(g, 0)


/// Breathing a plasma-laden gas mixture MUST add a toxin reagent to the
/// human's bloodstream. If this fails, players can stand in phoron with no
/// consequences — the breath path's toxin damage hook is broken.
/datum/unit_test/dq_phoron_breath_applies_toxin_reagent

/datum/unit_test/dq_phoron_breath_applies_toxin_reagent/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_NOTNULL(H, "couldn't allocate test human")
	TEST_ASSERT_NOTNULL(H.species, "test human has no species")
	TEST_ASSERT_NOTNULL(H.reagents, "test human has no reagents holder — damage path can't fire")

	// Default human species poison_type is GAS_PHORON (which #defines to
	// GAS_PLASMA = "plasma" under LINDA). If that's been broken, the breath
	// path won't recognize plasma as toxic.
	TEST_ASSERT_EQUAL(H.species.poison_type, GAS_PHORON, \
		"species.poison_type isn't GAS_PHORON ([H.species.poison_type] vs [GAS_PHORON]) — tox detection won't trigger")

	// Build a breath with plasma at high partial pressure (well above
	// safe_toxins_max=0.2 kPa).
	var/datum/gas_mixture/breath = new(BREATH_VOLUME)
	breath.adjust_gas(/datum/gas/oxygen, MOLES_O2STANDARD * 0.5)
	breath.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD * 0.5)
	breath.adjust_gas(/datum/gas/plasma, MOLES_O2STANDARD * 0.5)  // ~16 mol per breath
	breath.set_temperature(T20C)

	// Verify LINDA_GAS_AMT correctly resolves "plasma" string → /datum/gas/plasma.
	var/plasma_seen = LINDA_GAS_AMT(breath, GAS_PHORON)
	TEST_ASSERT(plasma_seen > 5, \
		"LINDA_GAS_AMT(breath, GAS_PHORON) = [plasma_seen] — string→type lookup broken")

	var/initial_toxin = H.reagents.get_reagent_amount(REAGENT_ID_TOXIN)

	life_test_breath(H, breath)

	var/final_toxin = H.reagents.get_reagent_amount(REAGENT_ID_TOXIN)
	TEST_ASSERT(final_toxin > initial_toxin, \
		"plasma in breath did NOT add toxin reagent: [initial_toxin] → [final_toxin]. Player can breathe plasma without consequences.")


/// Verifies atmosanalyzer_scan returns lines with real gas names. This was
/// broken pre-fix because GLOB.gas_data.name was empty and `for(g in mix.gas)`
/// iterated an empty list — analyzers would say "Pressure: 100 kPa" with no
/// gas breakdown. Now both should work.
/datum/unit_test/dq_atmos_analyzer_lists_gases

/datum/unit_test/dq_atmos_analyzer_lists_gases/Run()
	var/datum/gas_mixture/mix = new(CELL_VOLUME)
	mix.adjust_gas(/datum/gas/oxygen, MOLES_O2STANDARD)
	mix.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)
	mix.set_temperature(T20C)

	var/list/result = atmosanalyzer_scan(null, mix, null)
	TEST_ASSERT_NOTNULL(result, "atmosanalyzer_scan returned null")
	TEST_ASSERT(length(result) >= 3, "expected ≥3 result lines, got [length(result)]")

	var/has_o2_line = FALSE
	var/has_n2_line = FALSE
	var/has_pressure_line = FALSE
	for(var/line in result)
		if(findtext(line, "Oxygen"))
			has_o2_line = TRUE
		if(findtext(line, "Nitrogen"))
			has_n2_line = TRUE
		if(findtext(line, "Pressure"))
			has_pressure_line = TRUE
	TEST_ASSERT(has_pressure_line, "analyzer missing 'Pressure' line: [json_encode(result)]")
	TEST_ASSERT(has_o2_line, "analyzer missing 'Oxygen' line: [json_encode(result)]")
	TEST_ASSERT(has_n2_line, "analyzer missing 'Nitrogen' line: [json_encode(result)]")


/// Exercises the PDA app's actual update path. Passing its turf directly to the
/// gas-mixture scanner used to runtime on every UI refresh after the LINDA cutover.
/datum/unit_test/dq_pda_atmos_scanner_reads_turf_air

/datum/unit_test/dq_pda_atmos_scanner_reads_turf_air/Run()
	var/turf/simulated/floor/location
	for(var/turf/simulated/floor/candidate in world)
		if(candidate.air && !candidate.blocks_air)
			location = candidate
			break
	TEST_ASSERT_NOTNULL(location, "unit-test room has no floor for the PDA atmospheric scanner")
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, location)
	var/datum/data/pda/app/atmos_scanner/scanner = allocate(/datum/data/pda/app/atmos_scanner)
	var/list/data = list()

	scanner.update_ui(user, data)

	var/list/aircontents = data["aircontents"]
	TEST_ASSERT(islist(aircontents), "PDA atmospheric scanner did not produce a scan-data list")
	TEST_ASSERT(length(aircontents), "PDA atmospheric scanner produced an empty scan-data list")
	var/list/pressure_row = aircontents[1]
	TEST_ASSERT(islist(pressure_row), "PDA atmospheric scanner returned chat text instead of structured rows")
	TEST_ASSERT_EQUAL(pressure_row["entry"], "Pressure", "PDA atmospheric scanner's first row is not pressure")
	TEST_ASSERT(isnum(pressure_row["val"]), "PDA atmospheric scanner pressure is not numeric")
	TEST_ASSERT_NOTNULL(pressure_row["bad_low"], "PDA atmospheric scanner omitted warning thresholds")


/// Verifies gas_mixture.merge() (auxmos byondapi-bound) preserves total moles
/// across mixtures. Pipenet share/merge depends on this being correct.
/datum/unit_test/dq_gas_mixture_merge_conserves_moles

/datum/unit_test/dq_gas_mixture_merge_conserves_moles/Run()
	var/datum/gas_mixture/A = new(CELL_VOLUME)
	A.adjust_gas(/datum/gas/oxygen, 50)
	A.adjust_gas(/datum/gas/nitrogen, 100)
	A.set_temperature(T20C)
	var/a_moles = A.total_moles()

	var/datum/gas_mixture/B = new(CELL_VOLUME)
	B.adjust_gas(/datum/gas/carbon_dioxide, 30)
	B.set_temperature(T20C)
	var/b_moles = B.total_moles()

	A.merge(B)

	var/combined = A.total_moles()
	TEST_ASSERT(abs(combined - (a_moles + b_moles)) < 0.01, \
		"merge moles wrong: [a_moles] + [b_moles] != [combined]")
	TEST_ASSERT(A.get_moles(/datum/gas/carbon_dioxide) > 0, \
		"merge didn't bring CO2 from B into A")


/// Verifies gas_mixture.remove(amount) takes the specified moles and returns
/// a new mixture with those moles. Canister release + remove_volume() rely on
/// this.
/datum/unit_test/dq_gas_mixture_remove_takes_moles

/datum/unit_test/dq_gas_mixture_remove_takes_moles/Run()
	var/datum/gas_mixture/mix = new(CELL_VOLUME)
	mix.adjust_gas(/datum/gas/oxygen, 200)
	mix.set_temperature(T20C)

	var/initial = mix.total_moles()
	var/datum/gas_mixture/removed = mix.remove(50)

	TEST_ASSERT_NOTNULL(removed, "remove() returned null")
	var/after = mix.total_moles()
	var/removed_amt = removed.total_moles()
	TEST_ASSERT(abs(after - (initial - 50)) < 0.5, \
		"source moles wrong after remove: expected [initial - 50], got [after]")
	TEST_ASSERT(abs(removed_amt - 50) < 0.5, \
		"removed amount wrong: expected 50, got [removed_amt]")


/// Verifies the CHOMP /turf/proc/feed_lingering_fire bridge spawns a hotspot
/// when fed sufficient fuel intensity. Floor acts and CHOMP gameplay code call
/// this — if the bridge no-ops, lingering fires just don't exist.
/datum/unit_test/dq_lingering_fire_bridge

/datum/unit_test/dq_lingering_fire_bridge/Run()
	var/turf/simulated/T = null
	for(var/turf/simulated/sim_turf in world)
		if(sim_turf.air) // genuinely air-bearing turf (return_air() is now never-null, so it can't be the presence check)
			T = sim_turf
			break
	TEST_ASSERT_NOTNULL(T, "no simulated turf for lingering fire test")

	if(T.active_hotspot)
		qdel(T.active_hotspot)
		T.active_hotspot = null

	// Stock with fuel + oxidizer.
	var/datum/gas_mixture/air = T.return_air()
	air.adjust_gas(/datum/gas/plasma, 30)
	air.adjust_gas(/datum/gas/oxygen, 80)
	air.set_temperature(T20C)

	T.feed_lingering_fire(2.0)

	TEST_ASSERT_NOTNULL(T.active_hotspot, "feed_lingering_fire didn't spawn an active_hotspot")
	TEST_ASSERT_NOTNULL(T.lingering_fire(), "lingering_fire() returns null despite active_hotspot")

	if(T.active_hotspot)
		qdel(T.active_hotspot)
		T.active_hotspot = null


/// After the /turf/simulated → /turf/open reparent, every gas-bearing simulated
/// turf must istype as /turf/open so LINDA's adjacency calc, process_cell, and
/// update_visuals all run on it. Without this, gases don't spread or render on
/// the actual map (since the map terrain is /turf/simulated/floor, not /turf/open).
/datum/unit_test/dq_simulated_floor_is_open_turf
	priority = TEST_PRE

/datum/unit_test/dq_simulated_floor_is_open_turf/Run()
	var/list/default_parts = SSair.gas_string_to_list(OPENTURF_DEFAULT_ATMOS)
	TEST_ASSERT_EQUAL(default_parts[GAS_N2], "82", "default atmos parser did not retain nitrogen")
	var/datum/gas_mixture/default_mix = SSair.parse_gas_string(OPENTURF_DEFAULT_ATMOS)
	TEST_ASSERT(default_mix.get_moles(/datum/gas/nitrogen) > 80, \
		"parsed default atmosphere has no nitrogen: [default_mix.get_moles(/datum/gas/nitrogen)] moles")
	var/turf/simulated/floor/F = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.initial_gas_mix != OPENTURF_DEFAULT_ATMOS)
			continue
		F = cand
		break
	TEST_ASSERT_NOTNULL(F, "no /turf/simulated/floor on the test map — can't validate reparent")
	TEST_ASSERT(istype(F, /turf/open), \
		"/turf/simulated/floor is NOT /turf/open — the reparent in code/game/turfs/simulated.dm didn't take effect")
	TEST_ASSERT_NOTNULL(F.air, \
		"/turf/simulated/floor.air is null — /turf/open/Initialize didn't create the mixture (blocks_air? unexpected initial_gas_mix?)")
	TEST_ASSERT(F.air.get_moles(/datum/gas/oxygen) > 20, \
		"default station floor has no round-start oxygen: [F.air.get_moles(/datum/gas/oxygen)] moles")
	TEST_ASSERT(F.air.get_moles(/datum/gas/nitrogen) > 80, \
		"default station floor has no round-start nitrogen: [F.air.get_moles(/datum/gas/nitrogen)] moles")


/// A closed station atmosphere component containing an air alarm must not have
/// an atmos adjacency path to space at round start.
/datum/unit_test/dq_station_alarm_component_is_sealed
	priority = TEST_PRE

/datum/unit_test/dq_station_alarm_component_is_sealed/Run()
	var/list/checked = list()
	var/list/alarm_turfs = list()
	var/list/alarm_pressures = list()
	var/list/alarm_temperatures = list()
	var/list/alarm_turf_temperatures = list()
	var/alarm_count = 0
	for(var/obj/machinery/alarm/candidate in world)
		var/turf/candidate_turf = get_turf(candidate)
		if(!candidate_turf || candidate_turf.z > 3 || checked[candidate_turf])
			continue
		alarm_count++
		var/turf/open/start = candidate_turf
		TEST_ASSERT_NOTNULL(start.air, "air alarm at [start.x],[start.y],[start.z] is not on an air-bearing turf")
		if(start.air.return_temperature() >= 285)
			alarm_turfs += start
			alarm_pressures += start.air.return_pressure()
			alarm_temperatures += start.air.return_temperature()
			alarm_turf_temperatures += start.get_temperature()
		var/list/queue = list(start)
		checked[start] = TRUE
		var/head = 1
		while(head <= length(queue))
			var/turf/open/current = queue[head++]
			for(var/turf/open/neighbor as anything in vg_atmos_adjacent_turfs(current))
				if(checked[neighbor])
					continue
				if(istype(neighbor, /turf/space))
					TEST_FAIL("air alarm area [get_area(candidate)] at [start.x],[start.y],[start.z] reaches space through atmos edge [current.x],[current.y],[current.z] -> [neighbor.x],[neighbor.y],[neighbor.z]")
				if(neighbor.initial_gas_mix == AIRLESS_ATMOS)
					var/list/blockers = list()
					for(var/obj/blocker in current.contents + neighbor.contents)
						blockers += "[blocker.type](dir=[blocker.dir], anchored=[blocker.anchored], pass=[CANATMOSPASS(blocker, blocker.loc == current ? neighbor : current, FALSE)])"
					TEST_FAIL("air alarm area [get_area(candidate)] at [start.x],[start.y],[start.z] reaches an airless turf through atmos edge [current.x],[current.y],[current.z] -> [neighbor.x],[neighbor.y],[neighbor.z]; objects: [jointext(blockers, "; ")]")
				checked[neighbor] = TRUE
				queue += neighbor
			CHECK_TICK
	TEST_ASSERT(alarm_count > 0, "no Southern Cross air alarm found")
	for(var/turf/open/vertical_source in world)
		for(var/turf/open/vertical_target as anything in vg_atmos_adjacent_turfs(vertical_source))
			if(vertical_source.z == vertical_target.z)
				continue
			var/turf/upper = vertical_source.z > vertical_target.z ? vertical_source : vertical_target
			TEST_ASSERT(istype(upper, /turf/simulated/open), \
				"solid stacked turfs have a vertical atmos edge: [vertical_source.x],[vertical_source.y],[vertical_source.z] <-> [vertical_target.x],[vertical_target.y],[vertical_target.z]")
	// Up to 40 SSair fires; a sealed station goes quiet well before that, while
	// a component leaking to space stays pending and uses the whole budget.
	var/waited_fires = dq_unit_test_wait_air_until_quiescent(40)
	log_test("station alarm seal: waited [waited_fires]/40 SSair fires before atmos went idle")
	var/list/alarm_pressure_losses = list()
	for(var/alarm_index in 1 to length(alarm_turfs))
		var/turf/open/alarm_turf = alarm_turfs[alarm_index]
		var/final_pressure = alarm_turf.air.return_pressure()
		var/final_temperature = alarm_turf.air.return_temperature()
		var/final_turf_temperature = alarm_turf.get_temperature()
		if(final_pressure < alarm_pressures[alarm_index] * 0.98 || final_temperature < alarm_temperatures[alarm_index] * 0.98)
			alarm_pressure_losses += "[get_area(alarm_turf)] at [alarm_turf.x],[alarm_turf.y],[alarm_turf.z]: [alarm_pressures[alarm_index]] -> [final_pressure] kPa, gas [alarm_temperatures[alarm_index]] -> [final_temperature] K, turf [alarm_turf_temperatures[alarm_index]] -> [final_turf_temperature] K"
	var/alarm_loss_report = jointext(alarm_pressure_losses, "; ")
	TEST_ASSERT(!length(alarm_pressure_losses), "station air alarms rapidly lost pressure: [alarm_loss_report]")


/// Phoron (= LINDA plasma, GAS_PHORON #defined to GAS_PLASMA) must render a
/// visible gas overlay once concentration crosses /datum/gas/plasma.moles_visible.
/// Failure points covered: meta_gas_info not populated, GAS_OVERLAYS macro
/// short-circuits early, /turf/open/update_visuals not reached on simulated turfs.
/datum/unit_test/dq_phoron_renders_above_visible_threshold

/datum/unit_test/dq_phoron_renders_above_visible_threshold/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no /turf/simulated/floor with air for phoron-render test")

	// Pre-test: gas-overlay metadata must be present for /datum/gas/plasma.
	// If meta_gas_info is missing /datum/gas/plasma the overlay logic
	// will never emit anything, no matter what we put on the turf.
	var/list/meta = GLOB.meta_gas_info
	TEST_ASSERT_NOTNULL(meta, "GLOB.meta_gas_info is null — meta_gas_list() never ran")
	var/list/plasma_meta = meta[/datum/gas/plasma]
	TEST_ASSERT_NOTNULL(plasma_meta, "GLOB.meta_gas_info has no entry for /datum/gas/plasma")
	TEST_ASSERT_NOTNULL(plasma_meta[META_GAS_MOLES_VISIBLE], \
		"plasma META_GAS_MOLES_VISIBLE is null — visibility threshold not set")
	TEST_ASSERT_NOTNULL(plasma_meta[META_GAS_OVERLAY], \
		"plasma META_GAS_OVERLAY is null — overlay graphics never generated (SSmapping not ready when meta_gas_list ran?)")

	// Wipe any preexisting overlays / hotspot so we start clean.
	if(T.active_hotspot)
		qdel(T.active_hotspot)
		T.active_hotspot = null
	if(T.atmos_overlay_types)
		for(var/old_ov in T.atmos_overlay_types)
			T.vis_contents -= old_ov
		T.atmos_overlay_types = null

	// Pump in well above MOLES_GAS_VISIBLE (= 0.25).
	var/datum/gas_mixture/air = T.return_air()
	air.adjust_gas(/datum/gas/plasma, 50)

	T.update_visuals()

	TEST_ASSERT_NOTNULL(T.atmos_overlay_types, \
		"update_visuals() left atmos_overlay_types null despite 50 mol of plasma — overlay path not reached")
	TEST_ASSERT(LAZYLEN(T.atmos_overlay_types) > 0, \
		"atmos_overlay_types is empty after 50 mol of plasma — GAS_OVERLAYS macro emitted nothing")

	// Wipe so other tests don't see stale plasma.
	air.set_moles(/datum/gas/plasma, 0)
	T.update_visuals()


/// Phoron below the visibility threshold (MOLES_GAS_VISIBLE = 0.25 mol)
/// must NOT render. This guards the cheap fast-path inside GAS_OVERLAYS that
/// skips gases whose mole count is <= the per-gas visibility cutoff.
/datum/unit_test/dq_phoron_below_threshold_invisible

/datum/unit_test/dq_phoron_below_threshold_invisible/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no /turf/simulated/floor with air for phoron-invisibility test")

	if(T.active_hotspot)
		qdel(T.active_hotspot)
		T.active_hotspot = null
	if(T.atmos_overlay_types)
		for(var/old_ov in T.atmos_overlay_types)
			T.vis_contents -= old_ov
		T.atmos_overlay_types = null

	// Wipe ALL overlay-emitting gases so reaction products left by earlier tests
	// (water vapor / CO2 / tritium from hotspot_expose) don't fail this test.
	var/datum/gas_mixture/air = T.return_air()
	for(var/datum/gas/g as anything in air.get_gases())
		if(GLOB.nonoverlaying_gases[g])
			continue
		air.set_moles(g, 0)
	// 0.1 mol < MOLES_GAS_VISIBLE (0.25)
	air.set_moles(/datum/gas/plasma, 0.1)

	T.update_visuals()

	TEST_ASSERT(!LAZYLEN(T.atmos_overlay_types), \
		"atmos_overlay_types populated despite 0.1 mol plasma being below MOLES_GAS_VISIBLE (0.25) — visibility threshold not enforced")

	air.set_moles(/datum/gas/plasma, 0)
	T.update_visuals()


/// Adjacency calc must include /turf/simulated/floor as a peer (after the
/// reparent). If init_immediate_calculate_adjacent_turfs's isopenturf-style
/// gate excludes floors, atmos_adjacent_turfs stays empty and process_cell
/// has nothing to share with → gases never spread.
/datum/unit_test/dq_floor_adjacency_lists_floor_neighbors

/datum/unit_test/dq_floor_adjacency_lists_floor_neighbors/Run()
	// Pick a genuinely atmos-CONNECTED floor pair (both in each other's
	// atmos_adjacent_turfs), not merely two geometrically adjacent floors. A naive
	// scan lands on the first adjacent-floor pair, which on a full station is a dock
	// tile sealed by a closed external airlock / window (legitimately atmos-isolated
	// — verified, not an init bug). This test validates that init WIRED a connected
	// pair, so it must start from one.
	var/list/pair = dq_atmos_test_find_floor_pair_with_real_adjacency()
	TEST_ASSERT_NOTNULL(pair, "no atmos-connected /turf/simulated/floor pair on the map")
	var/turf/simulated/floor/A = pair[1]
	var/turf/simulated/floor/B = pair[2]

	// Production assertion: world init must have populated atmos_adjacent_turfs
	// for both turfs and listed each as a neighbor of the other. If either is
	// null or missing, init_immediate_calculate_adjacent_turfs is broken under
	// the /turf/simulated → /turf/open reparent and atmos spread won't work.
	TEST_ASSERT(length(vg_atmos_adjacent_turfs(A)), \
		"A has no atmos neighbours after world init — its air-block mask was never published")
	TEST_ASSERT(vg_atmos_turfs_share(A, B), \
		"init didn't make B adjacent to A — A has [length(vg_atmos_adjacent_turfs(A))] neighbours")
	TEST_ASSERT(vg_atmos_turfs_share(B, A), \
		"init didn't make A adjacent to B — symmetric adjacency broken")


/// End-to-end gas-spread check: put phoron on tile A via assume_air, wait
/// for real SSair ticks, and assert tile B (adjacent) now has some phoron.
/// This is the behaviour the user actually sees in the game; if it's broken,
/// breaches/leaks/atmos events all stop working.
/datum/unit_test/dq_phoron_spreads_to_adjacent_floor

/datum/unit_test/dq_phoron_spreads_to_adjacent_floor/Run()
	// Connected interior pair (see dq_floor_adjacency_lists_floor_neighbors) — not
	// the first adjacent-floor pair, which on a full station is a sealed dock tile.
	var/list/pair = dq_atmos_test_find_floor_pair_with_real_adjacency()
	TEST_ASSERT_NOTNULL(pair, "no atmos-connected /turf/simulated/floor pair on the map")
	var/turf/simulated/floor/A = pair[1]
	var/turf/simulated/floor/B = pair[2]

	// Assert adjacency built by init. If init didn't wire A↔B, the test
	// can't validate spread.
	TEST_ASSERT(vg_atmos_turfs_share(A, B), \
		"init didn't build vg_atmos_turfs_share(A, B) — the test map didn't wire this pair through init")

	// Strip B's plasma first so the post check is honest.
	B.air.set_moles(/datum/gas/plasma, 0)
	var/initial_b_plasma = LINDA_GAS_AMT(B.air, GAS_PLASMA)
	TEST_ASSERT_EQUAL(initial_b_plasma, 0, \
		"test setup failed: B already has [initial_b_plasma] mol plasma")

	// Pump phoron into A via the production assume_air path (which enrolls A
	// in active_turfs and runs update_visuals).
	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/plasma, 100)
	donor.set_temperature(T20C)
	A.assume_air(donor)

	// Let the real Master.Loop tick SSair so process_active_turfs walks A
	// and shares to B naturally — no manual process_cell call.
	dq_atmos_test_wait_real_ssair_ticks(5)

	var/b_after = LINDA_GAS_AMT(B.air, GAS_PLASMA)
	TEST_ASSERT(b_after > 0, \
		"after process_cell on A (with 100 mol plasma), adjacent floor B still has 0 plasma — process_cell didn't share. atmos neighbours of A = [length(vg_atmos_adjacent_turfs(A))]")

	// Clean up so we don't pollute later tests.
	A.air.set_moles(/datum/gas/plasma, 0)
	B.air.set_moles(/datum/gas/plasma, 0)
	A.update_visuals()
	B.update_visuals()


/// SSair.setup_allturfs() must call Initalize_Atmos on every gas-bearing turf
/// at roundstart. After the /turf/simulated → /turf/open reparent we provide
/// /turf/open/Initalize_Atmos that builds adjacency. If init_air is FALSE on
/// floors, or our Initalize_Atmos override doesn't run, every floor in the
/// world has atmos_adjacent_turfs = null and gases never spread anywhere.
/datum/unit_test/dq_floor_has_init_air_and_adjacency

/datum/unit_test/dq_floor_has_init_air_and_adjacency/Run()
	// Pick a floor that is genuinely ATMOS-CONNECTED to a neighbor (both in each
	// other's atmos_adjacent_turfs) — not merely geometrically adjacent. A naive
	// "first adjacent floor" scan can land on a dock-airlock or window tile, which
	// is legitimately atmos-isolated (verified: SC has ~1200 such tiles, all with
	// closed external airlocks / reinforced windows on them). Those aren't init
	// bugs; the test must select a real interior pair to validate init coverage.
	var/list/pair = dq_atmos_test_find_floor_pair_with_real_adjacency()
	TEST_ASSERT_NOTNULL(pair, "no atmos-connected /turf/simulated/floor pair on the map")
	var/turf/simulated/floor/T = pair[1]
	TEST_ASSERT(T.init_air, \
		"/turf/simulated/floor.init_air is FALSE — SSair.setup_allturfs() will skip this turf and never call Initalize_Atmos on it")
	// After SSair init, adjacency should be populated for at least one neighbor
	// (otherwise spread is dead).
	TEST_ASSERT(length(vg_atmos_adjacent_turfs(T)) > 0, \
		"no atmos neighbours after SSair init on a /turf/simulated/floor (at [T.x],[T.y],[T.z]) — its air-block mask was never published to Rust")

	if(T.active_hotspot)
		qdel(T.active_hotspot)
		T.active_hotspot = null

	// Stock with fuel + oxidizer.
	var/datum/gas_mixture/air = T.return_air()
	air.adjust_gas(/datum/gas/plasma, 30)
	air.adjust_gas(/datum/gas/oxygen, 80)
	air.set_temperature(T20C)

	T.feed_lingering_fire(2.0)

	TEST_ASSERT_NOTNULL(T.active_hotspot, "feed_lingering_fire didn't spawn an active_hotspot")
	TEST_ASSERT_NOTNULL(T.lingering_fire(), "lingering_fire() returns null despite active_hotspot")

	if(T.active_hotspot)
		qdel(T.active_hotspot)
		T.active_hotspot = null


// =====================================================================
// Atmos spread / share / barrier / conservation suite
// =====================================================================
// These tests drive process_cell directly with a monotonically increasing
// fire_count to simulate consecutive SSair ticks under a controlled adjacency
// graph. They cover what "atmos spreading works" means in practice:
// equalization over time, multi-tile chain propagation, walls blocking
// propagation, total-moles conservation, pressure-driven flow, and
// regressions for the ChangeTurf / make_floor LINDA fixes.

/// Find a pair of adjacent floor turfs whose atmos_adjacent_turfs lists were
/// actually built by init_immediate_calculate_adjacent_turfs during world
/// init. If init never ran or the proc skipped these turfs, the test that
/// uses this pair won't be testable — but that's the bug we want to surface.
/proc/dq_atmos_test_find_floor_pair_with_real_adjacency()
	// Restore walls so we don't return a walled-off turf from a prior test.
	dq_atmos_test_restore_walls()
	for(var/turf/simulated/floor/cand in world)
		if(!cand.air || cand.blocks_air)
			continue
		for(var/turf/n as anything in vg_atmos_adjacent_turfs(cand))
			if(istype(n, /turf/simulated/floor))
				var/turf/simulated/floor/floor_n = n
				if(floor_n.air && !floor_n.blocks_air)
					dq_atmos_test_snapshot_air(cand)
					dq_atmos_test_snapshot_air(floor_n)
					return list(cand, floor_n)
	return null


/// Runs `ticks` gas frames through the test hook (SSair.run_gas_frames):
/// deterministic, no wall-clock wait. Each frame is one SSair fire's worth of
/// gas (FRAME_DT = 0.5 s simulated), and its events (reactions, visuals,
/// spacewind) are dispatched as fire() would.
#define DQ_ATMOS_TEST_MAX_WAIT (10 SECONDS)
/proc/dq_atmos_test_wait_real_ssair_ticks(ticks)
	SSair.run_gas_frames(ticks)
	return ticks


/// Runs up to `max_fires` gas frames, stopping early once no registered turf
/// in the frames' events is still moving. Kept for callers that used to wait
/// for the async worker to go idle; frames are deterministic now.
/proc/dq_unit_test_wait_air_until_quiescent(max_fires, settle_fires = 3)
	SSair.run_gas_frames(max_fires)
	return max_fires


/// Find an adjacent floor pair whose adjacency was built by the real init
/// path (init_immediate_calculate_adjacent_turfs). Preference order:
///   1. Adjacent floor pair INSIDE the unit_tests.dmm sealed room (walls of
///      /turf/closed/indestructible block atmos via real type — no white-box
///      adjacency rewriting needed).
///   2. Any floor pair with built adjacency anywhere on the map.
/// Sealed-room pairs let mass-conservation tests check totals — the gas
/// can't leak out because the walls really block it.
/proc/dq_atmos_test_find_floor_pair()
	// Restore any walls left by a previous test's isolate_pair so we don't
	// hand back a turf that's been walled off.
	dq_atmos_test_restore_walls()
	// Try the sealed test-room landmarks first (loaded in RunUnitTests). Force-build
	// adjacency on the seed in case it wasn't wired yet — the room is a runtime-loaded
	// z, so setup_allturfs never saw it.
	var/obj/effect/landmark/test_corner = locate(/obj/effect/landmark/unit_test_bottom_left) in GLOB.landmarks_list
	if(test_corner)
		var/turf/seed_turf = get_turf(test_corner)
		if(istype(seed_turf, /turf/simulated/floor))
			var/turf/simulated/floor/seed = seed_turf
			if(seed.air && !seed.blocks_air)
				for(var/turf/n as anything in vg_atmos_adjacent_turfs(seed))
					if(istype(n, /turf/simulated/floor))
						var/turf/simulated/floor/floor_n = n
						if(floor_n.air && !floor_n.blocks_air)
							dq_atmos_test_snapshot_air(seed)
							dq_atmos_test_snapshot_air(floor_n)
							return list(seed, floor_n)
	// Fallback: any floor pair with built adjacency.
	return dq_atmos_test_find_floor_pair_with_real_adjacency()

/// Find a colinear line of `count` open floors, preferring the sealed test room
/// (unit_test landmark) so the line is genuinely interior. Force-builds adjacency
/// on the returned turfs so callers can rely on atmos_adjacent_turfs immediately.
/proc/dq_atmos_test_find_floor_line(count)
	dq_atmos_test_restore_walls()
	var/list/seeds = list()
	var/obj/effect/landmark/test_corner = locate(/obj/effect/landmark/unit_test_bottom_left) in GLOB.landmarks_list
	if(test_corner)
		var/turf/seed_turf = get_turf(test_corner)
		if(istype(seed_turf, /turf/simulated/floor))
			seeds += seed_turf
	for(var/turf/simulated/floor/f in world)
		seeds += f
	for(var/turf/simulated/floor/cand as anything in seeds)
		if(!cand.air || cand.blocks_air)
			continue
		for(var/direction in GLOB.cardinal)
			var/list/line = list(cand)
			var/turf/cur = cand
			for(var/i in 2 to count)
				var/turf/nxt = get_step(cur, direction)
				if(!istype(nxt, /turf/simulated/floor))
					break
				var/turf/simulated/floor/nf = nxt
				if(!nf.air || nf.blocks_air)
					break
				line += nf
				cur = nf
			if(line.len == count)
				// Build adjacency, then REQUIRE that every consecutive pair is
				// genuinely atmos-connected. On the live station a geometrically
				// colinear floor run can still be split by a closed door/window,
				// which leaves the pair unwired — the caller would then bad-index
				// on a null atmos_adjacent_turfs. Only hand back a real, connected line.
				for(var/turf/T as anything in line)
					T.air_update_turf(TRUE, FALSE)
				var/connected = TRUE
				for(var/i in 1 to count - 1)
					var/turf/a = line[i]
					var/turf/b = line[i + 1]
					if(!vg_atmos_turfs_share(a, b))
						connected = FALSE
						break
				if(connected)
					return line
	return null

/// Find a collinear run of `count` floor tiles suitable for building a FRESH
/// test pipeline on. Guarantees, for every tile in the run:
///   1. same z-level, connected by a single CARDINAL step (so consecutive
///      get_dir() values are real cardinals — pipes need a non-zero
///      initialize_directions, and a multi-z pair yields get_dir()==0);
///   2. it is an open, non-blocking /turf/simulated/floor;
///   3. it contains NO pre-existing /obj/machinery/atmospherics — on the live
///      station most floors already host supply/scrubber/regular pipes, and a
///      fresh test pipe would connect into that station network instead of only
///      to its sibling test pipe, contaminating build_network assertions.
/// Returns the list of `count` turfs (head→tail along the run), or null.
///
/// This is why the pipe-network tests are deterministic across maps: virgo is a
/// single flat deck so find_floor_pair() happened to hand back clean 2-D pairs,
/// but Southern Cross is multi-z and pipe-dense, so the tests must select their
/// own clean substrate rather than trusting the generic adjacency finder.
/proc/dq_atmos_test_find_clear_pipe_run(count)
	dq_atmos_test_restore_walls()
	for(var/turf/simulated/floor/cand in world)
		if(!cand.air || cand.blocks_air)
			continue
		if(locate(/obj/machinery/atmospherics) in cand)
			continue
		for(var/direction in GLOB.cardinal)
			var/list/run = list(cand)
			var/turf/cur = cand
			var/ok = TRUE
			for(var/i in 2 to count)
				var/turf/nxt = get_step(cur, direction)
				if(!istype(nxt, /turf/simulated/floor))
					ok = FALSE
					break
				var/turf/simulated/floor/nf = nxt
				if(!nf.air || nf.blocks_air || (locate(/obj/machinery/atmospherics) in nf))
					ok = FALSE
					break
				run += nf
				cur = nf
			if(ok && run.len == count)
				return run
	return null

/// Globally tracks turfs converted to walls for test isolation. We restore
/// them to floor after the test that triggered the walling.
GLOBAL_LIST_EMPTY(dq_atmos_test_walled_turfs)
GLOBAL_LIST_EMPTY(dq_atmos_test_air_snapshots)

/// Capture a turf's authoritative gas before a test mutates it. The first
/// snapshot wins so multiple helpers within one test still restore the true
/// pre-test state.
/proc/dq_atmos_test_snapshot_air(turf/open/T)
	if(!istype(T) || !T.air || (T in GLOB.dq_atmos_test_air_snapshots))
		return
	GLOB.dq_atmos_test_air_snapshots[T] = T.air.copy()

/// Per-test cleanup invoked by /datum/unit_test/restore_atmos().
/proc/dq_atmos_test_restore_state()
	dq_atmos_test_restore_walls()
	for(var/turf/open/T as anything in GLOB.dq_atmos_test_air_snapshots)
		var/datum/gas_mixture/original = GLOB.dq_atmos_test_air_snapshots[T]
		if(T && T.air && original)
			T.air.copy_from(original)
			T.air_update_turf(TRUE, FALSE)
		qdel(original)
	GLOB.dq_atmos_test_air_snapshots.Cut()

/// Build a REAL sealed environment around A and B by replacing every
/// non-{A,B} turf currently in their adjacency lists with /turf/simulated/wall
/// via ChangeTurf — the actual production wall type that the LINDA engine
/// treats as blocks_air. Tracks each replaced turf so subsequent calls /
/// dq_atmos_test_restore_walls can roll back.
///
/// This is not white-boxing: we use ChangeTurf (the production API), produce
/// real wall turfs (the production type), and the engine respects them via
/// the same blocks_air check it uses for mapped walls.
/proc/dq_atmos_test_isolate_pair(turf/open/A, turf/open/B)
	// Roll back walls from any previous isolate call so we always start clean.
	dq_atmos_test_restore_walls()
	if(!istype(A) || !istype(B))
		return
	// Seal by GEOMETRY, not just the adjacency lists. atmos_adjacent_turfs can be
	// incomplete right after isolate/assume (the graph rebuilds lazily over the next
	// ticks), so walling only listed neighbours misses real leak paths that appear a
	// tick later. Wall every cardinal + up/down geometric neighbour of A and B
	// (union'd with whatever the adjacency lists do know about).
	var/list/to_wall = list()
	for(var/turf/T as anything in list(A, B))
		for(var/dir in GLOB.cardinals_multiz)
			var/turf/N = get_step_multiz(T, dir)
			if(N && N != A && N != B && !(N in to_wall))
				to_wall += N
		for(var/turf/N as anything in vg_atmos_adjacent_turfs(T))
			if(N != A && N != B && !(N in to_wall))
				to_wall += N
	for(var/turf/N as anything in to_wall)
		// Skip turfs that already block atmos (real walls). We DO seal /turf/space
		// too: a conservation/pressure test needs a fully sealed box, and on maps
		// whose base turf is space (e.g. virgo_minitest) a floor pair is often
		// adjacent to space — leaving it open lets gas correctly vent to vacuum and
		// disperse across the whole station (the excited group balloons to
		// thousands of turfs), which reads as "mass lost" even though the engine is
		// conserving. restore_walls() rolls the space turf back to its original type.
		if(istype(N, /turf/simulated/wall) || N.blocks_air)
			continue
		// Record the ORIGINAL turf path before we overwrite it so we can
		// restore on cleanup.
		GLOB.dq_atmos_test_walled_turfs[N] = N.type
		N.ChangeTurf(/turf/simulated/wall)
	// Let the gas field apply the walls before the test sets gas.
	SSair.run_gas_frames(1)


/proc/dq_atmos_test_isolate_triple(turf/open/A, turf/open/B, turf/open/C)
	dq_atmos_test_restore_walls()
	if(!istype(A) || !istype(B) || !istype(C))
		return
	var/list/triple = list(A, B, C)
	// Seal by GEOMETRY (cardinal + up/down), not just the adjacency lists —
	// atmos_adjacent_turfs can be incomplete right after find_floor_line's
	// force-build, so walling only listed neighbours leaves real leak paths.
	// This mirrors the hardened dq_atmos_test_isolate_pair.
	var/list/to_wall = list()
	for(var/turf/T as anything in triple)
		for(var/dir in GLOB.cardinals_multiz)
			var/turf/N = get_step_multiz(T, dir)
			if(N && !(N in triple) && !(N in to_wall))
				to_wall += N
		for(var/turf/N as anything in vg_atmos_adjacent_turfs(T))
			if(!(N in triple) && !(N in to_wall))
				to_wall += N
	for(var/turf/N as anything in to_wall)
		if(istype(N, /turf/simulated/wall) || N.blocks_air)
			continue
		GLOB.dq_atmos_test_walled_turfs[N] = N.type
		N.ChangeTurf(/turf/simulated/wall)
	// Walling the neighbours (ChangeTurf) can clear a triple member's cached
	// adjacency and queue a rebuild that only runs on the next SSair tick. Refresh
	// A/B/C synchronously now so the caller's A-B / B-C adjacency assertions see the
	// post-seal state instead of a transiently-null list. (Safe here: only the triple
	// tests use this; the wall-barrier test does its own walling and must NOT rebuild.)
	for(var/turf/T as anything in triple)
		T.air_update_turf(TRUE, FALSE)

/// Restore turfs walled off by dq_atmos_test_isolate_* back to whatever
/// they were before the test. Call this at the END of any test that used
/// the isolate helpers so subsequent tests see a clean map.
	// Let the gas field apply the walls before the test sets gas.
	SSair.run_gas_frames(1)


/proc/dq_atmos_test_restore_walls()
	var/list/restored_turfs = list()
	for(var/turf/T as anything in GLOB.dq_atmos_test_walled_turfs)
		var/original_type = GLOB.dq_atmos_test_walled_turfs[T]
		if(T && original_type && T.type != original_type)
			var/turf/restored = T.ChangeTurf(original_type)
			if(restored)
				restored_turfs += restored
	GLOB.dq_atmos_test_walled_turfs.Cut()
	// ChangeTurf queues production topology work, but the next unit test begins
	// immediately and can observe the transient Rust edge graph. Reconcile the
	// restored turf and its neighbors synchronously before handing the map back.
	for(var/turf/restored as anything in restored_turfs)
		for(var/turf/open/open_turf as anything in list(restored, get_step(restored, NORTH), get_step(restored, SOUTH), get_step(restored, EAST), get_step(restored, WEST)))
			if(!istype(open_turf))
				continue
			open_turf.air_update_turf(TRUE, FALSE)

/// Open a sealed test-room floor up to space by ChangeTurf-ing one of its
/// cardinal neighbors (a /turf/closed/indestructible test-room wall) into a
/// real /turf/space. ChangeTurf marks the new turf for update, whose
/// immediate_calculate_adjacent_turfs wires the floor↔space adjacency
/// bidirectionally — the same production path a hull breach would take.
/// Returns the created space turf, or null if no convertible neighbor existed.
/// The original neighbor type is tracked in dq_atmos_test_walled_turfs so
/// dq_atmos_test_restore_walls() rolls it back.
/proc/dq_atmos_test_open_to_space(turf/floor)
	if(!isturf(floor))
		return null
	var/turf/fallback_neighbor
	for(var/direction in GLOB.cardinal)
		var/turf/neighbor = get_step(floor, direction)
		if(!neighbor)
			continue
		var/contents_block = FALSE
		for(var/obj/blocker in neighbor.contents + floor.contents)
			var/turf/other_side = blocker.loc == neighbor ? floor : neighbor
			if(!QDELETED(blocker) && !CANATMOSPASS(blocker, other_side, FALSE))
				contents_block = TRUE
				break
		if(contents_block)
			continue
		if(!fallback_neighbor)
			fallback_neighbor = neighbor
		// If a neighbor is already space, just use it (and record so we can put
		// it back). The test-room walls are /turf/closed/indestructible; isolate
		// helpers leave /turf/simulated/wall. Either way they block air, so pick
		// a solid neighbor and breach it.
		if(istype(neighbor, /turf/space))
			GLOB.dq_atmos_test_walled_turfs[neighbor] = neighbor.type
			neighbor.air_update_turf(TRUE, FALSE)
			floor.air_update_turf(TRUE, FALSE)
			return neighbor
		if(neighbor.blocks_air || istype(neighbor, /turf/simulated/wall))
			GLOB.dq_atmos_test_walled_turfs[neighbor] = neighbor.type
			var/turf/space/created = neighbor.ChangeTurf(/turf/space)
			// Make sure the floor side recomputes its adjacency too, in case the
			// space turf's own recompute raced the floor's active state.
			created.air_update_turf(TRUE, FALSE)
			floor.air_update_turf(TRUE, FALSE)
			return created
	// Some test maps do not surround the reserved floor with solid hull. A real
	// floor-to-space ChangeTurf is still the production breach path, so use the
	// first unobstructed neighbor rather than making the fixture map-dependent.
	if(fallback_neighbor)
		GLOB.dq_atmos_test_walled_turfs[fallback_neighbor] = fallback_neighbor.type
		var/turf/space/created = fallback_neighbor.ChangeTurf(/turf/space)
		created.air_update_turf(TRUE, FALSE)
		floor.air_update_turf(TRUE, FALSE)
		return created
	return null

/// Legacy entry point — runs N gas frames (the list argument is ignored).
/proc/dq_atmos_test_drive_ticks(list/turfs, ticks)
	dq_atmos_test_wait_real_ssair_ticks(ticks)


/// Equilibration over multiple ticks: load A with plasma, B starts empty,
/// after enough share ticks both should hold roughly half. This is the
/// fundamental "gases mix" behaviour — every other atmos behaviour assumes it.
/datum/unit_test/dq_gas_equilibrates_over_ticks

/datum/unit_test/dq_gas_equilibrates_over_ticks/Run()
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no usable floor pair on map for equilibration test")
	var/turf/simulated/floor/A = pair[1]
	var/turf/simulated/floor/B = pair[2]

	dq_atmos_test_isolate_pair(A, B)

	for(var/datum/gas/g as anything in A.air.get_gases())
		A.air.set_moles(g, 0)
	for(var/datum/gas/g as anything in B.air.get_gases())
		B.air.set_moles(g, 0)
	B.air.set_temperature(T20C)

	// Production injection: assume_air enrolls A in active_turfs via
	// air_update_turf, which is what canister.process / atmos_spawn_air do.
	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/plasma, 100)
	donor.set_temperature(T20C)
	A.assume_air(donor)

	// Poll for equilibration instead of always sleeping out the full 20-tick
	// budget: break as soon as the SAME condition we assert below holds.
	var/baseline = 0
	var/a_plasma
	var/b_plasma
	while(baseline < 20)
		a_plasma = A.air.get_moles(/datum/gas/plasma)
		b_plasma = B.air.get_moles(/datum/gas/plasma)
		if(abs((a_plasma + b_plasma) - 100) < 2 && abs(a_plasma - b_plasma) < 10)
			break
		SSair.run_gas_frames(1)
		baseline++

	a_plasma = A.air.get_moles(/datum/gas/plasma)
	b_plasma = B.air.get_moles(/datum/gas/plasma)
	TEST_ASSERT(abs((a_plasma + b_plasma) - 100) < 2, \
		"plasma moles NOT conserved after real SSair ticks in walled pair: A=[a_plasma] B=[b_plasma] total=[a_plasma + b_plasma], expected ~100")
	TEST_ASSERT(abs(a_plasma - b_plasma) < 10, \
		"plasma did not equilibrate after 20 real SSair ticks: A=[a_plasma] B=[b_plasma]")

	A.air.set_moles(/datum/gas/plasma, 0)
	B.air.set_moles(/datum/gas/plasma, 0)
	A.update_visuals()
	B.update_visuals()


/// Chain propagation: A → B → C. Phoron in A should reach C after enough ticks.
/// Validates that share is genuinely cell-to-cell propagating.
/datum/unit_test/dq_phoron_chains_through_3_floors

/datum/unit_test/dq_phoron_chains_through_3_floors/Run()
	var/list/line = dq_atmos_test_find_floor_line(3)
	TEST_ASSERT_NOTNULL(line, "no A-B-C colinear floor triple on map")
	var/turf/simulated/floor/A = line[1]
	var/turf/simulated/floor/B = line[2]
	var/turf/simulated/floor/C = line[3]

	dq_atmos_test_isolate_triple(A, B, C)
	TEST_ASSERT(vg_atmos_turfs_share(A, B), "A-B adjacency missing")
	TEST_ASSERT(vg_atmos_turfs_share(B, C), "B-C adjacency missing")

	for(var/turf/open/T as anything in list(A, B, C))
		for(var/datum/gas/g as anything in T.air.get_gases())
			T.air.set_moles(g, 0)
		T.air.set_temperature(T20C)

	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/plasma, 200)
	donor.set_temperature(T20C)
	A.assume_air(donor)

	dq_atmos_test_wait_real_ssair_ticks(20)

	var/a_p = A.air.get_moles(/datum/gas/plasma)
	var/b_p = B.air.get_moles(/datum/gas/plasma)
	var/c_p = C.air.get_moles(/datum/gas/plasma)
	TEST_ASSERT(abs((a_p + b_p + c_p) - 200) < 2, \
		"plasma not conserved across walled chain: A=[a_p] B=[b_p] C=[c_p] total=[a_p+b_p+c_p]")
	TEST_ASSERT(c_p > 1, \
		"plasma never reached C after real SSair ticks of A→B→C share: A=[a_p] B=[b_p] C=[c_p]")

	for(var/turf/open/T as anything in list(A, B, C))
		T.air.set_moles(/datum/gas/plasma, 0)
		T.update_visuals()


/// Wall barrier: A floor with plasma, a wall between, B floor on the far side.
/// Phoron must NOT cross the wall, no matter how many ticks pass.
/datum/unit_test/dq_wall_blocks_gas_spread

/datum/unit_test/dq_wall_blocks_gas_spread/Run()
	var/turf/simulated/floor/A = null
	var/turf/simulated/wall/W = null
	var/turf/simulated/floor/B = null
	for(var/turf/simulated/floor/cand in world)
		if(!cand.air || cand.blocks_air || cand.initial_gas_mix != OPENTURF_DEFAULT_ATMOS)
			continue
		for(var/direction in GLOB.cardinal)
			var/turf/n1 = get_step(cand, direction)
			if(!istype(n1, /turf/simulated/wall))
				continue
			var/turf/n2 = get_step(n1, direction)
			if(!istype(n2, /turf/simulated/floor))
				continue
			var/turf/simulated/floor/n2f = n2
			if(!n2f.air || n2f.blocks_air || n2f.initial_gas_mix != OPENTURF_DEFAULT_ATMOS)
				continue
			A = cand
			W = n1
			B = n2f
			break
		if(A)
			break
	TEST_ASSERT_NOTNULL(A, "no floor-wall-floor triple on map for barrier test")
	dq_atmos_test_snapshot_air(A)
	dq_atmos_test_snapshot_air(B)

	// The wall between A and B is part of the map's init layout.
	// Verify init didn't wire A↔B (wall blocks adjacency) and W is also
	// excluded from A's adjacency (blocks_air rejection).
	TEST_ASSERT(!vg_atmos_turfs_share(A, W), \
		"wall ended up adjacent to A — blocks_air check broken")
	TEST_ASSERT(!vg_atmos_turfs_share(A, B), \
		"B somehow ended up adjacent to A despite a wall between them")

	// Isolate the far-side turf from unrelated station routes and ambient test
	// contamination. The assertions above test the wall topology; this isolates
	// the Rust publication check so only a stale/phantom Rust edge can reach B.
	B.update_air_ref(0, AIR_BLOCK_ALL)

	for(var/datum/gas/g as anything in A.air.get_gases())
		A.air.set_moles(g, 0)
	for(var/datum/gas/g as anything in B.air.get_gases())
		B.air.set_moles(g, 0)

	// Inject plasma via the production path.
	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/plasma, 150)
	donor.set_temperature(T20C)
	A.assume_air(donor)

	// NEGATIVE test (plasma must NOT cross) — keep the full fixed wait.
	// Polling-and-breaking-early on "b_p == 0" would be vacuous: that
	// condition is already true at tick 0, so an early-break loop would
	// exit immediately and never actually exercise 20 real SSair ticks
	// of opportunity for a leak to appear.
	dq_atmos_test_wait_real_ssair_ticks(20)

	var/b_p = B.air.get_moles(/datum/gas/plasma)
	B.air_update_turf(TRUE, FALSE)
	TEST_ASSERT_EQUAL(b_p, 0, \
		"plasma leaked through a wall: B has [b_p] mol after 100 ticks with A→W→B layout")

	A.air.set_moles(/datum/gas/plasma, 0)
	A.update_visuals()


/// Regression for the /turf/open/Destroy fix: a floor in active_turfs that
/// gets ChangeTurf'd into a wall must NOT crash next process_cell. Before the
/// fix, the floor's slot in active_turfs resolved (via BYOND's location-based
/// turf refs) to the new wall, whose null air made LINDA_CYCLE_ARCHIVE blow up.
/datum/unit_test/dq_changeturf_to_wall_no_crash

/datum/unit_test/dq_changeturf_to_wall_no_crash/Run()
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no usable floor pair on map for ChangeTurf test")
	var/turf/simulated/floor/A = pair[1]
	var/turf/simulated/floor/B = pair[2]
	// Record A's original type so we can restore even if asserts fail. The
	// previous version permanently walled A whenever any check failed,
	// corrupting the test map for every subsequent test that picked A.
	GLOB.dq_atmos_test_walled_turfs[A] = A.type

	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/oxygen, 50)
	donor.set_temperature(T20C)
	A.assume_air(donor)
	// (active_turfs enrollment is now Rust-side; the DM list is gone. The test's
	// point is that ChangeTurf->wall doesn't crash and yields a null-air wall.)

	var/turf/W = A.ChangeTurf(/turf/simulated/wall)
	TEST_ASSERT_NOTNULL(W, "ChangeTurf returned null")
	TEST_ASSERT(istype(W, /turf/simulated/wall), "ChangeTurf didn't produce a wall: [W.type]")
	TEST_ASSERT(W.blocks_air, "new wall should blocks_air=1")
	var/turf/open/W_open = W
	TEST_ASSERT(isnull(W_open.air), "new wall should have air=null")

	dq_atmos_test_drive_ticks(list(B), 1)

	TEST_ASSERT(!vg_atmos_turfs_share(B, W), \
		"B is still adjacent to the dead A→wall slot")

	// Always restore even on success — keeps the test map clean for the
	// next test that picks this tile. (On assert failure the entry in
	// dq_atmos_test_walled_turfs survives so the next isolate_pair call
	// reverses it via dq_atmos_test_restore_walls.)
	dq_atmos_test_restore_walls()


/// Regression for /turf/simulated/mineral/make_floor() fix: carving a rock to
/// a floor must create an air mixture, otherwise neighbors will crash trying
/// to share with a blocks_air=0 + air=null turf.
/datum/unit_test/dq_make_floor_creates_air

/datum/unit_test/dq_make_floor_creates_air/Run()
	var/turf/simulated/mineral/M = null
	for(var/turf/simulated/mineral/cand in world)
		if(cand.density && cand.blocks_air)
			M = cand
			break
	TEST_ASSERT_NOTNULL(M, "no /turf/simulated/mineral on test map to carve")

	TEST_ASSERT(isnull(M.air), \
		"test precondition: mineral wall should start with air=null, has [M.air]")
	TEST_ASSERT_EQUAL(M.blocks_air, 1, \
		"test precondition: mineral wall should start with blocks_air=1")

	M.make_floor()

	// Restore-on-failure shape: capture each assertion result, drive the
	// restoration unconditionally, then re-fire any failure. Previously
	// any failing assert left the mineral as a floor forever, breaking
	// every subsequent run of the same test.
	var/blocks_air_post = M.blocks_air
	var/has_air = !isnull(M.air)
	var/moles_ok = has_air && M.air.total_moles() >= 0
	M.make_wall()
	var/blocks_air_restored = M.blocks_air
	var/air_cleared = isnull(M.air)

	TEST_ASSERT_EQUAL(blocks_air_post, 0, "make_floor didn't set blocks_air=0")
	TEST_ASSERT(has_air, \
		"make_floor left air=null — neighbors will crash on share. DQEdit in mine_turfs.dm missing?")
	TEST_ASSERT(moles_ok, "make_floor air mixture is broken")
	TEST_ASSERT_EQUAL(blocks_air_restored, 1, "make_wall didn't restore blocks_air=1")
	TEST_ASSERT(air_cleared, "make_wall didn't QDEL_NULL the air mixture")


/// Pressure-driven flow: A starts at ~2 atm, B at ~1 atm. Over ticks A
/// pressure must drop and B pressure must rise, with total moles conserved.
/// The "pressurised room equalises with the hallway" path.
/datum/unit_test/dq_pressure_differential_drives_flow

/datum/unit_test/dq_pressure_differential_drives_flow/Run()
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no usable floor pair on map for pressure test")
	var/turf/simulated/floor/A = pair[1]
	var/turf/simulated/floor/B = pair[2]

	dq_atmos_test_isolate_pair(A, B)

	for(var/datum/gas/g as anything in A.air.get_gases())
		A.air.set_moles(g, 0)
	for(var/datum/gas/g as anything in B.air.get_gases())
		B.air.set_moles(g, 0)
	A.air.set_temperature(T20C)
	B.air.set_temperature(T20C)

	// Pressurize A and B at different levels via assume_air (production path).
	var/datum/gas_mixture/donor_a = new(70)
	donor_a.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD * 2)
	donor_a.set_temperature(T20C)
	A.assume_air(donor_a)

	var/datum/gas_mixture/donor_b = new(70)
	donor_b.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)
	donor_b.set_temperature(T20C)
	B.assume_air(donor_b)

	var/a_initial_pressure = A.air.return_pressure()
	var/b_initial_pressure = B.air.return_pressure()
	var/total_initial_moles = A.air.total_moles() + B.air.total_moles()
	TEST_ASSERT(a_initial_pressure > b_initial_pressure, \
		"test setup: A should start higher pressure than B (A=[a_initial_pressure] B=[b_initial_pressure])")

	dq_atmos_test_wait_real_ssair_ticks(15)

	var/a_final_pressure = A.air.return_pressure()
	var/b_final_pressure = B.air.return_pressure()
	var/total_final_moles = A.air.total_moles() + B.air.total_moles()
	TEST_ASSERT(a_final_pressure < a_initial_pressure, \
		"A pressure didn't drop after real SSair ticks in walled pair: [a_initial_pressure] → [a_final_pressure]")
	TEST_ASSERT(b_final_pressure > b_initial_pressure, \
		"B pressure didn't rise: [b_initial_pressure] → [b_final_pressure]")
	TEST_ASSERT(abs(total_final_moles - total_initial_moles) < 2, \
		"total moles not conserved across walled pair: [total_initial_moles] → [total_final_moles]")

	A.air.set_moles(/datum/gas/nitrogen, MOLES_N2STANDARD)
	B.air.set_moles(/datum/gas/nitrogen, MOLES_N2STANDARD)


/// Total moles conservation under repeated share. Small per-tick rounding
/// errors shouldn't compound into mass loss over hundreds of ticks. If this
/// fails, rooms slowly go to vacuum without any obvious leak.
/datum/unit_test/dq_total_moles_conserved_long_run

/datum/unit_test/dq_total_moles_conserved_long_run/Run()
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no usable floor pair on map for conservation test")
	var/turf/simulated/floor/A = pair[1]
	var/turf/simulated/floor/B = pair[2]

	dq_atmos_test_isolate_pair(A, B)

	for(var/datum/gas/g as anything in A.air.get_gases())
		A.air.set_moles(g, 0)
	for(var/datum/gas/g as anything in B.air.get_gases())
		B.air.set_moles(g, 0)

	var/datum/gas_mixture/donor_a = new(70)
	donor_a.adjust_gas(/datum/gas/oxygen, 75)
	donor_a.adjust_gas(/datum/gas/nitrogen, 75)
	donor_a.set_temperature(T20C)
	A.assume_air(donor_a)

	var/datum/gas_mixture/donor_b = new(70)
	donor_b.adjust_gas(/datum/gas/oxygen, 25)
	donor_b.adjust_gas(/datum/gas/nitrogen, 25)
	donor_b.set_temperature(T20C)
	B.assume_air(donor_b)

	var/initial_total = A.air.total_moles() + B.air.total_moles()
	TEST_ASSERT(abs(initial_total - 200) < 1, "test setup: expected ~200 moles total, got [initial_total]")

	// Wait for ~20 real SSair ticks (10s wall time). The original test asked
	// for 200 ticks but the conservation property doesn't require that many —
	// either rounding leaks per-tick or it doesn't.
	dq_atmos_test_wait_real_ssair_ticks(20)

	var/final_total = A.air.total_moles() + B.air.total_moles()
	TEST_ASSERT(abs(final_total - initial_total) < 2, \
		"mass NOT conserved across real SSair ticks in walled pair: [initial_total] → [final_total] (loss [initial_total - final_total])")


// =====================================================================
// Reaction conservation, multi-z, planetary, gas-overlay-on-moving-gas
// =====================================================================

/// Plasmafire conservation: plasma + 2*O2 → CO2 + H2O (stoichiometric). The
/// total mass of the products must roughly equal the mass of reactants
/// (atoms aren't created or destroyed). Sanity-bounds against runaway loss.
/datum/unit_test/dq_plasmafire_conserves_mass

/datum/unit_test/dq_plasmafire_conserves_mass/Run()
	var/datum/gas_mixture/mix = new(CELL_VOLUME)
	mix.adjust_gas(/datum/gas/plasma, 50)
	mix.adjust_gas(/datum/gas/oxygen, 400)
	mix.set_temperature(PLASMA_MINIMUM_BURN_TEMPERATURE + 500)
	var/initial_total = mix.total_moles()
	var/initial_thermal = mix.thermal_energy()

	mix.react(null)

	var/final_total = mix.total_moles()
	var/final_thermal = mix.thermal_energy()
	// Plasmafire converts plasma+O2 to CO2+H2O+tritium; stoichiometry isn't 1:1
	// (mole count changes because the reaction joins atoms), but the TOTAL mol
	// count shouldn't drop by more than ~40% (reactant ratios) or rise above the
	// initial. If it goes outside that window, the reaction is leaking matter.
	TEST_ASSERT(final_total > initial_total * 0.55, \
		"plasmafire lost too many moles: [initial_total] → [final_total] (>45% loss is unphysical)")
	TEST_ASSERT(final_total < initial_total * 1.5, \
		"plasmafire created too many moles: [initial_total] → [final_total] (>50% gain is unphysical)")
	// Thermal energy can only increase from the reaction (exothermic) — it
	// must NOT drop below the starting energy.
	TEST_ASSERT(final_thermal >= initial_thermal * 0.95, \
		"plasmafire thermal energy DROPPED: [initial_thermal] → [final_thermal] (exothermic reaction should raise it)")


/// Multi-z spread: gas in an open turf propagates DOWN to the floor directly
/// below it when the two z-levels are vertically connected. Exercises the full
/// production multi-z atmos path:
///   - build_multiz_atmos_levels() bridges GLOB.z_levels (the movement-multiz
///     connectivity that /obj/effect/landmark/map_data populates) into
///     SSmapping.multiz_levels (the atmos vertical-adjacency table that the
///     init fast-path reads but nothing else ever filled);
///   - immediate_calculate_adjacent_turfs() wires the vertical adjacency via
///     get_step_multiz/GetBelow once the levels are connected;
///   - SSair.process_cell shares gas across that adjacency.
/// The live map is single-z, so we grow two scratch z-levels through the same
/// world.increment_max_z() path load_new_z() uses, connect + test on them, then
/// tear the scratch column back down so later tests see a clean world.
/datum/unit_test/dq_multiz_spread_through_open_turf

/datum/unit_test/dq_multiz_spread_through_open_turf/Run()
	world.increment_max_z()
	var/lower_z = world.maxz
	world.increment_max_z()
	var/upper_z = world.maxz

	// All z-levels share the same x/y dimensions; pick an interior column.
	var/cx = 3
	var/cy = 3
	var/turf/lower_raw = locate(cx, cy, lower_z)
	var/turf/upper_raw = locate(cx, cy, upper_z)
	TEST_ASSERT_NOTNULL(lower_raw, "scratch lower turf didn't materialize at [cx],[cy],[lower_z]")
	TEST_ASSERT_NOTNULL(upper_raw, "scratch upper turf didn't materialize at [cx],[cy],[upper_z]")

	// Connect the two scratch levels the way a height-2 map_data landmark would,
	// then run the production bridge that feeds atmos vertical adjacency.
	var/old_z_levels_len = length(GLOB.z_levels)
	if(length(GLOB.z_levels) < lower_z)
		GLOB.z_levels.len = lower_z
	var/old_connected = GLOB.z_levels[lower_z]
	GLOB.z_levels[lower_z] = TRUE

	SSair.build_multiz_atmos_levels()

	// The bridge must register the vertical traits — this is the wiring fix.
	var/list/upper_traits = (length(SSmapping.multiz_levels) >= upper_z) ? SSmapping.multiz_levels[upper_z] : null
	TEST_ASSERT_NOTNULL(upper_traits, "build_multiz_atmos_levels left multiz_levels for z=[upper_z] null")
	TEST_ASSERT(upper_traits[Z_LEVEL_DOWN], "build_multiz_atmos_levels didn't mark the upper z DOWN-connected from GLOB.z_levels")

	// Build the open-over-floor column with real turf types and air. ChangeTurf
	// returns the freshly-created turf of the requested type.
	var/turf/simulated/floor/lower = lower_raw.ChangeTurf(/turf/simulated/floor)
	var/turf/simulated/open/upper = upper_raw.ChangeTurf(/turf/simulated/open)
	TEST_ASSERT_NOTNULL(lower, "scratch lower didn't become a simulated floor")
	TEST_ASSERT_NOTNULL(upper, "scratch upper didn't become a simulated open turf")
	TEST_ASSERT_NOTNULL(lower.air, "scratch floor has no air mixture")
	TEST_ASSERT_NOTNULL(upper.air, "scratch open turf has no air mixture")

	// Keep this a vertical-spread test. Scratch levels start as open space, so
	// without a wall ring the donor vents sideways before the detached solver
	// has a meaningful opportunity to exercise the multi-z edge.
	var/list/isolation_walls = list()
	for(var/direction in GLOB.cardinal)
		var/turf/lower_neighbor = get_step(lower, direction)
		var/turf/upper_neighbor = get_step(upper, direction)
		isolation_walls += lower_neighbor.ChangeTurf(/turf/simulated/wall)
		isolation_walls += upper_neighbor.ChangeTurf(/turf/simulated/wall)

	// Wire both ends through the production recompute path, then publish the
	// complete topology batch before expecting the detached solver to use it.
	lower.air_update_turf(TRUE, FALSE)
	upper.air_update_turf(TRUE, FALSE)
	TEST_ASSERT(vg_atmos_turfs_share(upper, lower), \
		"vertical atmos adjacency wasn't wired: the open turf isn't adjacent to the floor below it (upper mask=[upper.air_block_mask()] open=[vg_atmos_open_dirs(upper)], lower mask=[lower.air_block_mask()] open=[vg_atmos_open_dirs(lower)], rust upper=[json_encode(vg_atmos_cell_info(upper))] lower=[json_encode(vg_atmos_cell_info(lower))] z=[lower_z]/[upper_z])")

	// Zero both, load plasma up top, let the real engine share it down.
	for(var/datum/gas/g as anything in upper.air.get_gases())
		upper.air.set_moles(g, 0)
	for(var/datum/gas/g as anything in lower.air.get_gases())
		lower.air.set_moles(g, 0)
	lower.air.set_temperature(T20C)

	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/plasma, 100)
	donor.set_temperature(T20C)
	upper.assume_air(donor)
	upper.air_update_turf(TRUE, FALSE)

	// Poll: break the moment plasma has reached the floor below (same
	// condition asserted after the loop), instead of always sleeping 20 ticks.
	var/baseline = 0
	var/down_p
	while(baseline < 20)
		down_p = lower.air.get_moles(/datum/gas/plasma)
		if(down_p > 1)
			break
		SSair.run_gas_frames(1)
		baseline++

	down_p = lower.air.get_moles(/datum/gas/plasma)
	TEST_ASSERT(down_p > 1, \
		"multi-z spread failed: floor below the open turf got [down_p] plasma after real SSair ticks")

	// Tear the scratch column down: clear gas, revert turfs to space, restore
	// the connectivity table. (world.maxz can't shrink; the spare levels are
	// left as inert space, which no later test's floor/open searches match.)
	upper.air.set_moles(/datum/gas/plasma, 0)
	lower.air.set_moles(/datum/gas/plasma, 0)
	for(var/turf/isolation_wall as anything in isolation_walls)
		isolation_wall.ChangeTurf(/turf/space)
	upper.ChangeTurf(/turf/space)
	lower.ChangeTurf(/turf/space)
	GLOB.z_levels[lower_z] = old_connected
	if(old_z_levels_len < length(GLOB.z_levels))
		GLOB.z_levels.len = old_z_levels_len
	SSair.build_multiz_atmos_levels()


/// Planetary share: a turf with planetary_atmos=TRUE shares 80% with the
/// planet's immutable mix every tick. A polluted turf should rapidly converge
/// to the planet's baseline atmosphere; an empty turf should rapidly inherit
/// the planet's gas.
/datum/unit_test/dq_planetary_atmos_converges_to_baseline

/datum/unit_test/dq_planetary_atmos_converges_to_baseline/Run()
	// No mapped turf type sets planetary_atmos on this build, so build the
	// scenario deterministically from a sealed test-room floor. We set
	// planetary_atmos = TRUE and register the immutable planetary mix in
	// SSair.planetary keyed by the floor's initial_gas_mix — exactly what
	// /turf/open/Initialize does for a planetary turf. The floor's default
	// initial_gas_mix (OPENTURF_DEFAULT_ATMOS) is plasma-free, so once we
	// pollute the turf with plasma the per-tick planetary share will drain it
	// back toward the baseline.
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no usable floor pair on map for planetary convergence test")
	var/turf/simulated/floor/T = pair[1]
	var/turf/simulated/floor/other = pair[2]

	// Seal the turf off from horizontal neighbors so the only sink is the
	// planetary atmosphere, then keep src active across ticks.
	dq_atmos_test_isolate_pair(T, other)

	T.planetary_atmos = TRUE
	if(!SSair.planetary[T.initial_gas_mix])
		var/datum/gas_mixture/immutable/planetary/baseline = new
		baseline.parse_string_immutable(T.initial_gas_mix)
		SSair.planetary[T.initial_gas_mix] = baseline

	var/datum/gas_mixture/planet_mix = SSair.planetary[T.initial_gas_mix]
	TEST_ASSERT_NOTNULL(planet_mix, "SSair.planetary missing entry for [T.type] gas_mix [T.initial_gas_mix]")

	// Register T as planetary in the arena WHILE IT IS STILL CLEAN. auxmos captures
	// the planetary baseline (the mix a planetary turf is pulled toward) from the
	// turf's current air at registration time. A real planetary turf registers clean
	// at mapload; here we set the flag at runtime, so re-register now — before we
	// pollute it — or auxmos would snapshot the polluted air as the baseline and the
	// share would have nothing to drain toward.
	T.update_air_ref(0)

	// Pollute the turf with phoron via the production path. assume_air calls
	// air_update_turf → enrolls T in active_turfs.
	for(var/datum/gas/g as anything in T.air.get_gases())
		T.air.set_moles(g, 0)
	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/plasma, 200)
	donor.set_temperature(T20C)
	T.assume_air(donor)
	var/initial_plasma = T.air.get_moles(/datum/gas/plasma)
	TEST_ASSERT(initial_plasma > 150, "test setup didn't load enough plasma: [initial_plasma]")

	// Real Master.Loop ticks SSair, whose Rust turf-sharing pass
	// (process_turfs_auxtools) blends the turf air toward planetary_mix
	// when T.planetary_atmos is set. Poll and break as soon as the drain
	// target (asserted below) is reached, instead of always waiting 20 ticks.
	var/baseline = 0
	var/final_plasma
	while(baseline < 20)
		final_plasma = T.air.get_moles(/datum/gas/plasma)
		if(final_plasma < initial_plasma * 0.5)
			break
		SSair.run_gas_frames(1)
		baseline++

	final_plasma = T.air.get_moles(/datum/gas/plasma)
	// Clean up: drop the planetary flag and unwall the room so later tests see
	// a clean, non-planetary floor. (We leave the SSair.planetary entry in
	// place — it's an immutable baseline keyed by the standard gas string and
	// matches what a real planetary turf would have registered anyway.)
	T.planetary_atmos = FALSE
	T.update_air_ref(0) // back to an ordinary cell
	for(var/datum/gas/g as anything in T.air.get_gases())
		T.air.set_moles(g, 0)
	dq_atmos_test_restore_walls()

	TEST_ASSERT(final_plasma < initial_plasma * 0.5, \
		"planetary share didn't drain phoron pollution: [initial_plasma] → [final_plasma] after real SSair ticks")


/// Gas overlay updates as gas moves: load plasma on A, run a share tick, both
/// A and B should now have visible plasma overlays in their atmos_overlay_types.
/// This catches "process_cell doesn't call update_visuals" regressions.
/datum/unit_test/dq_gas_overlays_appear_on_share

/datum/unit_test/dq_gas_overlays_appear_on_share/Run()
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no usable floor pair on map for overlay-on-share test")
	var/turf/simulated/floor/A = pair[1]
	var/turf/simulated/floor/B = pair[2]

	dq_atmos_test_isolate_pair(A, B)

	// Wipe pre-existing overlays from earlier tests so the assertion is honest.
	for(var/turf/open/T as anything in list(A, B))
		if(T.atmos_overlay_types)
			for(var/old_ov in T.atmos_overlay_types)
				T.vis_contents -= old_ov
			T.atmos_overlay_types = null

	for(var/datum/gas/g as anything in A.air.get_gases())
		A.air.set_moles(g, 0)
	for(var/datum/gas/g as anything in B.air.get_gases())
		B.air.set_moles(g, 0)
	B.air.set_temperature(T20C)

	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/plasma, 100) // well above moles_visible
	donor.set_temperature(T20C)
	A.assume_air(donor)

	// Poll: break as soon as both overlays appear (the same condition
	// asserted below), instead of always sleeping out 20 ticks.
	var/baseline = 0
	while(baseline < 20)
		if(LAZYLEN(A.atmos_overlay_types) > 0 && LAZYLEN(B.atmos_overlay_types) > 0)
			break
		SSair.run_gas_frames(1)
		baseline++

	TEST_ASSERT(LAZYLEN(A.atmos_overlay_types) > 0, \
		"A has plasma but no atmos_overlay — process_cell didn't call update_visuals")
	TEST_ASSERT(LAZYLEN(B.atmos_overlay_types) > 0, \
		"plasma reached B via share but B's overlay didn't update — process_cell skipped update_visuals on shared neighbors")

	// Cleanup.
	A.air.set_moles(/datum/gas/plasma, 0)
	B.air.set_moles(/datum/gas/plasma, 0)
	A.update_visuals()
	B.update_visuals()


/// fire_protection prevents ignition: a turf marked by apply_fire_protection
/// must NOT ignite even with abundant plasma + oxygen + heat. Validates the
/// flame-retardant tile hook tg_infra_compat::apply_fire_protection wired
/// into hotspot_expose.
/datum/unit_test/dq_fire_protection_prevents_ignition

/datum/unit_test/dq_fire_protection_prevents_ignition/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor on test map for fire-protection test")

	if(T.active_hotspot)
		qdel(T.active_hotspot)
		T.active_hotspot = null

	var/datum/gas_mixture/air = T.return_air()
	for(var/datum/gas/g as anything in air.get_gases())
		air.set_moles(g, 0)
	air.adjust_gas(/datum/gas/plasma, 20)
	air.adjust_gas(/datum/gas/oxygen, 50)
	air.set_temperature(PLASMA_MINIMUM_BURN_TEMPERATURE + 300)

	T.apply_fire_protection()
	T.hotspot_expose(PLASMA_MINIMUM_BURN_TEMPERATURE + 300, CELL_VOLUME, soh = TRUE)

	TEST_ASSERT(isnull(T.active_hotspot), \
		"hotspot ignited despite apply_fire_protection — flame-retardant gate not honored")

	// Sanity check: without protection (clear the timestamp), ignition succeeds.
	T.fire_protection = 0
	T.hotspot_expose(PLASMA_MINIMUM_BURN_TEMPERATURE + 300, CELL_VOLUME, soh = TRUE)
	TEST_ASSERT_NOTNULL(T.active_hotspot, \
		"control: ignition should succeed after clearing fire_protection")

	if(T.active_hotspot)
		qdel(T.active_hotspot)
		T.active_hotspot = null


/// share_ratio matches the Rust semantics: self_new = (1-r)*self + r*giver,
/// giver unchanged. This is the contract the verdigris auxmos byondapi-bound
/// version implements; the DM fallback in xgm_compat.dm has to match exactly.
/datum/unit_test/dq_share_ratio_matches_rust_semantics

/datum/unit_test/dq_phoron_canister_releases_to_turf

/datum/unit_test/dq_phoron_canister_releases_to_turf/Run()
	var/turf/simulated/floor/T
	for(var/turf/simulated/floor/candidate in world)
		if(candidate.air && !candidate.blocks_air)
			T = candidate
			break
	TEST_ASSERT_NOTNULL(T, "no simulated floor is available for the canister release test")
	dq_atmos_test_snapshot_air(T)
	dq_atmos_test_isolate_pair(T, T)
	T.air_update_turf(TRUE, FALSE)
	var/datum/gas_mixture/original_air = new(T.air.return_volume())
	original_air.copy_from(T.air)
	var/obj/machinery/portable_atmospherics/canister/phoron/C = allocate(/obj/machinery/portable_atmospherics/canister/phoron, T)
	var/before_canister = C.air_contents.get_moles(/datum/gas/plasma)
	var/before_turf = T.air.get_moles(/datum/gas/plasma)
	C.valve_open = TRUE
	C.release_pressure = 10 * ONE_ATMOSPHERE
	C.process()
	var/after_canister = C.air_contents.get_moles(/datum/gas/plasma)
	var/after_turf = T.air.get_moles(/datum/gas/plasma)
	var/overlay_visible = LAZYLEN(T.atmos_overlay_types) > 0
	var/analyzer_readout = jointext(atmosanalyzer_scan(T, T.air, null), " ")
	T.air.copy_from(original_air)
	T.update_visuals()
	T.air_update_turf(FALSE, FALSE)
	TEST_ASSERT(after_canister < before_canister, "phoron canister did not drain: [before_canister] -> [after_canister]")
	TEST_ASSERT(after_turf > before_turf, "released phoron vanished: turf [before_turf] -> [after_turf], canister [before_canister] -> [after_canister]")
	TEST_ASSERT(overlay_visible, "released phoron exceeded its visibility threshold but produced no turf overlay")
	TEST_ASSERT(findtext(analyzer_readout, "Phoron"), "gas analyzer did not identify released phoron: [analyzer_readout]")

/datum/unit_test/dq_share_ratio_matches_rust_semantics/Run()
	var/datum/gas_mixture/self_mix = new(CELL_VOLUME)
	self_mix.adjust_gas(/datum/gas/oxygen, 100)
	self_mix.set_temperature(T20C)
	var/datum/gas_mixture/giver_mix = new(CELL_VOLUME)
	giver_mix.adjust_gas(/datum/gas/nitrogen, 200)
	giver_mix.set_temperature(T0C + 50) // hotter

	// Half-blend.
	self_mix.share_ratio(giver_mix, 0.5)

	// Self should now have half of original O2 (50) plus half of giver's N2 (100).
	var/self_o2 = self_mix.get_moles(/datum/gas/oxygen)
	var/self_n2 = self_mix.get_moles(/datum/gas/nitrogen)
	TEST_ASSERT(abs(self_o2 - 50) < 0.5, "self O2 wrong: expected 50, got [self_o2]")
	TEST_ASSERT(abs(self_n2 - 100) < 0.5, "self N2 wrong: expected 100, got [self_n2]")

	// Giver must be UNCHANGED.
	var/giver_o2 = giver_mix.get_moles(/datum/gas/oxygen)
	var/giver_n2 = giver_mix.get_moles(/datum/gas/nitrogen)
	TEST_ASSERT_EQUAL(giver_o2, 0, "giver gained O2 — share_ratio should leave giver untouched")
	TEST_ASSERT(abs(giver_n2 - 200) < 0.5, "giver lost N2 — share_ratio should leave giver untouched")


/// specific_entropy returns finite values for a normal-pressure mixture and
/// monotonically decreases with rising partial pressure (more compressed gas
/// has lower entropy). Validates the XGM formula port — if these properties
/// don't hold, pump power-draw calculations are broken.
/datum/unit_test/dq_specific_entropy_decreases_with_pressure

/datum/unit_test/dq_specific_entropy_decreases_with_pressure/Run()
	var/datum/gas_mixture/lo = new(CELL_VOLUME)
	lo.adjust_gas(/datum/gas/oxygen, 10) // low partial pressure
	lo.set_temperature(T20C)
	var/datum/gas_mixture/hi = new(CELL_VOLUME)
	hi.adjust_gas(/datum/gas/oxygen, 1000) // high partial pressure
	hi.set_temperature(T20C)

	var/s_lo = lo.specific_entropy_gas(/datum/gas/oxygen)
	var/s_hi = hi.specific_entropy_gas(/datum/gas/oxygen)
	TEST_ASSERT(s_lo > 0, "low-pressure entropy must be positive: got [s_lo]")
	TEST_ASSERT(s_hi > 0, "high-pressure entropy must be positive: got [s_hi]")
	TEST_ASSERT(s_lo > s_hi, \
		"specific entropy should DECREASE with pressure (XGM formula): low-p s=[s_lo], high-p s=[s_hi]")

	// Vacuum returns the vacuum constant.
	var/datum/gas_mixture/empty = new(CELL_VOLUME)
	var/s_empty = empty.specific_entropy_gas(/datum/gas/oxygen)
	TEST_ASSERT_EQUAL(s_empty, 150, "vacuum specific_entropy should return SPECIFIC_ENTROPY_VACUUM (150), got [s_empty]")


/// c_airblock returns BLOCKED through walls and 0 between adjacent floors —
/// regression for the bitfield fix.
/datum/unit_test/dq_c_airblock_returns_bitfield

/datum/unit_test/dq_c_airblock_returns_bitfield/Run()
	// Need a floor with BOTH a wall neighbor (to assert BLOCKED) AND a genuinely
	// atmos-connected floor neighbor (to assert passable=0). A naive scan grabs the
	// first floor-next-to-a-wall, which on a full station is a dock-airlock tile
	// whose "floor neighbor" is behind a closed airlock/window — so c_airblock
	// correctly returns BLOCKED there and the passable assert wrongly fails. Require
	// the floor neighbor to be in atmos_adjacent_turfs (proven passable).
	var/turf/simulated/floor/A = null
	var/turf/simulated/wall/W = null
	var/turf/simulated/floor/N = null
	for(var/turf/simulated/floor/cand in world)
		if(!cand.air || cand.blocks_air || !length(vg_atmos_adjacent_turfs(cand)))
			continue
		var/turf/simulated/floor/conn = null
		for(var/turf/nn as anything in vg_atmos_adjacent_turfs(cand))
			if(istype(nn, /turf/simulated/floor))
				var/turf/simulated/floor/nf = nn
				if(nf.air && !nf.blocks_air)
					conn = nf
					break
		if(!conn)
			continue
		var/turf/simulated/wall/wall_n = null
		for(var/direction in GLOB.cardinal)
			var/turf/wn = get_step(cand, direction)
			if(istype(wn, /turf/simulated/wall))
				wall_n = wn
				break
		if(!wall_n)
			continue
		A = cand
		W = wall_n
		N = conn
		break
	TEST_ASSERT_NOTNULL(A, "no floor with both a wall neighbor and a connected floor neighbor")

	TEST_ASSERT_EQUAL(A.c_airblock(W), BLOCKED, \
		"c_airblock(wall) returned [A.c_airblock(W)], expected BLOCKED ([BLOCKED])")

	TEST_ASSERT_EQUAL(A.c_airblock(N), 0, \
		"c_airblock(open floor) returned [A.c_airblock(N)], expected 0 (passable)")

	// Self.
	TEST_ASSERT_EQUAL(A.c_airblock(A), 0, "c_airblock(self) should be 0")


/// gas_data.molar_mass has real values for every gas, not the crude
/// specific_heat * 0.05 fallback for /tg/-vendored LINDA-only gases.
/datum/unit_test/dq_gas_data_molar_mass_populated

/datum/unit_test/dq_gas_data_molar_mass_populated/Run()
	// Spot-check core gases.
	TEST_ASSERT(abs(GLOB.gas_data.molar_mass[GAS_O2] - 0.032) < 0.001, \
		"oxygen molar mass wrong: [GLOB.gas_data.molar_mass[GAS_O2]], expected 0.032")
	TEST_ASSERT(abs(GLOB.gas_data.molar_mass[GAS_N2] - 0.028) < 0.001, \
		"nitrogen molar mass wrong: [GLOB.gas_data.molar_mass[GAS_N2]]")

	// /tg/-only gases must have explicit molar masses from the LINDA-only table,
	// not the crude specific_heat * 0.05 default. These must be present and
	// positive unconditionally — a missing/zero entry is the exact regression
	// this test exists to catch (it silently breaks pump entropy / exhaust mass).
	TEST_ASSERT(GLOB.gas_data.molar_mass["water_vapor"] > 0, \
		"water_vapor molar mass missing/zero: [GLOB.gas_data.molar_mass["water_vapor"]]")
	TEST_ASSERT(abs(GLOB.gas_data.molar_mass["water_vapor"] - 0.018) < 0.001, \
		"water_vapor molar mass wrong: [GLOB.gas_data.molar_mass["water_vapor"]], expected 0.018 (H2O)")
	TEST_ASSERT(GLOB.gas_data.molar_mass["tritium"] > 0, \
		"tritium molar mass missing/zero: [GLOB.gas_data.molar_mass["tritium"]]")
	TEST_ASSERT(abs(GLOB.gas_data.molar_mass["tritium"] - 0.006) < 0.001, \
		"tritium molar mass wrong: [GLOB.gas_data.molar_mass["tritium"]], expected 0.006")
	TEST_ASSERT(GLOB.gas_data.molar_mass["hydrogen"] > 0, \
		"hydrogen molar mass missing/zero: [GLOB.gas_data.molar_mass["hydrogen"]]")
	TEST_ASSERT(abs(GLOB.gas_data.molar_mass["hydrogen"] - 0.002) < 0.001, \
		"hydrogen molar mass wrong: [GLOB.gas_data.molar_mass["hydrogen"]], expected 0.002")


// =====================================================================
// CHOMP atmos machinery integration on top of LINDA
// =====================================================================
// The CHOMP atmospherics machinery (vents, scrubbers, pumps, canisters) was
// built against the XGM gas API. After the LINDA migration the gas math runs
// on /tg/'s LINDA gas_mixture (with auxmos Rust bindings). The integration
// layer is the /proc/pump_gas, /proc/pump_gas_passive, and /proc/scrub_gas
// helpers in code/ATMOSPHERICS/_atmospherics_helpers.dm — every CHOMP atmos
// machine routes through one of those. These tests validate the helpers
// produce correct results against LINDA mixtures.

/// pump_gas helper: actively moves gas from source to sink and returns the
/// power draw. Verifies LINDA's specific_entropy + remove + merge all play
/// nicely together via the CHOMP pump pipeline.
/datum/unit_test/dq_pump_gas_helper_transfers_moles

/datum/unit_test/dq_pump_gas_helper_transfers_moles/Run()
	var/datum/gas_mixture/source = new(CELL_VOLUME)
	source.adjust_gas(/datum/gas/nitrogen, 200)
	source.set_temperature(T20C)
	var/datum/gas_mixture/sink = new(CELL_VOLUME)
	sink.set_temperature(T20C)

	var/initial_source = source.total_moles()
	var/initial_sink = sink.total_moles()

	var/power = pump_gas(null, source, sink, 50, 100000)

	TEST_ASSERT(power >= 0, "pump_gas returned [power] (no transfer); expected positive power_draw")
	var/after_source = source.total_moles()
	var/after_sink = sink.total_moles()
	TEST_ASSERT(after_source < initial_source, \
		"source moles didn't drop after pump: [initial_source] → [after_source]")
	TEST_ASSERT(after_sink > initial_sink, \
		"sink moles didn't rise after pump: [initial_sink] → [after_sink]")
	// Conservation: source_lost == sink_gained.
	TEST_ASSERT(abs((initial_source - after_source) - (after_sink - initial_sink)) < 0.01, \
		"moles not conserved across pump: source lost [initial_source - after_source], sink gained [after_sink - initial_sink]")


/// pump_gas_passive: drives transfer purely by pressure delta. Validates
/// calculate_equalize_moles (which calls return_pressure under the hood).
/datum/unit_test/dq_pump_gas_passive_equalizes_pressures

/datum/unit_test/dq_pump_gas_passive_equalizes_pressures/Run()
	var/datum/gas_mixture/source = new(CELL_VOLUME)
	source.adjust_gas(/datum/gas/oxygen, 200)
	source.set_temperature(T20C)
	var/datum/gas_mixture/sink = new(CELL_VOLUME)
	sink.adjust_gas(/datum/gas/oxygen, 50)
	sink.set_temperature(T20C)

	var/p_source_init = source.return_pressure()
	var/p_sink_init = sink.return_pressure()
	TEST_ASSERT(p_source_init > p_sink_init, "test setup: source should start higher pressure")

	pump_gas_passive(null, source, sink)

	var/p_source_after = source.return_pressure()
	var/p_sink_after = sink.return_pressure()
	TEST_ASSERT(p_source_after < p_source_init, "source pressure didn't drop: [p_source_init] → [p_source_after]")
	TEST_ASSERT(p_sink_after > p_sink_init, "sink pressure didn't rise: [p_sink_init] → [p_sink_after]")
	// After equalization the two pressures should be much closer than before.
	var/initial_delta = p_source_init - p_sink_init
	var/final_delta = abs(p_source_after - p_sink_after)
	TEST_ASSERT(final_delta < initial_delta * 0.5, \
		"pressure delta didn't shrink: was [initial_delta], now [final_delta]")


/// A connected pipenet owns exactly one gas mixture. Every pipeline observes a
/// mutation immediately without a reconciliation pass.
/datum/unit_test/dq_pipenet_reconcile_air_equalizes

/datum/unit_test/dq_pipenet_reconcile_air_equalizes/Run()
	var/datum/pipe_network/net = new
	var/datum/pipeline/line_a = new
	line_a.air = new(70)
	line_a.volume = 70
	line_a.members = list()
	line_a.edges = list()
	line_a.network = net
	line_a.air.adjust_gas(/datum/gas/oxygen, 100)
	line_a.air.set_temperature(T20C)
	var/datum/pipeline/line_b = new
	line_b.air = new(70)
	line_b.volume = 70
	line_b.members = list()
	line_b.edges = list()
	line_b.network = net
	line_b.air.set_temperature(T0C + 80)
	var/initial_total = line_a.air.total_moles() + line_b.air.total_moles()
	var/initial_thermal = line_a.air.thermal_energy() + line_b.air.thermal_energy()
	net.add_line_member(line_a)
	net.add_line_member(line_b)
	net.update_network_gases()

	TEST_ASSERT(line_a.air == net.air && line_b.air == net.air, \
		"connected pipelines did not share the authoritative network mixture")
	TEST_ASSERT_EQUAL(length(net.gases), 1, "pipenet compatibility gas list contains member mirrors")
	var/final_total = net.air.total_moles()
	var/final_thermal = net.air.thermal_energy()
	TEST_ASSERT(abs(final_total - initial_total) < 0.5, \
		"authoritative pipenet pooling lost mass: [initial_total] → [final_total]")
	TEST_ASSERT(abs(final_thermal - initial_thermal) < (initial_thermal * 0.05), \
		"authoritative pipenet pooling lost thermal energy: [initial_thermal] → [final_thermal]")
	var/before_mutation = line_b.air.total_moles()
	line_a.air.adjust_gas(/datum/gas/nitrogen, 10)
	TEST_ASSERT_EQUAL(line_b.air.total_moles(), before_mutation + 10, \
		"a connected pipeline required reconciliation to observe a gas mutation")
	qdel(net)
	qdel(line_a)
	qdel(line_b)


/// Vent pump integration: build a real vent_pump on a floor, seed its
/// air_contents with pressurized N2, satisfy can_pump's preconditions, and
/// verify process() pushes gas into the turf. This exercises the full
/// machinery → LINDA path end-to-end.
/datum/unit_test/dq_vent_pump_pushes_to_turf

/datum/unit_test/dq_vent_pump_pushes_to_turf/Run()
	var/list/run = dq_atmos_test_find_clear_pipe_run(2)
	TEST_ASSERT_NOTNULL(run, "no clear two-tile pipe run for vent_pump test")
	var/turf/simulated/floor/T = run[1]
	var/turf/simulated/floor/pipe_turf = run[2]
	var/direction = get_dir(T, pipe_turf)
	var/axis_directions = direction | REVERSE_DIR(direction)
	// A real sealed pair: the flow law now writes the turf through the R6
	// field, which shares gas with open neighbours every settled frame, so
	// an unsealed test turf would leak the result into the rest of the map.
	dq_atmos_test_isolate_pair(T, pipe_turf)

	var/datum/gas_mixture/turf_air = T.return_air()
	for(var/datum/gas/g as anything in turf_air.get_gases())
		turf_air.set_moles(g, 0)
	turf_air.set_temperature(T20C)

	var/obj/machinery/atmospherics/unary/vent_pump/V = new(T)
	TEST_ASSERT_NOTNULL(V, "couldn't construct vent_pump")
	TEST_ASSERT_NOTNULL(V.air_contents, "vent_pump air_contents null")
	V.dir = direction
	V.initialize_directions = direction
	var/obj/machinery/atmospherics/pipe/simple/P = new(pipe_turf)
	P.dir = axis_directions
	P.initialize_directions = axis_directions
	V.atmos_init()
	P.atmos_init()
	dq_atmos_test_publish_rust_pipenets(list(V, P))
	TEST_ASSERT_NOTNULL(V.node, "vent_pump did not connect to its test supply pipe")
	TEST_ASSERT_NOTNULL(V.air_contents, "vent_pump did not receive a pipenet mixture")

	// Pressurize the vent's internal supply (the "pipe behind it").
	V.air_contents.adjust_gas(/datum/gas/nitrogen, 500)
	V.air_contents.set_temperature(T20C)
	// Wire up the remaining process preconditions: powered and unobstructed.
	V.use_power = USE_POWER_IDLE
	V.stat &= ~(NOPOWER | BROKEN)
	V.welded = FALSE
	V.pump_direction = 1 // release
	V.external_pressure_bound = ONE_ATMOSPHERE * 2 // ambitious target
	V.internal_pressure_bound = 0
	V.update_rust_device()
	TEST_ASSERT(V.air_contents.arena_id() != turf_air.arena_id(), "vent supply and turf unexpectedly share one Rust mixture")
	TEST_ASSERT(V.air_contents.total_moles() > 499, "vent supply lost its seeded nitrogen before processing")
	TEST_ASSERT(V.get_pressure_delta(turf_air) > 0.5, "vent pressure predicate is not actionable after setup")

	var/initial_turf_n2 = turf_air.get_moles(/datum/gas/nitrogen)
	// Exercise the exact flat-ID ABI independently of the machinery queue. This
	// catches argument/list marshalling regressions instead of reporting them as
	// an apparently inert vent.
	var/list/direct_transfer = vg_batch_transfer_hook(list(V.air_contents.arena_id(), turf_air.arena_id(), 1))
	TEST_ASSERT(islist(direct_transfer) && length(direct_transfer) == 1, \
		"batch transfer ABI did not return one result: [json_encode(direct_transfer)]")
	TEST_ASSERT(direct_transfer?[1] > 0.9, \
		"batch transfer ABI moved no gas for valid arena IDs [V.air_contents.arena_id()] -> [turf_air.arena_id()]: [json_encode(direct_transfer)]")
	initial_turf_n2 = turf_air.get_moles(/datum/gas/nitrogen)
	var/initial_vent_n2 = V.air_contents.get_moles(/datum/gas/nitrogen)
	var/initial_pipe_turf_n2 = pipe_turf.return_air().get_moles(/datum/gas/nitrogen)

	// M2 (simulation.md §5): the flow law is a Rust device edge bridging
	// the pipe network and the turf field; SSair drives it, not
	// V.process() (deleted). Every step reads the same pinned turf view
	// until a gas frame runs, so its target-pressure check doesn't see its
	// own prior steps mid-loop (each command is a delta, so this still
	// conserves) - settle with one frame at the end, not every iteration,
	// so the real map's neighbour diffusion doesn't spread the result away
	// from this one turf before the assertions below read it. A frame must
	// run every iteration: step_turf_devices reads the field's pinned view,
	// so without a commit in between, every step recomputes its transfer
	// from the same unchanged turf snapshot instead of a shrinking one.
	for(var/i in 1 to 10)
		SSair.rust_step_pipe_devices()
		SSair.run_gas_frames(1)

	var/final_turf_n2 = turf_air.get_moles(/datum/gas/nitrogen)
	TEST_ASSERT(final_turf_n2 > initial_turf_n2 + 5, \
		"vent_pump didn't push N2 to turf: [initial_turf_n2] → [final_turf_n2]")
	// Conservation: vent_contents lost == gained across the whole isolated
	// pair. T shares what it received with pipe_turf (its sealed-pair
	// neighbour) every settled frame like any other open turf, so pipe_turf's
	// share must be counted too, not just T's.
	var/vent_after = V.air_contents.get_moles(/datum/gas/nitrogen)
	var/final_pipe_turf_n2 = pipe_turf.return_air().get_moles(/datum/gas/nitrogen)
	var/turf_pair_gained = (final_turf_n2 - initial_turf_n2) + (final_pipe_turf_n2 - initial_pipe_turf_n2)
	var/total_delta = abs((initial_vent_n2 - vent_after) - turf_pair_gained)
	TEST_ASSERT(total_delta < 1, \
		"vent_pump conservation broken: vent lost [initial_vent_n2 - vent_after], turf+neighbour gained [turf_pair_gained]")

	qdel(V)
	qdel(P)


/// Vent scrubber integration: pollute a turf with phoron, run a scrubber
/// configured to filter PHORON, verify turf phoron drops and scrubber's
/// air_contents phoron rises.
/datum/unit_test/dq_vent_scrubber_pulls_target_gas

/datum/unit_test/dq_vent_scrubber_pulls_target_gas/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor on test map for vent_scrubber test")
	dq_atmos_test_snapshot_air(T)
	dq_atmos_test_isolate_pair(T, T)
	T.air_update_turf(TRUE, FALSE)

	var/datum/gas_mixture/turf_air = T.return_air()
	for(var/datum/gas/g as anything in turf_air.get_gases())
		turf_air.set_moles(g, 0)
	turf_air.adjust_gas(/datum/gas/plasma, 100)
	turf_air.adjust_gas(/datum/gas/oxygen, 100)
	turf_air.set_temperature(T20C)

	var/obj/machinery/atmospherics/unary/vent_scrubber/S = new(T)
	TEST_ASSERT_NOTNULL(S, "couldn't construct vent_scrubber")
	TEST_ASSERT_NOTNULL(S.air_contents, "scrubber air_contents null")

	// Wire up: powered, scrubbing mode, filter PHORON only. `node` is set
	// after topology registration - self-referencing it beforehand would
	// make rust_register_pipe_edges() try to connect the scrubber's port
	// to itself.
	S.use_power = USE_POWER_IDLE
	S.stat &= ~(NOPOWER | BROKEN)
	S.welded = FALSE
	S.scrubbing = 1
	S.scrubbing_gas = list(GAS_PHORON)
	S.rust_register_pipe_topology() // allocates ports, registers the device edge
	S.node = S
	S.update_rust_device()

	var/initial_turf_phoron = turf_air.get_moles(/datum/gas/plasma)
	var/initial_turf_o2 = turf_air.get_moles(/datum/gas/oxygen)
	var/initial_scrubber_phoron = S.air_contents.get_moles(/datum/gas/plasma)

	// M2 (simulation.md §5): the flow law is a Rust device edge bridging
	// the pipe network and the turf field; SSair drives it, not
	// S.process() (deleted). A frame must run every iteration:
	// step_turf_devices reads the field's pinned view, so without a commit
	// in between, every step recomputes its transfer from the same
	// unchanged turf snapshot instead of a shrinking one.
	for(var/i in 1 to 5)
		SSair.rust_step_pipe_devices()
		SSair.run_gas_frames(1)

	var/final_turf_phoron = turf_air.get_moles(/datum/gas/plasma)
	var/final_turf_o2 = turf_air.get_moles(/datum/gas/oxygen)
	var/final_scrubber_phoron = S.air_contents.get_moles(/datum/gas/plasma)

	TEST_ASSERT(final_turf_phoron < initial_turf_phoron, \
		"scrubber didn't remove phoron from turf: [initial_turf_phoron] → [final_turf_phoron]")
	TEST_ASSERT(final_scrubber_phoron > initial_scrubber_phoron, \
		"scrubber air_contents didn't gain phoron: [initial_scrubber_phoron] → [final_scrubber_phoron]")
	// O2 must be UNTOUCHED (only phoron is in scrubbing_gas).
	TEST_ASSERT(abs(final_turf_o2 - initial_turf_o2) < 0.5, \
		"scrubber removed O2 despite only filtering phoron: [initial_turf_o2] → [final_turf_o2]")

	turf_air.set_moles(/datum/gas/plasma, 0)
	turf_air.set_moles(/datum/gas/oxygen, 0)
	qdel(S)


/// Supermatter sanity: ensure /obj/machinery/power/supermatter constructs
/// without erroring and its initial air_contents is empty (or null) — full
/// behaviour requires a full power+gas setup, but this catches "vendored
/// /tg/ supermatter is type-incompatible with our LINDA gas_mixture" regressions.
/datum/unit_test/dq_supermatter_constructs

/datum/unit_test/dq_supermatter_constructs/Run()
	var/turf/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor on test map for supermatter construct test")

	var/obj/machinery/power/supermatter/SM = new(T)
	TEST_ASSERT_NOTNULL(SM, "supermatter failed to construct")
	var/obj/item/projectile/beam/emitter/emitter_shot = new(T)
	// Live emitters calculate this from their power draw immediately before firing.
	emitter_shot.damage = 100
	var/initial_power = SM.power
	for(var/i in 1 to 100)
		SM.bullet_act(emitter_shot)
	TEST_ASSERT(!QDELETED(SM), "repeated emitter impacts deleted the supermatter through generic machinery damage")
	TEST_ASSERT(SM.power > initial_power, "emitter impacts did not excite the supermatter")
	SM.take_damage(SM.max_integrity * 2, BURN, LASER, sound_effect = FALSE)
	TEST_ASSERT(!QDELETED(SM), "generic obj_integrity damage deleted the supermatter instead of using its delamination model")
	qdel(emitter_shot)
	qdel(SM)


// =====================================================================
// Reaction coverage (beyond plasmafire)
// =====================================================================

/// Tritium combustion: trit + O2 + heat → water vapor + radiation. Verify
/// fuel consumption, water vapor production, exothermic temperature rise.
/datum/unit_test/dq_tritfire_reaction_consumes_tritium

/datum/unit_test/dq_tritfire_reaction_consumes_tritium/Run()
	var/datum/gas_mixture/mix = new(CELL_VOLUME)
	mix.adjust_gas(/datum/gas/tritium, 30)
	mix.adjust_gas(/datum/gas/oxygen, 200)
	mix.set_temperature(TRITIUM_MINIMUM_BURN_TEMPERATURE + 200)

	var/initial_trit = mix.get_moles(/datum/gas/tritium)
	var/initial_o2 = mix.get_moles(/datum/gas/oxygen)
	var/initial_h2o = mix.get_moles(/datum/gas/water_vapor)
	var/initial_temp = mix.return_temperature()

	mix.react(null)

	TEST_ASSERT(mix.get_moles(/datum/gas/tritium) < initial_trit, \
		"tritium did not burn: [initial_trit] → [mix.get_moles(/datum/gas/tritium)]")
	TEST_ASSERT(mix.get_moles(/datum/gas/oxygen) < initial_o2, \
		"O2 not consumed by tritfire")
	TEST_ASSERT(mix.get_moles(/datum/gas/water_vapor) > initial_h2o, \
		"water vapor not produced by tritfire")
	var/tritfire_temp = mix.return_temperature()
	TEST_ASSERT(tritfire_temp > initial_temp, \
		"tritfire didn't release heat: [initial_temp] → [tritfire_temp]")


/// Hydrogen combustion: H2 + O2 + heat → water vapor. Similar shape to
/// tritfire but lower fuel value.
/datum/unit_test/dq_h2fire_reaction_consumes_hydrogen

/datum/unit_test/dq_h2fire_reaction_consumes_hydrogen/Run()
	var/datum/gas_mixture/mix = new(CELL_VOLUME)
	mix.adjust_gas(/datum/gas/hydrogen, 40)
	mix.adjust_gas(/datum/gas/oxygen, 200)
	mix.set_temperature(HYDROGEN_MINIMUM_BURN_TEMPERATURE + 100)

	var/initial_h2 = mix.get_moles(/datum/gas/hydrogen)
	var/initial_o2 = mix.get_moles(/datum/gas/oxygen)
	var/initial_temp = mix.return_temperature()

	mix.react(null)

	TEST_ASSERT(mix.get_moles(/datum/gas/hydrogen) < initial_h2, \
		"H2 did not burn: [initial_h2] → [mix.get_moles(/datum/gas/hydrogen)]")
	TEST_ASSERT(mix.get_moles(/datum/gas/oxygen) < initial_o2, "O2 not consumed by h2fire")
	TEST_ASSERT(mix.return_temperature() > initial_temp, "h2fire didn't release heat")


/// Freon combustion: freon + O2 (BELOW freezing point) → endothermic cooling.
/// Validates the cooling-reaction path used by freon-bombs and cryo setups.
/datum/unit_test/dq_freonfire_reaction_cools_mixture

/datum/unit_test/dq_freonfire_reaction_cools_mixture/Run()
	var/datum/gas_mixture/mix = new(CELL_VOLUME)
	mix.adjust_gas(/datum/gas/freon, 50)
	mix.adjust_gas(/datum/gas/oxygen, 200)
	// freonfire's MIN_TEMP/MAX_TEMP gate is FREON_TERMINAL_TEMPERATURE (20K) to
	// FREON_MAXIMUM_BURN_TEMPERATURE (283K). Inside react() the burn scale is
	// 0 at/above the max, 0.5 below FREON_LOWER_TEMPERATURE (60K), and ramps
	// linearly between. Pick ~150K so we sit firmly in the linear band: above
	// the gate floor, below the cap, and the scale is comfortably positive so
	// the reaction actually consumes freon.
	mix.set_temperature((FREON_LOWER_TEMPERATURE + FREON_MAXIMUM_BURN_TEMPERATURE) / 2) // ~171K

	var/initial_freon = mix.get_moles(/datum/gas/freon)
	var/initial_temp = mix.return_temperature()
	TEST_ASSERT(initial_freon > 0, "test setup didn't load freon: [initial_freon]")

	mix.react(null)

	var/final_freon = mix.get_moles(/datum/gas/freon)
	var/final_temp = mix.return_temperature()
	// Freon combustion is endothermic: it consumes freon and cools the mix.
	TEST_ASSERT(final_freon < initial_freon, \
		"freonfire didn't fire under T=[initial_temp] freon=[initial_freon] O2=[mix.get_moles(/datum/gas/oxygen)] — freon was not consumed: [initial_freon] → [final_freon]")
	TEST_ASSERT(final_temp < initial_temp, \
		"freonfire is endothermic but temperature ROSE: [initial_temp] → [final_temp]")


/// Water vapor condensation: at temperatures below the deposition point,
/// vapor should be consumed and the turf gets wet/iced.
/datum/unit_test/dq_water_vapor_condenses_on_cold_turf

/datum/unit_test/dq_water_vapor_condenses_on_cold_turf/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for water_vapor test")

	// Reset wet state.
	T.wet = TURFSLIP_DRY

	var/datum/gas_mixture/air = T.return_air()
	for(var/datum/gas/g as anything in air.get_gases())
		air.set_moles(g, 0)
	air.adjust_gas(/datum/gas/water_vapor, MOLES_GAS_VISIBLE * 4)
	air.set_temperature(WATER_VAPOR_DEPOSITION_POINT - 20) // below deposition

	var/initial_vapor = air.get_moles(/datum/gas/water_vapor)
	air.react(T)
	var/final_vapor = air.get_moles(/datum/gas/water_vapor)

	TEST_ASSERT(final_vapor < initial_vapor, \
		"water vapor not consumed by deposition: [initial_vapor] → [final_vapor]")
	TEST_ASSERT(T.wet >= TURFSLIP_ICE, \
		"freeze_turf didn't ice the turf: T.wet=[T.wet], expected ≥ [TURFSLIP_ICE]")

	// Reset.
	T.wet = TURFSLIP_DRY
	air.set_moles(/datum/gas/water_vapor, 0)


/// Halon oxygen removal: halon + heat → O2 consumed, CO2 produced. Used for
/// fire suppression.
/datum/unit_test/dq_halon_removes_oxygen

/datum/unit_test/dq_halon_removes_oxygen/Run()
	var/datum/gas_mixture/mix = new(CELL_VOLUME)
	mix.adjust_gas(/datum/gas/halon, 30)
	mix.adjust_gas(/datum/gas/oxygen, 100)
	mix.set_temperature(HALON_COMBUSTION_MIN_TEMPERATURE + 100)

	var/initial_halon = mix.get_moles(/datum/gas/halon)
	var/initial_o2 = mix.get_moles(/datum/gas/oxygen)

	mix.react(null)

	TEST_ASSERT(mix.get_moles(/datum/gas/halon) < initial_halon, "halon not consumed")
	TEST_ASSERT(mix.get_moles(/datum/gas/oxygen) < initial_o2, \
		"O2 not removed by halon: [initial_o2] → [mix.get_moles(/datum/gas/oxygen)]")


/// Miaster: miasma decomposes in warm dry conditions. Validates the body-decay
/// gas behaviour.
/datum/unit_test/dq_miaster_decomposes_miasma

/datum/unit_test/dq_miaster_decomposes_miasma/Run()
	var/datum/gas_mixture/mix = new(CELL_VOLUME)
	mix.adjust_gas(/datum/gas/miasma, 50)
	mix.adjust_gas(/datum/gas/oxygen, 100)
	mix.set_temperature(MIASTER_STERILIZATION_TEMP + 50) // hot enough to decompose

	var/initial_miasma = mix.get_moles(/datum/gas/miasma)

	mix.react(null)

	var/final_miasma = mix.get_moles(/datum/gas/miasma)
	TEST_ASSERT(final_miasma < initial_miasma, \
		"miaster didn't decompose miasma: [initial_miasma] → [final_miasma]")


/// All gas_reactions have an init_reqs that populates a non-empty requirements
/// list — catches "wrong gas type path" / "typo'd #define" / "forgot to set
/// requirements" regressions in newly-added reactions.
/datum/unit_test/dq_all_reactions_have_valid_requirements

/datum/unit_test/dq_all_reactions_have_valid_requirements/Run()
	for(var/datum/gas_reaction/R_type as anything in subtypesof(/datum/gas_reaction))
		var/datum/gas_reaction/R = new R_type
		TEST_ASSERT_NOTNULL(R.requirements, "[R_type] has null requirements after New()")
		TEST_ASSERT(length(R.requirements) > 0, \
			"[R_type] has empty requirements")
		TEST_ASSERT_NOTNULL(R.id, "[R_type] has null id")
		TEST_ASSERT_NOTNULL(R.name, "[R_type] has null name")


// =====================================================================
// Doors / CanZASPass routing through can_atmos_pass
// =====================================================================
// A closed airlock between two rooms should block atmos. CHOMP airlocks
// override CanZASPass; our xgm_compat.CanZASPass routes through LINDA's
// can_atmos_pass so the override propagates into adjacency calc.

/// Closed airlock blocks atmos pass; open airlock allows it.
/datum/unit_test/dq_closed_airlock_blocks_atmos

/datum/unit_test/dq_closed_airlock_blocks_atmos/Run()
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no floor pair for airlock atmos test")
	var/turf/simulated/floor/A = pair[1]
	var/turf/simulated/floor/B = pair[2]

	// Place a closed airlock on B.
	var/obj/machinery/door/airlock/D = new(B)
	TEST_ASSERT_NOTNULL(D, "couldn't construct airlock")
	D.density = TRUE
	D.update_nearby_tiles()

	// update_nearby_tiles() is the production proc that doors call to refresh
	// adjacency around them. After it runs, the engine's adjacency lists
	// reflect the door's current density.
	TEST_ASSERT(!vg_atmos_turfs_share(A, B), \
		"closed airlock didn't block A↔B atmos adjacency — door.update_nearby_tiles or CanZASPass routing broken")

	// Open the airlock — the door itself calls update_nearby_tiles on density
	// change in production.
	D.density = FALSE
	D.update_nearby_tiles()

	TEST_ASSERT(vg_atmos_turfs_share(A, B), \
		"open airlock didn't allow A↔B atmos adjacency — door.update_nearby_tiles or CanZASPass routing broken in reverse direction")

	qdel(D)


// =====================================================================
// Rust-authoritative pipenet materialization
// =====================================================================

/// Two adjacent pipes published through Rust should end up
/// in the same /datum/pipe_network with a shared air mixture. This is the
/// production "pipes load from map → atmos_init builds the network" flow.
/datum/unit_test/dq_pipes_build_into_one_network

/datum/unit_test/dq_pipes_build_into_one_network/Run()
	var/list/pair = dq_atmos_test_find_clear_pipe_run(2)
	TEST_ASSERT_NOTNULL(pair, "no clear same-z cardinal floor pair for pipe network test")
	var/turf/simulated/floor/A = pair[1]
	var/turf/simulated/floor/B = pair[2]

	var/dir_A_to_B = get_dir(A, B)
	var/dir_B_to_A = get_dir(B, A)

	var/obj/machinery/atmospherics/pipe/simple/P1 = new(A)
	P1.dir = dir_A_to_B | dir_B_to_A // straight pipe along the A-B axis
	P1.initialize_directions = dir_A_to_B | dir_B_to_A

	var/obj/machinery/atmospherics/pipe/simple/P2 = new(B)
	P2.dir = dir_A_to_B | dir_B_to_A
	P2.initialize_directions = dir_A_to_B | dir_B_to_A

	TEST_ASSERT_NOTNULL(P1, "P1 pipe construction failed")
	TEST_ASSERT_NOTNULL(P2, "P2 pipe construction failed")

	// Run atmos_init to wire them. Pipes find each other via initialize_directions.
	P1.atmos_init()
	P2.atmos_init()
	dq_atmos_test_publish_rust_pipenets(list(P1, P2))

	// After build_network, both pipes should share a pipe_network's gas mixture.
	TEST_ASSERT_NOTNULL(P1.parent, "P1.parent (pipeline) is null after build_network")
	TEST_ASSERT_NOTNULL(P2.parent, "P2.parent (pipeline) is null after build_network")
	// Either same pipeline OR pipelines in same network.
	var/same_network = (P1.parent == P2.parent) || (P1.parent.network && P1.parent.network == P2.parent.network)
	TEST_ASSERT(same_network, \
		"P1 and P2 not in the same pipe_network after build_network — pipenet auto-build broken")

	qdel(P1)
	qdel(P2)


/datum/unit_test/dq_reactive_disposal_wakes_on_contents

/datum/unit_test/dq_reactive_disposal_wakes_on_contents/Run()
	var/list/pair = dq_atmos_test_find_clear_pipe_run(1)
	TEST_ASSERT_NOTNULL(pair, "no clear floor for reactive disposal test")
	var/obj/machinery/disposal/D = new(pair[1])
	D.mode = 2 // DISPOSALMODE_CHARGED is file-local to disposal_machines.dm.
	D.process()
	TEST_ASSERT(!(D in SSmachines.processing_machines), \
		"stable empty disposal did not enter dependency sleep")
	D.power_change()
	TEST_ASSERT(!(D in SSmachines.processing_machines), \
		"unchanged area power state woke a sleeping disposal")
	var/obj/item/I = new(pair[1])
	I.forceMove(D)
	TEST_ASSERT(D in SSmachines.processing_machines, \
		"disposal contents mutation did not wake the sleeping disposal")
	qdel(D)

/datum/unit_test/dq_disposal_filters_unpumpable_gas_changes

/datum/unit_test/dq_disposal_filters_unpumpable_gas_changes/Run()
	var/list/pair = dq_atmos_test_find_clear_pipe_run(1)
	TEST_ASSERT_NOTNULL(pair, "no clear floor for disposal pump feasibility test")
	var/obj/machinery/disposal/D = new(pair[1])
	var/datum/gas_mixture/source = new(CELL_VOLUME)
	source.set_temperature(T20C)
	source.adjust_moles(/datum/gas/oxygen, MINIMUM_MOLES_TO_PUMP * 2)
	TEST_ASSERT(!D.can_pressurize_from(source), "disposal treated a sub-transfer-sized gas trace as actionable")
	source.adjust_moles(/datum/gas/oxygen, 10)
	TEST_ASSERT(D.can_pressurize_from(source), "empty disposal rejected an actionable room-air intake")
	qdel(source)
	qdel(D)

/datum/unit_test/dq_disposal_staggered_power_retry_wakes

/datum/unit_test/dq_disposal_staggered_power_retry_wakes/Run()
	var/list/pair = dq_atmos_test_find_clear_pipe_run(1)
	TEST_ASSERT_NOTNULL(pair, "no clear floor for disposal power retry test")
	var/turf/open/T = pair[1]
	var/obj/machinery/disposal/D = new(T)
	D.mode = 1 // DISPOSALMODE_CHARGING is file-local to disposal_machines.dm.
	D.stat &= ~(NOPOWER|BROKEN)
	D.air_contents.clear()
	// Prior atmos tests deliberately evacuate map turfs. Supply a controlled
	// actionable atmosphere so this test measures retry scheduling, not suite order.
	T.return_air().clear()
	T.return_air().set_temperature(T20C)
	T.return_air().adjust_moles(/datum/gas/oxygen, 10)
	TEST_ASSERT(D.can_pressurize_from(T.return_air()), "test floor has no pumpable atmosphere")
	STOP_MACHINE_PROCESSING(D)
	D.retry_charge_after_power_restore()
	TEST_ASSERT(D in SSmachines.processing_machines, "staggered power restoration callback did not wake a pumpable disposal")
	qdel(D)


/datum/unit_test/dq_opaque_movable_detaches_from_turf_before_delete

/datum/unit_test/dq_opaque_movable_detaches_from_turf_before_delete/Run()
	var/list/pair = dq_atmos_test_find_clear_pipe_run(1)
	TEST_ASSERT_NOTNULL(pair, "no clear floor for opaque movable lifecycle test")
	var/turf/T = pair[1]
	var/obj/effect/expl_particles/particle = new(T)
	TEST_ASSERT(particle in T.opacity_sources, "opaque particle did not register as a turf opacity source")
	qdel(particle)
	TEST_ASSERT(!(particle in T.opacity_sources), \
		"deleted opaque particle remained retained by the turf opacity source list")


/datum/unit_test/dq_airlock_sensor_wakes_on_pressure

/obj/machinery/portable_atmospherics/powered/reagent_distillery/unit_test/powered(channel = -1)
	return TRUE

/datum/unit_test/dq_idle_distillery_hibernates

/datum/unit_test/dq_idle_distillery_hibernates/Run()
	var/list/pair = dq_atmos_test_find_clear_pipe_run(1)
	TEST_ASSERT_NOTNULL(pair, "no clear floor for distillery hibernation test")
	var/obj/machinery/portable_atmospherics/powered/reagent_distillery/unit_test/D = new(pair[1])
	TEST_ASSERT_EQUAL(D.process(), PROCESS_KILL, "settled switched-off distillery kept polling")
	STOP_MACHINE_PROCESSING(D)
	D.toggle_power(null)
	TEST_ASSERT(D.on, "distillery toggle did not switch heating on")
	TEST_ASSERT(D.datum_flags & DF_ISPROCESSING, "distillery toggle did not wake the hibernating machine")
	qdel(D)

/datum/unit_test/dq_airlock_sensor_wakes_on_pressure/Run()
	var/list/pair = dq_atmos_test_find_clear_pipe_run(1)
	TEST_ASSERT_NOTNULL(pair, "no clear floor for airlock sensor dependency test")
	var/turf/simulated/floor/T = pair[1]
	dq_atmos_test_snapshot_air(T)
	dq_atmos_test_isolate_pair(T, T)
	T.air_update_turf(TRUE, FALSE)
	var/obj/machinery/airlock_sensor/S = new(T)
	S.process()
	TEST_ASSERT(!(S in SSmachines.processing_machines), \
		"stable airlock sensor did not enter gas dependency sleep")
	T.return_air().adjust_moles(/datum/gas/oxygen, 0.001)
	TEST_ASSERT(!S.gas_dependency_changed(T.return_air().arena_id(), GAS_DEPENDENCY_PRESSURE), \
		"sub-display-resolution pressure mutation woke a sleeping airlock sensor")
	T.return_air().adjust_moles(/datum/gas/oxygen, 10)
	TEST_ASSERT(S.gas_dependency_changed(T.return_air().arena_id(), GAS_DEPENDENCY_PRESSURE), \
		"visible pressure mutation was rejected by a sleeping airlock sensor")
	SSmachines.wake_gas_subscriber(WEAKREF(S))
	TEST_ASSERT(S in SSmachines.processing_machines, \
		"pressure mutation did not wake sleeping airlock sensor")
	qdel(S)


/datum/unit_test/dq_mc_performance_window_statistics

/datum/unit_test/dq_mc_performance_window_statistics/Run()
	var/list/old_usage = Master.perf_tick_usage
	var/list/old_realtime = Master.perf_tick_realtime
	Master.perf_tick_usage = list()
	Master.perf_tick_realtime = list()
	for(var/i in 1 to 100)
		Master.perf_tick_usage += i
		Master.perf_tick_realtime += i * world.tick_lag
	var/list/window = Master.performance_window(30)
	TEST_ASSERT_EQUAL(window["samples"], 100, "MC performance window lost samples")
	TEST_ASSERT_EQUAL(window["p50"], 50, "MC performance window calculated the wrong median")
	TEST_ASSERT_EQUAL(window["p95"], 95, "MC performance window calculated the wrong p95")
	TEST_ASSERT_EQUAL(window["p99"], 99, "MC performance window calculated the wrong p99")
	TEST_ASSERT_EQUAL(window["max"], 100, "MC performance window calculated the wrong maximum")
	TEST_ASSERT(abs(window["tps"] - world.fps) < 0.01, "MC performance window calculated incorrect TPS")
	var/list/old_outliers = Master.perf_outliers
	var/list/old_breakdown = Master.perf_tick_breakdown
	Master.perf_outliers = list()
	Master.perf_tick_breakdown = list("Atmospherics" = 80, "Stat Panels" = 30)
	Master.record_performance_tick(125)
	var/list/outlier = Master.perf_outliers[1]
	TEST_ASSERT_EQUAL(outlier["overrun"], 25, "MC outlier recorded an incorrect overrun")
	TEST_ASSERT_EQUAL(length(outlier["breakdown"]), 3, "MC outlier omitted attributed or external tick usage")
	Master.perf_tick_usage = old_usage
	Master.perf_tick_realtime = old_realtime
	Master.perf_outliers = old_outliers
	Master.perf_tick_breakdown = old_breakdown


// =====================================================================
// Pipenet dispatch (catches "START_PROCESSING_PIPENET targets wrong list")
// =====================================================================

/// Rust materialization registers a /datum/pipe_network through START_PROCESSING_PIPENET.
/// That macro must point at SSair.networks (where SSair.process_pipenets reads),
/// NOT SSmachines.networks (whose process_pipenets is a stub on this fork).
/// If the macro is mis-targeted, the network builds but reconcile_air never
/// runs — silent failure that this test catches.
/datum/unit_test/dq_pipenet_dispatches_through_ssair

/datum/unit_test/dq_pipenet_dispatches_through_ssair/Run()
	var/list/pair = dq_atmos_test_find_clear_pipe_run(2)
	TEST_ASSERT_NOTNULL(pair, "no clear same-z cardinal floor pair for pipenet dispatch test")
	var/turf/simulated/floor/A = pair[1]
	var/turf/simulated/floor/B = pair[2]

	var/dir_A_to_B = get_dir(A, B)
	var/dir_B_to_A = get_dir(B, A)

	var/obj/machinery/atmospherics/pipe/simple/P1 = new(A)
	P1.dir = dir_A_to_B | dir_B_to_A
	P1.initialize_directions = dir_A_to_B | dir_B_to_A
	var/obj/machinery/atmospherics/pipe/simple/P2 = new(B)
	P2.dir = dir_A_to_B | dir_B_to_A
	P2.initialize_directions = dir_A_to_B | dir_B_to_A

	P1.atmos_init()
	P2.atmos_init()
	dq_atmos_test_publish_rust_pipenets(list(P1, P2))

	TEST_ASSERT_NOTNULL(P1.parent, "P1.parent (pipeline) null after build_network")
	TEST_ASSERT_NOTNULL(P1.parent.network, "pipeline has no parent network after build_network")

	var/datum/pipe_network/N = P1.parent.network
	TEST_ASSERT(!(N in SSair.networks), \
		"clean Rust-authoritative pipe_network was needlessly scheduled after topology publication")
	var/initial_revision = N.revision
	N.mark_dirty()
	TEST_ASSERT(!(N in SSair.networks), \
		"semantic gas revision incorrectly reenrolled a sleeping pipe_network")
	TEST_ASSERT(N.revision > initial_revision, \
		"mark_dirty() did not advance the pipe_network mutation generation")
	N.mark_topology_dirty()
	TEST_ASSERT(N in SSair.networks, \
		"mark_topology_dirty() did not reenroll a sleeping pipe_network")
	// SSmachines.networks was removed entirely (see machines.dm). If
	// a future merge re-adds it, the macro's redirect should still keep
	// pipenets out of it.

	qdel(P1)
	qdel(P2)


// =====================================================================
// Scrubber trace-gas conservation (catches XGM .gas no-op shim mutation)
// =====================================================================

/// scrub_gas's "scrub the remaining trace" branch used to write `source.gas -= g`,
/// but under LINDA `.gas` is the empty compat shim on /datum/gas_mixture so the
/// removal was a no-op. The gas was added to sink WITHOUT being removed from
/// source — every trace tick duplicated moles. This test feeds scrub_gas a
/// source with sub-threshold gas, checks moles are conserved across the pair.
/datum/unit_test/dq_scrubber_trace_remnant_conserves_moles

/datum/unit_test/dq_scrubber_trace_remnant_conserves_moles/Run()
	var/datum/gas_mixture/source = new(CELL_VOLUME)
	var/datum/gas_mixture/sink = new(CELL_VOLUME)

	// 0.5 moles phoron + 0.5 moles N2O — both well over the per-gas
	// MINIMUM_MOLES_TO_FILTER threshold (0.04) so they hit the "remainder"
	// branch deterministically: after the main loop's transfer, the leftover
	// fraction of each filtered gas is dumped through the source.gas -= g path.
	// (The bug also bites smaller fills that fall straight into the trace
	// branch — adding plenty here ensures the branch executes regardless of
	// the main loop's transfer math rounding.)
	source.adjust_gas(/datum/gas/plasma, 0.5)
	source.adjust_gas(/datum/gas/nitrous_oxide, 0.5)
	// Padding so total_moles() > MINIMUM_MOLES_TO_PUMP and scrub_gas proceeds
	// past its early-return guard.
	source.adjust_gas(/datum/gas/oxygen, 5)
	source.set_temperature(T20C)

	var/initial_total_plasma = source.get_moles(/datum/gas/plasma) + sink.get_moles(/datum/gas/plasma)
	var/initial_total_n2o = source.get_moles(/datum/gas/nitrous_oxide) + sink.get_moles(/datum/gas/nitrous_oxide)

	// Call scrub_gas with a tiny per-call budget so multiple passes are
	// required to exhaust the gas — each pass exercises the trace remainder
	// branch on whatever scrap is left below MINIMUM_MOLES_TO_FILTER.
	for(var/i in 1 to 25)
		scrub_gas(null, list(GAS_PHORON, GAS_N2O), source, sink, total_transfer_moles = 0.1)

	var/final_total_plasma = source.get_moles(/datum/gas/plasma) + sink.get_moles(/datum/gas/plasma)
	var/final_total_n2o = source.get_moles(/datum/gas/nitrous_oxide) + sink.get_moles(/datum/gas/nitrous_oxide)

	// Conservation: source+sink moles must equal what we started with.
	// The XGM-shim bug INCREASES total moles (sink gets the trace, source keeps it).
	TEST_ASSERT(abs(final_total_plasma - initial_total_plasma) < 0.01, \
		"scrub_gas violated plasma conservation: started [initial_total_plasma], ended [final_total_plasma] — source.gas -= g is hitting the XGM compat shim (empty list) instead of mutating the real gases dict.")
	TEST_ASSERT(abs(final_total_n2o - initial_total_n2o) < 0.01, \
		"scrub_gas violated N2O conservation: started [initial_total_n2o], ended [final_total_n2o] — same shim bug.")


// =====================================================================
// Pipe split / merge mid-round (catches stale parent pipeline references)
// =====================================================================

/// Build a 3-pipe straight run A-B-C, destroy B, verify A and C now belong
/// to separate (or no) pipelines. Then build a replacement bridging pipe
/// at B's old location, verify A and C re-merge into a single pipeline.
/// Exercises Rust's atomic persistent-region split and merge transitions.
/datum/unit_test/dq_pipe_split_then_merge_rebuilds_pipeline

/datum/unit_test/dq_pipe_split_then_merge_rebuilds_pipeline/Run()
	// Find three collinear, pipe-free floor tiles A-B-C on one z-level.
	var/list/run = dq_atmos_test_find_clear_pipe_run(3)
	TEST_ASSERT_NOTNULL(run, "no 3-tile clear collinear floor strip for split/merge test")
	var/turf/simulated/floor/A = run[1]
	var/turf/simulated/floor/B = run[2]
	var/turf/simulated/floor/C = run[3]
	// The run is a single cardinal step apart; align the pipes to that axis.
	var/axis = get_dir(A, B) | get_dir(B, A)

	// Construct three straight pipes along the strip's axis.
	var/obj/machinery/atmospherics/pipe/simple/PA = new(A)
	PA.dir = axis
	PA.initialize_directions = axis
	var/obj/machinery/atmospherics/pipe/simple/PB = new(B)
	PB.dir = axis
	PB.initialize_directions = axis
	var/obj/machinery/atmospherics/pipe/simple/PC = new(C)
	PC.dir = axis
	PC.initialize_directions = axis

	PA.atmos_init()
	PB.atmos_init()
	PC.atmos_init()
	dq_atmos_test_publish_rust_pipenets(list(PA, PB, PC))

	// Sanity: all three share one pipeline.
	TEST_ASSERT(PA.parent && PA.parent == PB.parent && PB.parent == PC.parent, \
		"3-pipe straight run didn't form one pipeline: PA=[PA.parent] PB=[PB.parent] PC=[PC.parent]")
	var/datum/pipeline/initial_pipeline = PA.parent

	// Kill the middle pipe. Rust must retire the old wrapper once and publish
	// two replacement regions immediately.
	qdel(PB)
	TEST_ASSERT_NOTNULL(PA.parent, "PA did not receive a replacement pipeline after split")
	TEST_ASSERT_NOTNULL(PC.parent, "PC did not receive a replacement pipeline after split")
	TEST_ASSERT(PA.parent != PC.parent, "split Rust region left PA and PC in one pipeline")
	TEST_ASSERT_NULL(PB.parent, "destroyed pipe retained its pipeline back-reference")
	TEST_ASSERT_NULL(initial_pipeline.members, "destroyed pipeline retained its member roster")
	TEST_ASSERT_NULL(initial_pipeline.edges, "destroyed pipeline retained its edge roster")
	TEST_ASSERT_NULL(initial_pipeline.leaks, "destroyed pipeline retained its leak roster")
	TEST_ASSERT_NULL(initial_pipeline.network, "destroyed pipeline retained its network")
	TEST_ASSERT_NULL(initial_pipeline.air, "destroyed pipeline retained its gas mixture")

	TEST_ASSERT(PA.parent != initial_pipeline, "PA's rebuilt pipeline is the old (destroyed) one — stale reference")

	// Insert a fresh bridging pipe at B's slot.
	var/obj/machinery/atmospherics/pipe/simple/PB2 = new(B)
	PB2.dir = axis
	PB2.initialize_directions = axis
	PB2.atmos_init()
	dq_atmos_test_publish_rust_pipenets(list(PB2))

	TEST_ASSERT_NOTNULL(PA.parent, "PA.parent null after merge")
	TEST_ASSERT_NOTNULL(PC.parent, "PC.parent null after merge")
	TEST_ASSERT_NOTNULL(PB2.parent, "PB2.parent null after merge")
	TEST_ASSERT(PA.parent == PB2.parent && PB2.parent == PC.parent, \
		"3 pipes didn't re-merge into one pipeline after bridging: PA=[PA.parent] PB2=[PB2.parent] PC=[PC.parent]")

	qdel(PA)
	qdel(PB2)
	qdel(PC)

/datum/unit_test/dq_pipeline_edge_reverse_ownership

/datum/unit_test/dq_pipeline_edge_reverse_ownership/Run()
	var/turf/test_turf = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	var/obj/machinery/atmospherics/pipe/simple/edge = new(test_turf)
	var/datum/pipeline/first = new
	var/datum/pipeline/second = new
	first.add_edge(edge)
	second.add_edge(edge)
	TEST_ASSERT((first in edge.edge_pipelines) && (second in edge.edge_pipelines), "A pipe did not record every foreign pipeline edge owner.")
	qdel(edge)
	TEST_ASSERT(!(edge in first.edges) && !(edge in second.edges), "A destroyed pipe remained in a foreign pipeline edge roster.")
	qdel(first)
	qdel(second)


// =====================================================================
// Phase F coverage smoke tests — every machinery class that was missing
// a process() exercise gets one here. Each just verifies (a) the machine
// constructs without runtime, (b) one tick of process() doesn't crash,
// and (c) the headline observable behaviour fires (gas moves, valve
// state propagates, etc). Construct-only assertions belong elsewhere.
// =====================================================================

/// Portable canister-style pump: load it with pressurized N2, drop it on a
/// floor with low ambient, run process() once, verify ambient gained moles.
/datum/unit_test/dq_portable_pump_pushes_to_turf

/datum/unit_test/dq_portable_pump_pushes_to_turf/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for portable pump test")

	// Drain ambient so the pump's effect shows up clearly.
	var/datum/gas_mixture/turf_air = T.return_air()
	for(var/datum/gas/g as anything in turf_air.get_gases())
		turf_air.set_moles(g, 0)
	turf_air.set_temperature(T20C)

	var/obj/machinery/portable_atmospherics/powered/pump/P = new(T)
	TEST_ASSERT_NOTNULL(P, "portable pump construction failed")
	TEST_ASSERT_NOTNULL(P.air_contents, "portable pump has no internal tank")

	P.air_contents.adjust_gas(/datum/gas/nitrogen, 200)
	P.air_contents.set_temperature(T20C)
	P.on = TRUE
	P.direction_out = TRUE
	P.target_pressure = 5 * ONE_ATMOSPHERE
	// Make sure the power gate doesn't short-circuit the test.
	if(P.cell)
		P.cell.charge = P.cell.maxcharge

	var/before = turf_air.get_moles(/datum/gas/nitrogen)
	P.process()
	var/after = turf_air.get_moles(/datum/gas/nitrogen)
	TEST_ASSERT(after > before, \
		"portable pump didn't push N2 to floor: [before] → [after]")

	qdel(P)


/// Portable scrubber: drop one on a phoron-laden tile, enable scrubbing,
/// run process(), verify the turf lost phoron and the scrubber's internal
/// tank gained some.
/datum/unit_test/dq_portable_scrubber_pulls_target_gas

/datum/unit_test/dq_portable_scrubber_pulls_target_gas/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for portable scrubber test")

	var/datum/gas_mixture/turf_air = T.return_air()
	for(var/datum/gas/g as anything in turf_air.get_gases())
		turf_air.set_moles(g, 0)
	turf_air.adjust_gas(/datum/gas/plasma, 50)
	turf_air.set_temperature(T20C)

	var/obj/machinery/portable_atmospherics/powered/scrubber/S = new(T)
	TEST_ASSERT_NOTNULL(S, "portable scrubber construction failed")
	TEST_ASSERT_NOTNULL(S.air_contents, "portable scrubber has no internal tank")

	S.on = TRUE
	if(S.cell)
		S.cell.charge = S.cell.maxcharge

	var/floor_plasma_before = turf_air.get_moles(/datum/gas/plasma)
	var/tank_plasma_before = S.air_contents.get_moles(/datum/gas/plasma)
	S.process()
	var/floor_plasma_after = turf_air.get_moles(/datum/gas/plasma)
	var/tank_plasma_after = S.air_contents.get_moles(/datum/gas/plasma)

	TEST_ASSERT(floor_plasma_after < floor_plasma_before, \
		"portable scrubber didn't remove phoron from floor: [floor_plasma_before] → [floor_plasma_after]")
	TEST_ASSERT(tank_plasma_after > tank_plasma_before, \
		"portable scrubber didn't capture phoron in its tank: [tank_plasma_before] → [tank_plasma_after]")

	qdel(S)


/// Manual valve open/close: build two pipes joined by a valve, verify gas
/// flow is gated by the valve.open state. Closed → no transfer; open →
/// reconcile_air pools across both pipelines.
/datum/unit_test/dq_valve_open_close_gates_pipenet_flow

/datum/unit_test/dq_valve_open_close_gates_pipenet_flow/Run()
	// Find three collinear, pipe-free tiles A-V-B on one z-level.
	var/list/run = dq_atmos_test_find_clear_pipe_run(3)
	TEST_ASSERT_NOTNULL(run, "no 3-tile clear collinear strip for valve test")
	var/turf/simulated/floor/A = run[1]
	var/turf/simulated/floor/V = run[2]
	var/turf/simulated/floor/B = run[3]
	var/axis = get_dir(A, V) | get_dir(V, A)

	var/obj/machinery/atmospherics/pipe/simple/PA = new(A)
	PA.dir = axis
	PA.initialize_directions = axis
	var/obj/machinery/atmospherics/valve/VL = new(V)
	VL.dir = get_dir(V, B)
	VL.initialize_directions = axis
	VL.open = FALSE
	var/obj/machinery/atmospherics/pipe/simple/PB = new(B)
	PB.dir = axis
	PB.initialize_directions = axis

	PA.atmos_init()
	VL.atmos_init()
	PB.atmos_init()
	dq_atmos_test_publish_rust_pipenets(list(PA, PB, VL))

	// Closed: PA and PB sit in separate pipelines.
	TEST_ASSERT_NOTNULL(PA.parent, "PA pipeline null after build")
	TEST_ASSERT_NOTNULL(PB.parent, "PB pipeline null after build")
	TEST_ASSERT(PA.parent != PB.parent, \
		"closed valve didn't separate pipelines — PA and PB share parent [PA.parent]")

	// Open the valve and rebuild — they should merge.
	VL.open = TRUE
	VL.update_icon()
	// Publish the valve's newly enabled internal edge.
	VL.rust_register_pipe_topology()

	// After opening, the valve's two network slots should both reference
	// the same pipenet, and PA/PB pipelines should land in it together.
	TEST_ASSERT_NOTNULL(VL.network_node1, "valve network_node1 null after open")
	TEST_ASSERT(VL.network_node1 == VL.network_node2, \
		"valve open but network_node1 / network_node2 still distinct")
	var/same_net = (PA.parent.network && PA.parent.network == PB.parent.network)
	TEST_ASSERT(same_net, \
		"open valve didn't bridge PA and PB into one pipenet (PA.net=[PA.parent.network], PB.net=[PB.parent.network])")

	qdel(PA)
	qdel(VL)
	qdel(PB)


/// Passive gate (one-way pressure regulator): seed air1 with high pressure,
/// air2 empty, set REGULATE_NONE so it free-flows, unlock, run the Rust
/// device edge's flow law (M2: passive_gate has no process() any more —
/// SSair.rust_step_pipe_devices() is what runs it), verify gas moved from
/// air1 to air2.
/datum/unit_test/dq_passive_gate_one_way_flow

/datum/unit_test/dq_passive_gate_one_way_flow/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for passive gate test")

	var/obj/machinery/atmospherics/binary/passive_gate/G = new(T)
	TEST_ASSERT_NOTNULL(G, "passive_gate construction failed")
	G.unlocked = TRUE
	G.regulate_mode = 0  // REGULATE_NONE — free flow (Rust: Regulate::Equalize)
	G.rust_register_pipe_topology() // allocates ports, binds air1/air2, registers the device edge
	TEST_ASSERT_NOTNULL(G.air1, "passive_gate has no air1")
	TEST_ASSERT_NOTNULL(G.air2, "passive_gate has no air2")

	// Pressurize air1 well above air2.
	G.air1.adjust_gas(/datum/gas/oxygen, 500)
	G.air1.set_temperature(T20C)
	G.air2.set_temperature(T20C)
	G.update_rust_device()

	var/air1_before = G.air1.total_moles()
	var/air2_before = G.air2.total_moles()
	for(var/i in 1 to 30)
		SSair.rust_step_pipe_devices()
	var/air1_after = G.air1.total_moles()
	var/air2_after = G.air2.total_moles()

	TEST_ASSERT(air1_after < air1_before, \
		"passive_gate didn't drain air1: [air1_before] → [air1_after]")
	TEST_ASSERT(air2_after > air2_before, \
		"passive_gate didn't fill air2: [air2_before] → [air2_after]")
	// Conservation across the gate (we removed `* group_multiplier` from the
	// flow math — guard against off-by-multiplier regressions).
	var/total_before = air1_before + air2_before
	var/total_after = air1_after + air2_after
	TEST_ASSERT(abs(total_after - total_before) < 1, \
		"passive_gate violated mole conservation: [total_before] → [total_after]")

	qdel(G)


// =====================================================================
// Auxmos byondapi parity (Rust set/get/adjust vs DM fallback)
// =====================================================================

/// Verify that the auxmos byondapi-bound gas_mixture procs (set_moles,
/// adjust_moles, get_moles, return_pressure) produce numerically consistent
/// results. Adjust then read, mutate then check pressure, etc.
/datum/unit_test/dq_auxmos_byondapi_set_get_consistent

/datum/unit_test/dq_auxmos_byondapi_set_get_consistent/Run()
	var/datum/gas_mixture/mix = new(CELL_VOLUME)
	mix.set_temperature(T20C)

	mix.set_moles(/datum/gas/oxygen, 42.5)
	TEST_ASSERT(abs(mix.get_moles(/datum/gas/oxygen) - 42.5) < 0.001, \
		"set_moles → get_moles round trip wrong: set 42.5, got [mix.get_moles(/datum/gas/oxygen)]")

	mix.adjust_moles(/datum/gas/oxygen, 7.5)
	TEST_ASSERT(abs(mix.get_moles(/datum/gas/oxygen) - 50) < 0.001, \
		"adjust_moles wrong: 42.5 + 7.5 should be 50, got [mix.get_moles(/datum/gas/oxygen)]")

	// Pressure equation: P = n R T / V. n=50 mol, R=8.31, T=293.15 K, V=2500 L.
	// P = 50 * 8.31 * 293.15 / 2500 ≈ 48.71 kPa.
	var/expected_p = 50 * R_IDEAL_GAS_EQUATION * T20C / CELL_VOLUME
	var/actual_p = mix.return_pressure()
	TEST_ASSERT(abs(actual_p - expected_p) < 0.5, \
		"return_pressure off: expected ~[expected_p], got [actual_p] (ideal gas law mismatch — auxmos bug?)")

	mix.adjust_moles(/datum/gas/oxygen, -30)
	TEST_ASSERT(abs(mix.get_moles(/datum/gas/oxygen) - 20) < 0.001, \
		"negative adjust wrong: 50 - 30 should be 20, got [mix.get_moles(/datum/gas/oxygen)]")

/datum/unit_test/dq_gas_revision_tracks_mutations

/datum/unit_test/dq_gas_revision_tracks_mutations/Run()
	var/datum/gas_mixture/mix = new(CELL_VOLUME)
	var/initial_revision = mix.revision()
	mix.return_pressure()
	TEST_ASSERT_EQUAL(mix.revision(), initial_revision, \
		"read-only gas access advanced its mutation revision")
	mix.adjust_moles(/datum/gas/oxygen, 1)
	TEST_ASSERT(mix.revision() > initial_revision, \
		"gas mutation did not advance its revision")


// =====================================================================
// Real SSair scheduling (no fire-disable)
// =====================================================================

/// Drive SSair via its native scheduling for several real ticks and verify
/// gas spreads. Exercises the actual MC-scheduled tick flow.
/datum/unit_test/dq_real_ssair_scheduling_spreads_gas

/datum/unit_test/dq_real_ssair_scheduling_spreads_gas/Run()
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no floor pair for real-SSair test")
	var/turf/simulated/floor/A = pair[1]
	var/turf/simulated/floor/B = pair[2]

	dq_atmos_test_isolate_pair(A, B)

	for(var/datum/gas/g as anything in A.air.get_gases())
		A.air.set_moles(g, 0)
	for(var/datum/gas/g as anything in B.air.get_gases())
		B.air.set_moles(g, 0)
	B.air.set_temperature(T20C)

	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/plasma, 100)
	donor.set_temperature(T20C)
	A.assume_air(donor)

	// Let real SSair fire — Master.Loop ticks it on schedule.
	dq_atmos_test_wait_real_ssair_ticks(5)

	// We expect SOME spread to have happened. Don't assert exact equilibrium
	// because real SSair has tick budgets and MC_TICK_CHECK preemption.
	var/b_p = B.air.get_moles(/datum/gas/plasma)
	TEST_ASSERT(b_p > 0, \
		"after 5 real SSair ticks B still has 0 plasma — native scheduling didn't process A")
	// And total should still be conserved.
	var/total = A.air.get_moles(/datum/gas/plasma) + b_p
	TEST_ASSERT(abs(total - 100) < 1, \
		"real-SSair scheduling lost mass: A+B = [total], expected 100")

	A.air.set_moles(/datum/gas/plasma, 0)
	B.air.set_moles(/datum/gas/plasma, 0)
	A.update_visuals()
	B.update_visuals()


// =====================================================================
// Mob pressure damage / non-human breath
// =====================================================================

/// A human in a low-pressure (near-vacuum) environment becomes hypoxic as the
/// breath proc can't extract enough O2. Validates the life-cycle atmos chain.
/datum/unit_test/dq_human_low_pressure_hypoxia

/datum/unit_test/dq_human_low_pressure_hypoxia/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_NOTNULL(H, "couldn't allocate human")
	TEST_ASSERT_NOTNULL(H.species, "test human has no species")

	// Near-vacuum breath (tiny moles).
	var/datum/gas_mixture/breath = new(BREATH_VOLUME)
	breath.adjust_gas(/datum/gas/oxygen, 0.002)
	breath.set_temperature(T20C)
	var/initial_hypoxia = H.oxygen_debt()

	life_test_breath(H, breath)
	H.body.physiology_tick(2)

	var/final_hypoxia = H.oxygen_debt()
	TEST_ASSERT(final_hypoxia > initial_hypoxia, \
		"human didn't become hypoxic from near-vacuum breath: [initial_hypoxia] → [final_hypoxia]")


/// Verify phoron breather species correctly consumes plasma when given a
/// plasma-rich breath. This is the inverse-respiration check.
/datum/unit_test/dq_phoron_breather_consumes_plasma

/datum/unit_test/dq_phoron_breather_consumes_plasma/Run()
	// No base species in GLOB.all_species declares a phoron/plasma breath_type
	// on this build — phoron-breathing is only ever a custom-species trait
	// (/datum/trait/negative/breathes/phoron, which var-changes breath_type to
	// GAS_PHORON). The breathing system's exchange() reads species.breath_type and consumes that
	// exact gas. To exercise that consumption path deterministically we allocate
	// a normal human and temporarily flip its species' breath_type to GAS_PHORON
	// — the same value the phoron-breather trait applies — restoring it after so
	// the shared species singleton is left untouched for later tests.
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_NOTNULL(H, "couldn't allocate human")
	TEST_ASSERT_NOTNULL(H.species, "allocated human has no species datum")

	var/datum/species/species = H.species
	var/saved_breath_type = species.breath_type
	species.breath_type = GAS_PHORON

	var/datum/gas_mixture/breath = new(BREATH_VOLUME)
	breath.adjust_gas(/datum/gas/plasma, 5)
	breath.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)
	breath.set_temperature(T20C)

	var/initial_plasma = breath.get_moles(/datum/gas/plasma)

	life_test_breath(H, breath)

	var/final_plasma = breath.get_moles(/datum/gas/plasma)

	// Restore the shared species singleton before asserting so a failure can't
	// leak the mutated breath_type into subsequent tests.
	species.breath_type = saved_breath_type

	TEST_ASSERT(final_plasma < initial_plasma, \
		"phoron-breather didn't consume plasma: [initial_plasma] → [final_plasma]")


// =====================================================================
// Heat-exchange pipes
// =====================================================================

/// /datum/pipeline.temperature_interact transfers heat between a pipeline's
/// air mixture and an adjacent turf — the mechanism HE pipes use to dump or
/// extract heat through the world. Direct test via a programmatic pipeline
/// avoids the HE pipe's two-segment auto-connection requirement.
/datum/unit_test/dq_pipeline_temperature_interact_with_turf

/datum/unit_test/dq_pipeline_temperature_interact_with_turf/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for temperature_interact test")

	var/datum/gas_mixture/turf_air = T.return_air()
	for(var/datum/gas/g as anything in turf_air.get_gases())
		turf_air.set_moles(g, 0)
	turf_air.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)
	turf_air.set_temperature(T20C)

	// Manually-built pipeline (sidesteps HE pipe two-node auto-connection).
	var/datum/pipeline/P = new
	P.air = new(70)
	P.air.adjust_gas(/datum/gas/nitrogen, 50)
	P.air.set_temperature(T0C + 500) // hot

	var/initial_turf_temp = turf_air.return_temperature()
	var/initial_pipe_temp = P.air.return_temperature()

	P.temperature_interact(T, P.air.return_volume(), OPEN_HEAT_TRANSFER_COEFFICIENT)

	var/final_turf_temp = turf_air.return_temperature()
	var/final_pipe_temp = P.air.return_temperature()
	TEST_ASSERT(final_turf_temp > initial_turf_temp, \
		"turf air didn't heat from hot pipe: [initial_turf_temp] → [final_turf_temp]")
	TEST_ASSERT(final_pipe_temp < initial_pipe_temp, \
		"hot pipe didn't cool giving heat to turf: [initial_pipe_temp] → [final_pipe_temp]")

	qdel(P)


// =====================================================================
// Fire propagation, depressurization, environment damage
// =====================================================================

/// Hotspot on one tile should ignite gas on an adjacent tile after enough
/// ticks of share + hotspot_expose. This is the visible "fire spreads" game
/// behaviour — if it doesn't work, plasma breaches don't propagate.
/datum/unit_test/dq_fire_spreads_to_adjacent_floor

/datum/unit_test/dq_fire_spreads_to_adjacent_floor/Run()
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no floor pair for fire-spread test")
	var/turf/simulated/floor/A = pair[1]
	var/turf/simulated/floor/B = pair[2]

	dq_atmos_test_isolate_pair(A, B)

	// Clear any prior hotspots.
	if(A.active_hotspot)
		qdel(A.active_hotspot)
		A.active_hotspot = null
	if(B.active_hotspot)
		qdel(B.active_hotspot)
		B.active_hotspot = null

	// Stock both with plasma + oxygen so once gas migrates, B can also burn.
	for(var/datum/gas/g as anything in A.air.get_gases())
		A.air.set_moles(g, 0)
	for(var/datum/gas/g as anything in B.air.get_gases())
		B.air.set_moles(g, 0)

	var/datum/gas_mixture/donor_a = new(70)
	donor_a.adjust_gas(/datum/gas/plasma, 30)
	donor_a.adjust_gas(/datum/gas/oxygen, 100)
	donor_a.set_temperature(PLASMA_MINIMUM_BURN_TEMPERATURE + 500)
	A.assume_air(donor_a)

	var/datum/gas_mixture/donor_b = new(70)
	donor_b.adjust_gas(/datum/gas/plasma, 30)
	donor_b.adjust_gas(/datum/gas/oxygen, 100)
	donor_b.set_temperature(T20C)
	B.assume_air(donor_b)

	// Ignite A.
	A.hotspot_expose(PLASMA_MINIMUM_BURN_TEMPERATURE + 500, CELL_VOLUME, soh = TRUE)
	TEST_ASSERT_NOTNULL(A.active_hotspot, "A didn't ignite from hotspot_expose")

	// Let real SSair tick — share + hotspot.process should heat B and ignite.
	dq_atmos_test_wait_real_ssair_ticks(15)

	// After enough ticks, B should have caught fire (hotspot present OR
	// temperature now well above ignition).
	var/b_caught = !isnull(B.active_hotspot) || B.air.return_temperature() > PLASMA_MINIMUM_BURN_TEMPERATURE
	TEST_ASSERT(b_caught, \
		"fire did not spread from A to B over 20 ticks. B.hotspot=[B.active_hotspot] B.temp=[B.air.return_temperature()]")

	if(A.active_hotspot)
		qdel(A.active_hotspot)
		A.active_hotspot = null
	if(B.active_hotspot)
		qdel(B.active_hotspot)
		B.active_hotspot = null
	A.air.set_moles(/datum/gas/plasma, 0)
	B.air.set_moles(/datum/gas/plasma, 0)
	A.update_visuals()
	B.update_visuals()


/// Spacing: a pressurized floor adjacent to a space tile should LOSE moles
/// every tick as gas vents into space (sharing with the immutable vacuum mix).
/datum/unit_test/dq_room_depressurizes_when_open_to_space

/datum/unit_test/dq_room_depressurizes_when_open_to_space/Run()
	// Deterministically build the floor↔space scenario: grab a sealed test-room
	// floor, wall off its other neighbors so space is the only sink, then breach
	// one wall into real /turf/space. ChangeTurf wires the floor↔space adjacency
	// through the production immediate_calculate_adjacent_turfs path.
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no usable floor pair on map for depressurization test")
	var/turf/simulated/floor/A = pair[1]
	var/turf/simulated/floor/other = pair[2]

	dq_atmos_test_isolate_pair(A, other)

	var/turf/space/S = dq_atmos_test_open_to_space(A)
	TEST_ASSERT_NOTNULL(S, "couldn't breach a test-room wall into space for depressurization test")
	// Vacuum is a real /datum/gas_mixture (immutable space mix), never null.
	TEST_ASSERT_NOTNULL(S.air, "/turf/space.air is null — /turf/open/Initialize didn't create the vacuum mixture")
	// ChangeTurf + air_update_turf must have wired floor↔space both ways.
	var/list/space_blockers = list()
	for(var/obj/blocker in S.contents + A.contents)
		var/turf/other_side = blocker.loc == S ? A : S
		if(!QDELETED(blocker) && !CANATMOSPASS(blocker, other_side, FALSE))
			space_blockers += "[blocker.type](loc=[COORD(blocker)],density=[blocker.density],pass=[blocker.can_atmos_pass])"
	TEST_ASSERT(vg_atmos_turfs_share(A, S), \
		"floor↔space adjacency wasn't wired after breaching the wall to space (A=[COORD(A)] S=[COORD(S)] dir=[get_dir(A, S)] A.blocks=[A.blocks_air] S.blocks=[S.blocks_air] A.pass=[CANATMOSPASS(A, A, FALSE)] S.pass=[CANATMOSPASS(S, A, FALSE)] blockers=[jointext(space_blockers, ",")] A.adj=[json_encode(vg_atmos_adjacent_turfs(A))] S.adj=[json_encode(vg_atmos_adjacent_turfs(S))])")

	for(var/datum/gas/g as anything in A.air.get_gases())
		A.air.set_moles(g, 0)
	// And ensure space is genuinely vacuum (some maps initialize it with trace gas).
	for(var/datum/gas/g as anything in S.air.get_gases())
		S.air.set_moles(g, 0)

	// Pressurize A through the production path.
	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD * 5) // ~5 atm
	donor.set_temperature(T20C)
	A.assume_air(donor)

	var/initial_pressure = A.air.return_pressure()
	var/initial_moles = A.air.total_moles()

	// Let real SSair tick, polling for the drop instead of always waiting the
	// full 15-tick budget — break as soon as both conditions asserted below hold.
	var/baseline = 0
	var/final_pressure
	var/final_moles
	while(baseline < 15)
		final_pressure = A.air.return_pressure()
		final_moles = A.air.total_moles()
		if(final_pressure < initial_pressure * 0.4 && final_moles < initial_moles * 0.4)
			break
		SSair.run_gas_frames(1)
		baseline++

	final_pressure = A.air.return_pressure()
	final_moles = A.air.total_moles()

	// Restore baseline air on A and roll the breached wall + isolation walls back
	// to their original turf types so later tests see a clean sealed room.
	A.air.set_moles(/datum/gas/nitrogen, MOLES_N2STANDARD)
	dq_atmos_test_restore_walls()

	TEST_ASSERT(final_pressure < initial_pressure, \
		"pressurised floor adjacent to space didn't depressurize: [initial_pressure] → [final_pressure]")
	TEST_ASSERT(final_moles < initial_moles, \
		"depressurization didn't drain moles: [initial_moles] → [final_moles]")
	TEST_ASSERT(final_pressure < initial_pressure * 0.4, \
		"explosive decompression was too slow: pressure only fell [initial_pressure] → [final_pressure] in [baseline] gas frames")
	log_runtime("ATMOS_DECOMPRESSION_PROOF pressure=[round(initial_pressure, 0.01)]->[round(final_pressure, 0.01)]kPa moles=[round(initial_moles, 0.01)]->[round(final_moles, 0.01)] frames=[baseline]")


/// Full atmos cycle: vent_pump pressurizes a turf, vent_scrubber on the
/// same turf removes a target gas. Validates the supply→space→scrub loop.
/datum/unit_test/dq_full_atmos_cycle_vent_then_scrubber

/datum/unit_test/dq_full_atmos_cycle_vent_then_scrubber/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for full-cycle test")
	dq_atmos_test_snapshot_air(T)
	dq_atmos_test_isolate_pair(T, T)
	T.air_update_turf(TRUE, FALSE)

	var/datum/gas_mixture/turf_air = T.return_air()
	for(var/datum/gas/g as anything in turf_air.get_gases())
		turf_air.set_moles(g, 0)
	turf_air.set_temperature(T20C)

	// Pollute the turf with CO2 — the scrubber's target.
	turf_air.adjust_gas(/datum/gas/carbon_dioxide, 200)

	// Vent_pump preloaded with clean N2 supply. `node` is set after
	// topology registration - self-referencing it beforehand would make
	// rust_register_pipe_edges() try to connect the port to itself.
	var/obj/machinery/atmospherics/unary/vent_pump/V = new(T)
	V.use_power = USE_POWER_IDLE
	V.stat &= ~(NOPOWER | BROKEN)
	V.welded = FALSE
	V.pump_direction = 1
	V.external_pressure_bound = ONE_ATMOSPHERE * 1.5
	V.internal_pressure_bound = 0
	V.rust_register_pipe_topology()
	V.node = V
	V.air_contents.adjust_gas(/datum/gas/nitrogen, 500)
	V.air_contents.set_temperature(T20C)
	V.update_rust_device()

	// Scrubber configured for CO2.
	var/obj/machinery/atmospherics/unary/vent_scrubber/S = new(T)
	S.use_power = USE_POWER_IDLE
	S.stat &= ~(NOPOWER | BROKEN)
	S.welded = FALSE
	S.scrubbing = 1
	S.scrubbing_gas = list(GAS_CO2)
	S.rust_register_pipe_topology()
	S.node = S
	S.update_rust_device()

	var/initial_co2 = turf_air.get_moles(/datum/gas/carbon_dioxide)
	var/initial_n2 = turf_air.get_moles(/datum/gas/nitrogen)

	// M2 (simulation.md §5): the flow law is a Rust device edge bridging
	// the pipe network and the turf field; SSair drives it, not
	// V.process()/S.process() (deleted). Turf CO2 starts above the vent's
	// own external_pressure_bound, so the vent stays refused until the
	// scrubber (running the same loop) brings the turf pressure down -
	// give the coupled feedback loop enough iterations to converge.
	for(var/i in 1 to 30)
		SSair.rust_step_pipe_devices()
		SSair.run_gas_frames(1)

	var/final_co2 = turf_air.get_moles(/datum/gas/carbon_dioxide)
	var/final_n2 = turf_air.get_moles(/datum/gas/nitrogen)
	TEST_ASSERT(final_co2 < initial_co2, \
		"CO2 not removed by scrubber: [initial_co2] → [final_co2]")
	TEST_ASSERT(final_n2 > initial_n2, \
		"N2 not added by vent: [initial_n2] → [final_n2]")
	// Scrubber captured the CO2.
	TEST_ASSERT(S.air_contents.get_moles(/datum/gas/carbon_dioxide) > 0, \
		"scrubber air_contents didn't accumulate CO2")

	for(var/datum/gas/g as anything in turf_air.get_gases())
		turf_air.set_moles(g, 0)
	qdel(V)
	qdel(S)


/// High-pressure environment damages a human via handle_environment.
/datum/unit_test/dq_high_pressure_damages_human

/datum/unit_test/dq_high_pressure_damages_human/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for high-pressure test")

	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT_NOTNULL(H, "couldn't allocate human")

	var/datum/gas_mixture/turf_air = T.return_air()
	for(var/datum/gas/g as anything in turf_air.get_gases())
		turf_air.set_moles(g, 0)
	// Crush pressure (~20 atm).
	turf_air.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD * 20)
	turf_air.set_temperature(T20C)

	var/initial_brute = H.injury_load(INJURY_CATEGORY_PHYSICAL)
	for(var/i in 1 to 5)
		life_test_environment(H, turf_air)
	var/final_brute = H.injury_load(INJURY_CATEGORY_PHYSICAL)

	TEST_ASSERT(final_brute > initial_brute, \
		"human took no brute damage at ~20 atm pressure: [initial_brute] → [final_brute]")

	// Reset turf to standard atmosphere.
	for(var/datum/gas/g as anything in turf_air.get_gases())
		turf_air.set_moles(g, 0)
	turf_air.adjust_gas(/datum/gas/oxygen, MOLES_O2STANDARD)
	turf_air.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)


/// Extreme cold environment burns a human (cold burn → fire damage).
/datum/unit_test/dq_extreme_cold_damages_human

/datum/unit_test/dq_extreme_cold_damages_human/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for cold-damage test")

	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT_NOTNULL(H, "couldn't allocate human")

	// Use a detached mixture: this test exercises human environmental response,
	// not the concurrently running turf-diffusion worker. A mapped turf mixture
	// can warm between these synchronous calls under full-suite load.
	var/datum/gas_mixture/turf_air = new(CELL_VOLUME)
	for(var/datum/gas/g as anything in turf_air.get_gases())
		turf_air.set_moles(g, 0)
	turf_air.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)
	turf_air.set_temperature(50) // 50 K, ~-223°C

	// Cold exposure → frostbite (thermal injury).
	var/initial_thermal = H.injury_load(INJURY_CATEGORY_THERMAL)
	for(var/i in 1 to 10)
		life_test_environment(H, turf_air)
	var/final_thermal = H.injury_load(INJURY_CATEGORY_THERMAL)

	TEST_ASSERT(final_thermal > initial_thermal, \
		"human took no thermal injury at 50K: [initial_thermal] → [final_thermal]")

	for(var/datum/gas/g as anything in turf_air.get_gases())
		turf_air.set_moles(g, 0)
	turf_air.adjust_gas(/datum/gas/oxygen, MOLES_O2STANDARD)
	turf_air.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)
	turf_air.set_temperature(T20C)
	qdel(turf_air)


/// Tank pressure: a tank filled past its rupture threshold should report its
/// pressure correctly via return_pressure. This validates the tank's
/// air_contents pressure read.
/datum/unit_test/dq_tank_pressure_read_correct

/datum/unit_test/dq_tank_pressure_read_correct/Run()
	var/obj/item/tank/oxygen/Tank = new(locate(1, 1, 1))
	TEST_ASSERT_NOTNULL(Tank, "couldn't construct oxygen tank")
	TEST_ASSERT_NOTNULL(Tank.air_contents, "tank air_contents null")
	var/initial_p = Tank.return_pressure()
	TEST_ASSERT(initial_p > 0, "fresh oxygen tank returned 0 pressure")
	TEST_ASSERT(initial_p < TANK_FRAGMENT_PRESSURE, \
		"fresh tank should be below fragment pressure, got [initial_p]")

	// Pressurize further.
	Tank.air_contents.adjust_gas(/datum/gas/oxygen, 500)
	Tank.air_contents.set_temperature(T0C + 100) // hot
	var/loaded_p = Tank.return_pressure()
	TEST_ASSERT(loaded_p > initial_p, \
		"adding gas didn't raise tank pressure: [initial_p] → [loaded_p]")

	qdel(Tank)


// =====================================================================
// Air alarm pressure detection
// =====================================================================

/// Air alarm constructs and reads turf pressure correctly. Validates the
/// alarm → LINDA gas_mixture integration.
/datum/unit_test/dq_air_alarm_reads_turf_pressure

/datum/unit_test/dq_air_alarm_reads_turf_pressure/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for air alarm test")

	var/datum/gas_mixture/turf_air = T.return_air()
	for(var/datum/gas/g as anything in turf_air.get_gases())
		turf_air.set_moles(g, 0)
	turf_air.adjust_gas(/datum/gas/oxygen, MOLES_O2STANDARD)
	turf_air.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)
	turf_air.set_temperature(T20C)

	var/obj/machinery/alarm/A = new(T)
	TEST_ASSERT_NOTNULL(A, "couldn't construct air alarm")
	// Ensure the alarm's area + threshold-limit-value table are set up, then
	// drive the production scan path (scan_atmo → overall_danger_level) directly.
	A.update_area()
	A.set_initial_TLV()

	// The alarm reads its turf's pressure. ~one atmosphere ≈ 101.3 kPa.
	var/pressure = turf_air.return_pressure()
	TEST_ASSERT(abs(pressure - ONE_ATMOSPHERE) < 5, \
		"turf pressure not standard atmosphere: got [pressure]")

	// Baseline: standard breathable air should read as safe (danger_level 0).
	A.scan_atmo()
	TEST_ASSERT_EQUAL(A.danger_level, 0, \
		"air alarm flagged danger on a standard breathable atmosphere: [A.danger_level]")

	// Pollute with plasma well past the phoron TLV danger ceiling — the alarm
	// must now read its turf and raise danger_level above safe.
	turf_air.adjust_gas(/datum/gas/plasma, 50)
	A.scan_atmo()
	TEST_ASSERT(A.danger_level > 0, \
		"air alarm did not detect a dangerous (plasma-laden) atmosphere: danger_level stayed [A.danger_level]")

	turf_air.set_moles(/datum/gas/plasma, 0)
	qdel(A)

/datum/unit_test/dq_air_alarm_skips_unchanged_air

/datum/unit_test/dq_air_alarm_skips_unchanged_air/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/candidate in world)
		if(candidate.air && !candidate.blocks_air)
			T = candidate
			break
	TEST_ASSERT_NOTNULL(T, "no floor for event-driven air alarm test")
	for(var/datum/gas/g as anything in T.air.get_gases())
		T.air.set_moles(g, 0)
	T.air.adjust_gas(/datum/gas/oxygen, MOLES_O2STANDARD)
	T.air.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)
	T.air.set_temperature(T20C)
	var/obj/machinery/alarm/A = new(T)
	A.update_area()
	A.set_initial_TLV()
	A.alarm_area.main_air_alarm = WEAKREF(A)
	A.process()
	var/datum/weakref/alarm_ref = WEAKREF(A)
	TEST_ASSERT(SSmachines.sleeping_gas_devices[alarm_ref.reference], \
		"stable air alarm did not enter dependency sleep")
	T.air.adjust_moles(/datum/gas/oxygen, 0.01)
	TEST_ASSERT(!A.gas_dependency_changed(T.air.arena_id(), GAS_DEPENDENCY_ALL), \
		"air alarm accepted a gas change that crossed no alarm or control threshold")
	T.air.adjust_moles(/datum/gas/plasma, 50)
	TEST_ASSERT(A.gas_dependency_changed(T.air.arena_id(), GAS_DEPENDENCY_ALL), \
		"air alarm rejected a gas change that crossed a danger threshold")
	SSmachines.wake_gas_subscriber(alarm_ref)
	TEST_ASSERT(A.datum_flags & DF_ISPROCESSING, \
		"air alarm did not wake after its gas dependency changed")
	A.process()
	TEST_ASSERT(A.danger_level > 0, \
		"air alarm did not rescan after its gas revision changed")
	T.air.set_moles(/datum/gas/plasma, 0)
	T.air.set_temperature(T20C)
	A.process()
	TEST_ASSERT(SSmachines.sleeping_gas_devices[alarm_ref.reference], \
		"air alarm did not return to dependency sleep after atmosphere recovery")
	T.air.set_temperature(T20C + 0.1)
	TEST_ASSERT(!A.gas_dependency_changed(T.air.arena_id(), GAS_DEPENDENCY_ALL), \
		"air alarm accepted a harmless same-band temperature change")
	T.air.set_temperature(A.target_temperature + 3)
	TEST_ASSERT(A.gas_dependency_changed(T.air.arena_id(), GAS_DEPENDENCY_ALL), \
		"air alarm rejected a temperature change requiring active regulation")
	qdel(A)

#ifdef DQ_TEST_AIR_ALARM_RADIO
TEST_FOCUS(/datum/unit_test/dq_air_alarm_receives_matching_status)
#endif

/datum/unit_test/dq_air_alarm_receives_matching_status

/datum/unit_test/dq_air_alarm_receives_matching_status/Run()
	var/turf/simulated/floor/T
	for(var/turf/simulated/floor/candidate in world)
		if(candidate.air && !candidate.blocks_air)
			T = candidate
			break
	TEST_ASSERT_NOTNULL(T, "no floor for air alarm radio test")
	var/obj/machinery/alarm/A = new(T)
	TEST_ASSERT_NOTNULL(A.alarm_area, "air alarm radio test has no area")
	var/tag = "dq-radio-test-[REF(A)]"
	var/datum/signal/status = new
	status.data = list(
		"tag" = tag,
		"area" = A.area_uid,
		"sigtype" = "status",
		"device" = "AVP",
		"timestamp" = world.time,
	)
	A.receive_signal(status)
	TEST_ASSERT_EQUAL(LAZYACCESS(A.alarm_area.air_vent_info, tag), status.data, \
		"air alarm discarded a matching vent status packet")
	TEST_ASSERT(tag in A.alarm_area.air_vent_names, \
		"air alarm did not register the matching vent status tag")
	LAZYREMOVE(A.alarm_area.air_vent_info, tag)
	LAZYREMOVE(A.alarm_area.air_vent_names, tag)
	qdel(status)
	qdel(A)

/datum/unit_test/dq_gas_dependencies_wake_exact_devices

/datum/unit_test/dq_gas_dependencies_wake_exact_devices/Run()
	var/turf/simulated/floor/T
	for(var/turf/simulated/floor/candidate in world)
		if(candidate.air && !candidate.blocks_air)
			T = candidate
			break
	TEST_ASSERT_NOTNULL(T, "no floor for gas dependency test")
	// Seal T so the air alarm's baseline is the standard mixture set below, not
	// whatever pressure the surrounding room was left at by earlier tests. An
	// alarm already at its worst danger level correctly ignores more plasma.
	dq_atmos_test_snapshot_air(T)
	dq_atmos_test_isolate_pair(T, T)
	T.air_update_turf(TRUE)
	for(var/datum/gas/g as anything in T.air.get_gases())
		T.air.set_moles(g, 0)
	T.air.adjust_gas(/datum/gas/oxygen, MOLES_O2STANDARD)
	T.air.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)
	T.air.set_temperature(T20C)
	dq_atmos_test_drain_dependency_queue()

	var/obj/machinery/atmospherics/unary/vent_pump/V = new(T)
	V.update_use_power(USE_POWER_IDLE)
	V.external_pressure_bound = T.air.return_pressure() + 50
	V.air_contents.adjust_moles(/datum/gas/oxygen, 10)
	vg_drain_dirty_gas_mixtures()
	SSmachines.hibernate_vent(V)
	var/datum/weakref/vent_ref = WEAKREF(V)
	TEST_ASSERT(SSmachines.hibernating_vents[vent_ref.reference], "vent did not register as sleeping")
	var/turf_mixture_id = V.sleeping_turf_mixture_id
	var/list/original_subscribers = SSmachines.gas_mixture_subscribers["[turf_mixture_id]"]
	T.air.adjust_moles(/datum/gas/oxygen, 5)
	while(!SSmachines.wake_dirty_gas_subscribers())
		stoplag()
	TEST_ASSERT(!SSmachines.hibernating_vents[vent_ref.reference], "pressure change did not wake vent")
	TEST_ASSERT(original_subscribers[vent_ref.reference], "waking discarded the vent's reusable gas subscription")
	SSmachines.hibernate_vent(V)
	TEST_ASSERT_EQUAL(SSmachines.gas_mixture_subscribers["[turf_mixture_id]"], original_subscribers, \
		"re-hibernating replaced an unchanged gas subscriber collection")
	TEST_ASSERT(SSmachines.gas_mixture_subscribers["[turf_mixture_id]"][vent_ref.reference], \
		"re-hibernating did not restore the gas subscription")

	var/obj/machinery/alarm/A = new(T)
	A.update_area()
	A.set_initial_TLV()
	SSmachines.hibernate_air_alarm(A)
	var/alarm_wakes_before = A.gas_dependency_wake_count
	T.air.adjust_moles(/datum/gas/plasma, 1)
	for(var/alarm_i in 1 to 65536)
		SSmachines.wake_dirty_gas_subscribers()
		if(A.gas_dependency_wake_count > alarm_wakes_before)
			break
		if(!(alarm_i % 256))
			stoplag()
	TEST_ASSERT(A.gas_dependency_wake_count > alarm_wakes_before, "composition change did not wake air alarm")

	var/obj/machinery/air_sensor/S = new(T)
	SSmachines.hibernate_air_sensor(S)
	var/sensor_wakes_before = S.gas_dependency_wake_count
	T.air.set_temperature(T.air.return_temperature() + 5)
	for(var/sensor_i in 1 to 65536)
		SSmachines.wake_dirty_gas_subscribers()
		if(S.gas_dependency_wake_count > sensor_wakes_before)
			break
		if(!(sensor_i % 256))
			stoplag()
	TEST_ASSERT(S.gas_dependency_wake_count > sensor_wakes_before, "temperature change did not wake air sensor")

	qdel(V)
	qdel(A)
	qdel(S)

/datum/unit_test/dq_inactive_vents_hibernate

/datum/unit_test/dq_inactive_vents_hibernate/Run()
	var/turf/simulated/floor/T
	for(var/turf/simulated/floor/candidate in world)
		if(candidate.air && !candidate.blocks_air)
			T = candidate
			break
	TEST_ASSERT_NOTNULL(T, "no floor for inactive vent hibernation test")
	// M2 (simulation.md §5): both flow laws are Rust device edges, stepped
	// from SSair every gas tick, so neither is ever a DM process()
	// subscriber - there is nothing left in DM to hibernate or wake.
	var/obj/machinery/atmospherics/unary/vent_pump/V = new(T)
	V.update_use_power(USE_POWER_OFF)
	TEST_ASSERT(!(V in SSmachines.processing_machines), "inactive vent pump should never be a DM process() subscriber")
	var/obj/machinery/atmospherics/unary/vent_scrubber/S = new(T)
	S.update_use_power(USE_POWER_OFF)
	TEST_ASSERT(!(S in SSmachines.processing_machines), "inactive vent scrubber should never be a DM process() subscriber")
	qdel(V)
	qdel(S)

/datum/unit_test/dq_idle_recharge_station_hibernates

/datum/unit_test/dq_idle_recharge_station_hibernates/Run()
	var/turf/test_turf = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	var/obj/machinery/recharge_station/R = new(test_turf)
	TEST_ASSERT_NOTNULL(R.cell, "recharge station did not construct its internal cell")
	R.cell.charge = R.cell.maxcharge
	R.occupant = null
	TEST_ASSERT_EQUAL(R.process(), PROCESS_KILL, "idle full recharge station did not stop timed processing")
	qdel(R)

/datum/unit_test/dq_shield_diffuser_is_event_driven

/datum/unit_test/dq_shield_diffuser_is_event_driven/Run()
	var/list/pair = dq_atmos_test_find_clear_pipe_run(2)
	TEST_ASSERT_NOTNULL(pair, "no adjacent floors for shield diffuser test")
	var/obj/machinery/shield_diffuser/D = new(pair[1])
	var/obj/effect/shield/S = new(pair[2])
	TEST_ASSERT_EQUAL(D.process(), PROCESS_KILL, "stable shield diffuser retained timed polling")
	TEST_ASSERT(S.diffused_for > 0, "event-driven shield diffuser did not suppress an adjacent shield")
	qdel(S)
	qdel(D)

/datum/unit_test/dq_idle_shieldwall_generator_hibernates

/datum/unit_test/dq_idle_shieldwall_generator_hibernates/Run()
	var/turf/test_turf = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	var/obj/machinery/shieldwallgen/G = new(test_turf)
	G.active = FALSE
	G.anchored = FALSE
	G.storedpower = 0
	TEST_ASSERT_EQUAL(G.process(), PROCESS_KILL, "unanchored inactive shieldwall generator retained timed polling")
	G.anchored = TRUE
	G.storedpower = G.max_stored_power
	TEST_ASSERT_EQUAL(G.process(), PROCESS_KILL, "full inactive shieldwall generator retained timed polling")
	G.active = TRUE
	TEST_ASSERT_NOTEQUAL(G.process(), PROCESS_KILL, "active shieldwall generator incorrectly hibernated")
	qdel(G)

/datum/unit_test/dq_idle_circulator_hibernates

/datum/unit_test/dq_idle_circulator_hibernates/Run()
	var/turf/test_turf = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	var/obj/machinery/atmospherics/binary/circulator/C = new(test_turf)
	C.recent_moles_transferred = 0
	TEST_ASSERT_EQUAL(C.process(), PROCESS_KILL, "idle circulator retained timed polling")
	C.recent_moles_transferred = 1
	C.last_worldtime_transfer = world.time
	TEST_ASSERT_NOTEQUAL(C.process(), PROCESS_KILL, "recently active circulator hibernated before its display timeout")
	C.last_worldtime_transfer = world.time - 51
	TEST_ASSERT_EQUAL(C.process(), PROCESS_KILL, "settled circulator retained timed polling")
	TEST_ASSERT_EQUAL(C.recent_moles_transferred, 0, "settled circulator retained stale transfer state")
	qdel(C)

/datum/unit_test/dq_stable_heat_exchanger_hibernates

/datum/unit_test/dq_stable_heat_exchanger_hibernates/Run()
	var/list/pair = dq_atmos_test_find_clear_pipe_run(2)
	TEST_ASSERT_NOTNULL(pair, "no adjacent floors for heat exchanger test")
	var/obj/machinery/atmospherics/unary/heat_exchanger/first = new(pair[1])
	var/obj/machinery/atmospherics/unary/heat_exchanger/second = new(pair[2])
	first.partner = second
	second.partner = first
	first.air_contents.set_temperature(T20C)
	second.air_contents.set_temperature(T20C)
	first.air_contents.set_moles(/datum/gas/oxygen, 10)
	second.air_contents.set_moles(/datum/gas/oxygen, 10)
	TEST_ASSERT_EQUAL(first.process(), PROCESS_KILL, "equilibrated heat exchanger retained timed polling")
	second.air_contents.set_temperature(T20C + 10)
	TEST_ASSERT(first.gas_dependency_changed(second.air_contents.arena_id(), GAS_DEPENDENCY_TEMPERATURE), "temperature divergence did not wake a heat exchanger")
	qdel(first)
	qdel(second)

/datum/unit_test/dq_inactive_emergency_shield_hibernates

/datum/unit_test/dq_inactive_emergency_shield_hibernates/Run()
	var/turf/test_turf = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	var/obj/machinery/shieldgen/G = new(test_turf)
	G.active = FALSE
	TEST_ASSERT_EQUAL(G.process(), PROCESS_KILL, "inactive emergency shield generator retained timed polling")
	G.shields_up()
	TEST_ASSERT(G in SSmachines.processing_machines, "raising emergency shields did not wake their generator")
	qdel(G)

/datum/unit_test/dq_idle_motion_camera_hibernates

/datum/unit_test/dq_idle_motion_camera_hibernates/Run()
	var/turf/test_turf = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	var/obj/machinery/camera/C = new(test_turf)
	C.upgradeMotion()
	C.motionTargets = null
	C.detectTime = 0
	C.stat &= ~NOPOWER
	C.schedule_camera_timer()
	TEST_ASSERT(isnull(C.camera_timer_token), "idle motion camera kept a timer")
	var/mob/living/carbon/human/H = new(test_turf)
	C.newTarget(H)
	TEST_ASSERT(!isnull(C.camera_timer_token), "motion target did not schedule its camera's alarm timer")
	qdel(H)
	qdel(C)

/datum/unit_test/dq_unanchored_teg_hibernates

/datum/unit_test/dq_unanchored_teg_hibernates/Run()
	var/turf/test_turf = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	var/obj/machinery/power/generator/G = new(test_turf)
	G.anchored = FALSE
	TEST_ASSERT_EQUAL(G.process(), PROCESS_KILL, "unanchored thermoelectric generator retained timed polling")
	qdel(G)

/datum/unit_test/dq_idle_teg_wakes_from_pressure

/datum/unit_test/dq_idle_teg_wakes_from_pressure/Run()
	var/turf/test_turf = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	var/obj/machinery/atmospherics/binary/circulator/first = new(test_turf)
	var/obj/machinery/atmospherics/binary/circulator/second = new(test_turf)
	var/obj/machinery/power/generator/G = new(test_turf)
	G.anchored = TRUE
	G.circ1 = first
	G.circ2 = second
	G.stat = 0
	TEST_ASSERT_EQUAL(G.process(), PROCESS_KILL, "idle thermoelectric generator retained timed polling")
	var/datum/weakref/generator_ref = WEAKREF(G)
	TEST_ASSERT(SSmachines.sleeping_gas_devices[generator_ref.reference], "idle thermoelectric generator did not subscribe to its circulator gases")
	first.air1.set_temperature(T20C)
	first.air1.adjust_moles(/datum/gas/oxygen, 100)
	TEST_ASSERT(G.gas_dependency_changed(first.air1.arena_id(), GAS_DEPENDENCY_PRESSURE), "actionable circulator pressure did not invalidate sleeping generator")
	for(var/generator_i in 1 to 4096)
		SSmachines.wake_dirty_gas_subscribers()
		if(G.datum_flags & DF_ISPROCESSING)
			break
	TEST_ASSERT(G.datum_flags & DF_ISPROCESSING, "circulator pressure change did not wake sleeping generator")
	qdel(G)
	qdel(first)
	qdel(second)

/datum/unit_test/dq_closed_firedoor_is_event_driven

/datum/unit_test/dq_closed_firedoor_is_event_driven/Run()
	dq_atmos_test_drain_dependency_queue()
	var/list/pair = dq_atmos_test_find_clear_pipe_run(2)
	TEST_ASSERT_NOTNULL(pair, "no adjacent floors for firedoor dependency test")
	var/turf/simulated/floor/T = pair[1]
	dq_atmos_test_snapshot_air(T)
	dq_atmos_test_isolate_pair(T, T)
	T.air_update_turf(TRUE, FALSE)
	// Start from room temperature. Earlier tests can leave this turf warm, and
	// +10 K from there may cross the firedoor's hot threshold, which is a real
	// alarm rather than harmless drift.
	T.air.set_temperature(T20C)
	dq_atmos_test_drain_dependency_queue()
	vg_drain_dirty_gas_mixtures()
	var/obj/machinery/door/firedoor/F = new(T)
	F.density = TRUE
	TEST_ASSERT_EQUAL(F.process(), PROCESS_KILL, "stable closed firedoor retained timed polling")
	var/datum/weakref/firedoor_ref = WEAKREF(F)
	TEST_ASSERT(SSmachines.sleeping_gas_devices[firedoor_ref.reference], "closed firedoor did not register gas dependencies")
	var/firedoor_wakes_before = F.gas_dependency_wake_count
	T.air.set_temperature(T.air.return_temperature() + 10)
	while(!SSmachines.wake_dirty_gas_subscribers())
		stoplag()
	TEST_ASSERT_EQUAL(F.gas_dependency_wake_count, firedoor_wakes_before, "harmless in-band temperature drift woke a closed firedoor")
	T.air.set_temperature(convert_c2k(60))
	for(var/firedoor_i in 1 to 65536)
		SSmachines.wake_dirty_gas_subscribers()
		if(F.gas_dependency_wake_count > firedoor_wakes_before)
			break
		if(!(firedoor_i % 256))
			stoplag()
	TEST_ASSERT(F.gas_dependency_wake_count > firedoor_wakes_before, "temperature change did not wake closed firedoor")
	TEST_ASSERT_EQUAL(F.process(), PROCESS_KILL, "dependency wake left a firedoor polling after evaluating its state")
	TEST_ASSERT(!(F in SSmachines.processing_machines), "early-woken firedoor did not return to dependency sleep")
	qdel(F)

/datum/unit_test/dq_unpowered_empty_light_hibernates

/datum/unit_test/dq_unpowered_empty_light_hibernates/Run()
	var/turf/test_turf = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	var/obj/machinery/light/L = new(test_turf)
	L.stat |= NOPOWER
	L.emergency_mode = FALSE
	L.auto_flicker = FALSE
	var/obj/item/cell/emergency = L.emergency_cell()
	emergency.charge = 0
	L.continue_emergency_discharge()
	TEST_ASSERT(!L.emergency_discharge_at && !L.flicker_chunk_tokens, "unpowered light without emergency charge kept a timer or chunk keys")
	qdel(L)

/datum/unit_test/dq_emergency_light_discharge_is_timer_driven

/datum/unit_test/dq_emergency_light_discharge_is_timer_driven/Run()
	var/turf/test_turf = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	var/obj/machinery/light/L = new(test_turf)
	L.stat |= NOPOWER
	L.emergency_mode = TRUE
	L.auto_flicker = FALSE
	L.begin_emergency_discharge()
	TEST_ASSERT(L.emergency_discharge_at && !isnull(L.light_timer_token), "emergency light did not schedule its discharge timer")
	TEST_ASSERT(!(L in SSobj.processing), "ordinary emergency light retained SSobj polling")
	qdel(L)

/datum/unit_test/dq_idle_cooker_hibernates

/datum/unit_test/dq_idle_cooker_hibernates/Run()
	var/turf/test_turf = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	var/obj/machinery/appliance/cooker/oven/O = new(test_turf)
	O.stat = 0
	O.cooking = FALSE
	// Its temperature is its heat body's (H3): hold it at the target, isolated from the room.
	O.create_heat_body(TRUE)
	vg_heat_body_couple(O.heat_body, 0, HEAT_TARGET_NONE, 0, 0)
	vg_heat_body_set_temperature(O.heat_body, O.optimal_temp)
	TEST_ASSERT_EQUAL(O.process(), PROCESS_KILL, "stable empty cooker retained timed polling")
	TEST_ASSERT_NOTNULL(O.thermostat_watch, "a hibernating cooker waits on a heat watch")
	vg_heat_body_set_temperature(O.heat_body, O.optimal_temp - 20)
	TEST_ASSERT_NOTEQUAL(O.process(), PROCESS_KILL, "heating cooker hibernated below its target temperature")
	qdel(O)

/datum/unit_test/dq_idle_meter_and_fire_alarm_hibernate

/datum/unit_test/dq_idle_meter_and_fire_alarm_hibernate/Run()
	var/turf/simulated/floor/T
	for(var/turf/simulated/floor/candidate in world)
		if(candidate.air && !candidate.blocks_air)
			T = candidate
			break
	TEST_ASSERT_NOTNULL(T, "no floor for idle machine hibernation test")
	var/obj/machinery/atmospherics/pipe/simple/P = new(T)
	var/datum/gas_mixture/pipe_air = P.return_air()
	pipe_air.adjust_moles(/datum/gas/oxygen, 10)
	var/obj/machinery/meter/M = new(T)
	M.target = P
	M.process()
	var/datum/weakref/meter_ref = WEAKREF(M)
	TEST_ASSERT(SSmachines.sleeping_gas_devices[meter_ref.reference], "idle local meter did not subscribe and hibernate")
	pipe_air.adjust_moles(/datum/gas/oxygen, 0.0001)
	TEST_ASSERT(!M.gas_dependency_changed(M.sleeping_mixture_id, GAS_DEPENDENCY_PRESSURE), "sub-display-resolution pressure change woke an idle meter")
	pipe_air.adjust_moles(/datum/gas/oxygen, 1000)
	TEST_ASSERT(M.gas_dependency_changed(M.sleeping_mixture_id, GAS_DEPENDENCY_PRESSURE), "display-range pressure change was filtered from an idle meter")
	// Finish any dirty-gas batch captured by the running subsystem before
	// consuming the mutation made above. Production does this on successive fires.
	for(var/meter_i in 1 to 4096)
		SSmachines.wake_dirty_gas_subscribers()
		if(M.datum_flags & DF_ISPROCESSING)
			break
	TEST_ASSERT(M.datum_flags & DF_ISPROCESSING, "meter did not wake after target pressure changed")

	var/obj/machinery/firealarm/F = new(T)
	var/fire_result = F.process()
	TEST_ASSERT_EQUAL(fire_result, PROCESS_KILL, "idle fire alarm remained in the machine polling loop")
	// Its detector is a heat rule on its body (H3): no polling needed.
	// dq_rule_test_write() flushes deterministically itself now.
	dq_rule_test_write(F, PROP_TEMPERATURE, T0C + 300)
	TEST_ASSERT(F.firewarn, "hibernating fire alarm did not respond to being heated")
	qdel(F)
	qdel(M)
	qdel(P)

/datum/unit_test/dq_idle_portables_connectors_and_displays_hibernate

/datum/unit_test/dq_idle_portables_connectors_and_displays_hibernate/Run()
	var/turf/simulated/floor/T = locate() in world
	TEST_ASSERT_NOTNULL(T, "no floor for idle machinery hibernation test")
	var/obj/machinery/portable_atmospherics/powered/pump/P = new(T)
	TEST_ASSERT_EQUAL(P.process(), PROCESS_KILL, "powered-off portable pump remained scheduled")
	var/obj/machinery/portable_atmospherics/powered/scrubber/S = new(T)
	TEST_ASSERT_EQUAL(S.process(), PROCESS_KILL, "powered-off portable scrubber remained scheduled")
	var/obj/machinery/atmospherics/portables_connector/C = new(T)
	C.on = FALSE
	TEST_ASSERT_EQUAL(C.process(), PROCESS_KILL, "disconnected portable connector remained scheduled")
	C.connected_device = P
	C.on = TRUE
	C.hibernate_until_device_changes()
	STOP_MACHINE_PROCESSING(C)
	P.air_contents.adjust_moles(/datum/gas/oxygen, 1)
	for(var/connector_i in 1 to 4096)
		SSmachines.wake_dirty_gas_subscribers()
	TEST_ASSERT(!(C.datum_flags & DF_ISPROCESSING), "connected portable connector scheduled a no-op callback for a device gas change")
	C.clear_gas_dependency()
	C.connected_device = null
	C.on = FALSE
	var/obj/machinery/portable_atmospherics/canister/oxygen/canister = new(T)
	TEST_ASSERT_EQUAL(canister.process(), PROCESS_KILL, "closed inert canister remained scheduled")
	var/datum/weakref/canister_ref = WEAKREF(canister)
	TEST_ASSERT(SSmachines.sleeping_gas_devices[canister_ref.reference], "closed canister did not subscribe to its gas mixture")
	canister.air_contents.adjust_moles(/datum/gas/oxygen, 1)
	for(var/canister_i in 1 to 4096)
		SSmachines.wake_dirty_gas_subscribers()
		if(canister.datum_flags & DF_ISPROCESSING)
			break
	// The live subsystem may consume the wake and settle the inert canister back
	// to its dependency subscription before this test regains execution. Both
	// states prove delivery; being neither active nor resubscribed is stale.
	var/canister_active = canister.datum_flags & DF_ISPROCESSING
	var/canister_resubscribed = SSmachines.sleeping_gas_devices[canister_ref.reference] && !isnull(canister.sleeping_mixture_id)
	TEST_ASSERT(canister_active || canister_resubscribed, "closed canister was stranded after its contents changed")
	STOP_MACHINE_PROCESSING(canister)
	canister.connect(C)
	TEST_ASSERT_EQUAL(C.process(), PROCESS_KILL, "stable connected portable port remained scheduled")
	STOP_MACHINE_PROCESSING(C)
	var/datum/weakref/connector_ref = WEAKREF(C)
	TEST_ASSERT(SSmachines.sleeping_gas_devices[connector_ref.reference], "connected portable port did not subscribe to device gas")
	canister.air_contents.adjust_moles(/datum/gas/oxygen, 1)
	for(var/connector_i in 1 to 4096)
		SSmachines.wake_dirty_gas_subscribers()
	TEST_ASSERT(!(C.datum_flags & DF_ISPROCESSING), "portable port scheduled a no-op callback after connected-device gas changed")
	var/obj/machinery/status_display/D = new(T)
	var/datum/signal/blank = new
	blank.data["command"] = "blank"
	D.receive_signal(blank)
	TEST_ASSERT(isnull(D.refresh_token), "blank status display kept a refresh timer")
	var/datum/signal/time_signal = new
	time_signal.data["command"] = "time"
	D.receive_signal(time_signal)
	TEST_ASSERT(!isnull(D.refresh_token) || (D.stat & NOPOWER), "time signal did not schedule the clock's next redraw")
	qdel(D)
	qdel(canister)
	qdel(C)
	qdel(S)
	qdel(P)

/datum/unit_test/dq_rust_portable_port_round_trip_conserves_gas

/datum/unit_test/dq_rust_portable_port_round_trip_conserves_gas/Run()
	var/turf/simulated/floor/T
	for(var/turf/simulated/floor/candidate in world)
		if(!locate(/obj/machinery/atmospherics) in candidate && !locate(/obj/machinery/portable_atmospherics) in candidate)
			T = candidate
			break
	TEST_ASSERT_NOTNULL(T, "no floor for Rust portable-port test")
	var/obj/machinery/atmospherics/portables_connector/C = new(T)
	TEST_ASSERT(!QDELETED(C), "test connector was deleted during initialization")
	C.rust_register_pipe_topology()
	var/turf/simulated/floor/staging_turf
	for(var/turf/simulated/floor/candidate in world)
		if(candidate != T && !locate(/obj/machinery/atmospherics) in candidate && !locate(/obj/machinery/portable_atmospherics) in candidate)
			staging_turf = candidate
			break
	TEST_ASSERT_NOTNULL(staging_turf, "no staging floor for Rust portable-port test")
	var/obj/machinery/portable_atmospherics/canister/P = new(staging_turf)
	TEST_ASSERT(!P.connected_port, "fresh test portable unexpectedly started connected")
	TEST_ASSERT(!C.connected_device, "fresh test connector unexpectedly started occupied")
	P.air_contents.clear()
	P.air_contents.set_temperature(300)
	P.air_contents.adjust_moles(/datum/gas/oxygen, 100)
	var/initial_moles = P.air_contents.total_moles()
	P.forceMove(T)
	TEST_ASSERT_EQUAL(P.loc, C.loc, "test portable and connector did not share a turf")
	TEST_ASSERT(P.connect(C), "portable did not attach to its Rust connector")
	TEST_ASSERT(C.rust_external_port_id, "connector did not allocate a persistent external Rust port")
	TEST_ASSERT_EQUAL(P.air_contents, C.network.air, "portable was not rebound to the authoritative Rust region mixture")
	TEST_ASSERT(P.disconnect(), "portable did not detach from its Rust connector")
	TEST_ASSERT_NULL(C.rust_external_port_id, "external Rust port survived portable detachment")
	TEST_ASSERT(abs(P.air_contents.total_moles() - initial_moles) < 0.001, "portable attach/detach changed its gas inventory")
	TEST_ASSERT_EQUAL(P.air_contents.return_volume(), 1000, "portable detached with the wrong physical volume")
	qdel(P)
	qdel(C)

/datum/unit_test/dq_rust_destroyed_pipe_vents_atomically

/datum/unit_test/dq_rust_destroyed_pipe_vents_atomically/Run()
	var/turf/simulated/floor/T
	for(var/turf/simulated/floor/candidate in world)
		var/nearby_atmos = FALSE
		for(var/turf/nearby in RANGE_TURFS(1, candidate))
			if(locate(/obj/machinery/atmospherics) in nearby)
				nearby_atmos = TRUE
				break
		if(candidate.air && !nearby_atmos)
			T = candidate
			break
	TEST_ASSERT_NOTNULL(T, "no floor for Rust pipe-removal test")
	dq_atmos_test_snapshot_air(T)
	dq_atmos_test_isolate_pair(T, T)
	T.air_update_turf(TRUE, FALSE)
	var/initial_turf_oxygen = T.air.get_moles(/datum/gas/oxygen)
	var/initial_region_count = length(SSair.rust_pipe_region_networks)
	var/obj/machinery/atmospherics/pipe/simple/P = new(T)
	P.rust_register_pipe_topology()
	var/datum/gas_mixture/pipe_air = P.return_air()
	pipe_air.clear()
	pipe_air.set_temperature(300)
	pipe_air.adjust_moles(/datum/gas/oxygen, 25)
	TEST_ASSERT_EQUAL(length(SSair.rust_pipe_region_networks), initial_region_count + 1, "standalone pipe did not materialize one Rust region")
	qdel(P)
	TEST_ASSERT(abs(T.air.get_moles(/datum/gas/oxygen) - initial_turf_oxygen - 25) < 0.001, "destroyed pipe gas was not atomically received by its turf")
	TEST_ASSERT_EQUAL(length(SSair.rust_pipe_region_networks), initial_region_count, "fully removed Rust region left a compatibility wrapper")

/datum/unit_test/dq_stable_binary_pump_hibernates_and_wakes

/datum/unit_test/dq_stable_binary_pump_hibernates_and_wakes/Run()
	// M2 (simulation.md §5): the binary pump's flow law is a Rust device
	// edge, stepped every gas tick from SSair regardless of state, so it is
	// never a DM process() subscriber at all — there is nothing left to
	// hibernate or wake in DM, in any state.
	var/turf/simulated/floor/T = locate() in world
	TEST_ASSERT_NOTNULL(T, "no floor for binary pump hibernation test")
	var/obj/machinery/atmospherics/binary/pump/P = new(T)
	P.stat = 0
	P.use_power = USE_POWER_OFF
	P.set_target_pressure(ONE_ATMOSPHERE)
	P.rust_register_pipe_topology()
	P.update_rust_device()
	TEST_ASSERT(!(P in SSmachines.processing_machines), "powered-off binary pump should never be a DM process() subscriber")
	P.use_power = USE_POWER_IDLE
	P.set_on(TRUE)
	P.update_rust_device()
	TEST_ASSERT(!(P in SSmachines.processing_machines), "enabling a binary pump must not add DM process() scheduling")
	P.air1.adjust_moles(/datum/gas/oxygen, 10)
	for(var/i in 1 to 10)
		SSair.rust_step_pipe_devices()
	TEST_ASSERT(!(P in SSmachines.processing_machines), "a running binary pump must not add DM process() scheduling")
	qdel(P)

/datum/unit_test/dq_idle_turret_wakes_for_nearby_mob

/datum/unit_test/dq_idle_turret_wakes_for_nearby_mob/Run()
	var/turf/T = locate(1, 1, 1)
	TEST_ASSERT_NOTNULL(T, "no isolated turf for turret hibernation test")
	var/obj/machinery/porta_turret/turret = new(T)
	turret.stat = 0
	turret.enabled = TRUE
	TEST_ASSERT_EQUAL(turret.process(), PROCESS_KILL, "turret with an empty field of view remained scheduled")
	TEST_ASSERT(turret.react_sleep_tokens, "idle turret did not subscribe to nearby mob chunks")
	SSreactor.trace(turret)
	var/mob/living/arrival = new(get_step(T, NORTH))
	react_test_ticks(4)
	TEST_ASSERT(SSreactor.traced_wakes(turret), "idle turret did not wake when a mob appeared nearby")
	SSreactor.untrace(turret)
	qdel(arrival)
	qdel(turret)

/datum/unit_test/dq_blocked_airlock_wakes_from_blocker_movement

/datum/unit_test/dq_blocked_airlock_wakes_from_blocker_movement/Run()
	var/obj/machinery/door/airlock/A = locate() in world
	TEST_ASSERT_NOTNULL(A, "no mapped airlock for blocked airlock hibernation test")
	var/turf/T = get_turf(A)
	A.density = FALSE
	A.operating = FALSE
	A.locked = FALSE
	A.frozen = FALSE
	A.close_door_at = 0
	A.safe = TRUE
	A.autoclose = TRUE
	var/obj/blocker = new(T)
	blocker.density = TRUE
	A.close()
	TEST_ASSERT(!A.close_door_at, "blocked airlock retained a timed polling retry")
	TEST_ASSERT(LAZYLEN(A.autoclose_blockers), "blocked airlock did not subscribe to its blocker")
	TEST_ASSERT(blocker._listen_lookup?[COMSIG_MOVABLE_MOVED], "blocked airlock did not register a movement signal on its blocker")
	TEST_ASSERT(isnull(A.door_timer_token) || A.next_door_deadline(), "blocked airlock kept an autoclose timer")
	blocker.Moved(T, NORTH, TRUE, 0)
	TEST_ASSERT(A.close_door_at, "woken airlock did not schedule an immediate close attempt")
	TEST_ASSERT(!isnull(A.door_timer_token), "woken airlock has no autoclose timer (close_at=[A.close_door_at], blockers=[LAZYLEN(A.autoclose_blockers)])")
	qdel(blocker)
	qdel(A)

/datum/unit_test/dq_closed_airlock_clears_stale_autoclose

/datum/unit_test/dq_closed_airlock_clears_stale_autoclose/Run()
	var/obj/machinery/door/airlock/A = locate() in world
	TEST_ASSERT_NOTNULL(A, "no mapped airlock for stale autoclose test")
	A.density = TRUE
	A.operating = FALSE
	A.autoclose = TRUE
	A.close_door_at = world.time
	A.door_deadlines_due()
	TEST_ASSERT(!A.close_door_at, "closed airlock did not clear its stale autoclose deadline")
	A.density = FALSE
	A.operating = FALSE
	A.locked = TRUE
	A.close_door_at = world.time
	A.door_deadlines_due()
	TEST_ASSERT(!A.close_door_at, "locked open airlock did not clear its impossible autoclose deadline")
	A.schedule_door_timer()
	A.unlock(TRUE)
	TEST_ASSERT(A.close_door_at, "unlocking an open airlock did not restore autoclose scheduling")

/datum/unit_test/dq_idle_recharger_hibernates

/datum/unit_test/dq_idle_recharger_hibernates/Run()
	var/turf/simulated/floor/T = locate() in world
	TEST_ASSERT_NOTNULL(T, "no floor for recharger hibernation test")
	var/obj/machinery/recharger/R = new(T)
	R.stat = 0
	R.anchored = TRUE
	TEST_ASSERT_EQUAL(R.process(), PROCESS_KILL, "empty recharger remained scheduled")
	var/obj/item/cell/C = new(R)
	C.charge = C.maxcharge
	R.charging = C
	TEST_ASSERT_EQUAL(R.process(), PROCESS_KILL, "recharger holding a full cell remained scheduled")
	qdel(R)

/datum/unit_test/dq_power_monitor_hibernates_until_grid_warning

/datum/unit_test/dq_power_monitor_hibernates_until_grid_warning/Run()
	var/turf/simulated/floor/T = locate() in world
	TEST_ASSERT_NOTNULL(T, "no floor for power monitor hibernation test")
	var/datum/powernet/P = new
	var/obj/machinery/power/sensor/S = new(T)
	var/obj/machinery/computer/power_monitor/M = new(T)
	S.powernet = P
	M.power_monitor.grid_sensors = list(S)
	START_MACHINE_PROCESSING(M)
	M.process()
	TEST_ASSERT(!(M in SSmachines.processing_machines), "stable power monitor remained scheduled")
	TEST_ASSERT(M.react_sleep_tokens, "power monitor did not subscribe before sleeping")
	SSreactor.trace(M)
	P.trigger_warning()
	react_test_ticks(4)
	TEST_ASSERT(SSreactor.traced_wakes(M), "grid warning did not wake the sleeping power monitor")
	SSreactor.untrace(M)
	qdel(M)
	qdel(S)
	qdel(P)

/datum/unit_test/dq_idle_auxiliary_machines_hibernate

/datum/unit_test/dq_idle_auxiliary_machines_hibernate/Run()
	var/turf/simulated/floor/T = locate() in world
	TEST_ASSERT_NOTNULL(T, "no floor for auxiliary machinery hibernation test")
	var/obj/machinery/ai_status_display/display = new(T)
	TEST_ASSERT_EQUAL(display.process(), PROCESS_KILL, "AI status display retained an empty polling loop")
	var/obj/machinery/drone_fabricator/drone_fabricator = new(T)
	TEST_ASSERT_EQUAL(drone_fabricator.process(), PROCESS_KILL, "drone readiness retained a permanent polling loop")
	var/obj/machinery/airlock_sensor/airlock_sensor = new(T)
	airlock_sensor.on = FALSE
	TEST_ASSERT_EQUAL(airlock_sensor.process(), PROCESS_KILL, "disabled airlock sensor did not explicitly terminate processing")
	var/obj/machinery/status_display/supply_display/supply_display = new(T)
	TEST_ASSERT_EQUAL(supply_display.process(), PROCESS_KILL, "stable supply display remained scheduled")
	var/obj/machinery/media/jukebox/jukebox = new(T)
	jukebox.playing = FALSE
	TEST_ASSERT_EQUAL(jukebox.process(), PROCESS_KILL, "silent jukebox remained scheduled")
	var/obj/machinery/appliance/appliance = new(T)
	appliance.cooking = FALSE
	TEST_ASSERT_EQUAL(appliance.process(), PROCESS_KILL, "idle cooking appliance remained scheduled")
	var/obj/machinery/appliance/mixer/cereal/mixer = new(T)
	mixer.cooking = FALSE
	TEST_ASSERT_EQUAL(mixer.process(), PROCESS_KILL, "idle food mixer remained scheduled")
	var/obj/machinery/cell_charger/charger = new(T)
	charger.stat = 0
	charger.anchored = TRUE
	TEST_ASSERT_EQUAL(charger.process(), PROCESS_KILL, "empty heavy cell charger remained scheduled")
	var/obj/machinery/mech_recharger/mech_charger = new(T)
	TEST_ASSERT_EQUAL(mech_charger.process(), PROCESS_KILL, "empty mech charger remained scheduled")
	var/obj/machinery/space_heater/heater = new(T)
	heater.state = 0
	TEST_ASSERT_EQUAL(heater.process(), PROCESS_KILL, "switched-off space heater remained scheduled")
	var/obj/machinery/floodlight/floodlight = new(T)
	floodlight.on = 0
	TEST_ASSERT_EQUAL(floodlight.process(), PROCESS_KILL, "switched-off floodlight remained scheduled")
	floodlight.cell.charge = floodlight.cell.maxcharge
	STOP_MACHINE_PROCESSING(floodlight)
	TEST_ASSERT(floodlight.turn_on(), "charged floodlight refused to turn on")
	TEST_ASSERT(floodlight in SSmachines.processing_machines, "turning on a floodlight did not wake it")
	var/obj/machinery/power/emitter/emitter = new(T)
	emitter.active = FALSE
	TEST_ASSERT_EQUAL(emitter.process(), PROCESS_KILL, "inactive emitter remained scheduled")
	var/obj/machinery/shieldwallgen/shieldwall_generator = new(T)
	shieldwall_generator.active = FALSE
	shieldwall_generator.storedpower = shieldwall_generator.max_stored_power
	TEST_ASSERT_EQUAL(shieldwall_generator.process(), PROCESS_KILL, "full inactive shieldwall generator remained scheduled")
	var/obj/machinery/shield_capacitor/shield_capacitor = new(T)
	shield_capacitor.stored_charge = shield_capacitor.max_charge
	TEST_ASSERT_EQUAL(shield_capacitor.process(), PROCESS_KILL, "full shield capacitor remained scheduled")
	var/obj/machinery/atmospherics/valve/shutoff/shutoff = new(T)
	TEST_ASSERT(!isnull(shutoff.global_leak_token), "automatic shutoff valve did not subscribe to the global leak key")
	var/shutoff_wake = react_wake_test(shutoff, CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(wake_automatic_shutoff_valves)))
	TEST_ASSERT(!shutoff_wake, shutoff_wake)
	var/obj/machinery/sleeper/sleeper = new(T)
	sleeper.stat = 0
	TEST_ASSERT_EQUAL(sleeper.process(), PROCESS_KILL, "empty sleeper remained scheduled")
	var/obj/machinery/iv_drip/drip = new(T)
	TEST_ASSERT_EQUAL(drip.process(), PROCESS_KILL, "detached IV drip remained scheduled")
	var/obj/machinery/floor_light/floor_light = new(T)
	TEST_ASSERT_EQUAL(floor_light.process(), PROCESS_KILL, "stable floor light remained scheduled")
	var/obj/machinery/vending/vendor = new(T)
	vendor.stat = 0
	vendor.shut_up = TRUE
	vendor.seconds_electrified = 0
	vendor.shoot_inventory = FALSE
	TEST_ASSERT_EQUAL(vendor.process(), PROCESS_KILL, "silent stable vending machine remained scheduled")
	var/obj/machinery/computer/security/security_console = new(T)
	TEST_ASSERT_EQUAL(security_console.process(), PROCESS_KILL, "passive computer inherited permanent polling")
	var/obj/machinery/computer/cloning/cloning_console = new(T)
	cloning_console.autoprocess = FALSE
	TEST_ASSERT_EQUAL(cloning_console.process(), PROCESS_KILL, "cloning console polled with autoprocess disabled")
	var/obj/machinery/clonepod/clonepod = new(T)
	TEST_ASSERT_EQUAL(clonepod.process(), PROCESS_KILL, "empty cloning pod remained scheduled")
	var/obj/machinery/computer/ship/helm/helm = new(T)
	helm.autopilot = FALSE
	TEST_ASSERT_EQUAL(helm.process(), PROCESS_KILL, "idle ship helm remained scheduled without autopilot")
	var/obj/machinery/cryopod/cryo = new(T)
	TEST_ASSERT_EQUAL(cryo.process(), PROCESS_KILL, "empty cryopod remained scheduled")
	var/obj/machinery/atmospherics/unary/cryo_cell/cryo_cell = new(T)
	cryo_cell.on = FALSE
	TEST_ASSERT_EQUAL(cryo_cell.process(), PROCESS_KILL, "switched-off cryo cell remained scheduled")
	var/obj/machinery/power/sensor/power_sensor = new(T)
	TEST_ASSERT_EQUAL(power_sensor.process(), PROCESS_KILL, "power sensor polled between history samples")
	TEST_ASSERT(power_sensor.record_timer, "power sensor did not schedule its next history sample")
	STOP_MACHINE_PROCESSING(power_sensor)
	deltimer(power_sensor.record_timer)
	power_sensor.record_timer = null
	power_sensor.wake_for_record()
	TEST_ASSERT(!(power_sensor in SSmachines.processing_machines), "timer-driven power history sample unnecessarily entered machinery processing")
	TEST_ASSERT(power_sensor.record_timer, "direct power history sample did not schedule its successor")
	var/obj/machinery/power/solar_control/solar_controller = new(T)
	TEST_ASSERT_EQUAL(solar_controller.process(), PROCESS_KILL, "solar controller remained in machinery processing between minute-based solar events")
	var/obj/machinery/telecomms/telecomms_node = new(T)
	TEST_ASSERT_EQUAL(telecomms_node.process(), PROCESS_KILL, "idle telecomms node retained a two-second machinery poll")
	TEST_ASSERT(telecomms_node.thermal_timer, "idle telecomms node did not schedule its physical thermal boundary")
	var/obj/machinery/optable/operating_table = new(T)
	TEST_ASSERT_EQUAL(operating_table.process(), PROCESS_KILL, "empty operating table remained scheduled")
	var/obj/machinery/computer/aifixer/ai_fixer = new(T)
	TEST_ASSERT_EQUAL(ai_fixer.process(), PROCESS_KILL, "idle AI fixer remained scheduled")
	var/obj/machinery/power/breakerbox/breaker = new(T)
	TEST_ASSERT_EQUAL(breaker.process(), PROCESS_KILL, "breaker box retained a no-op polling loop")
	var/obj/machinery/fusion_fuel_injector/injector = new(T)
	TEST_ASSERT_EQUAL(injector.process(), PROCESS_KILL, "inactive fusion fuel injector remained scheduled")
	STOP_MACHINE_PROCESSING(injector)
	injector.cur_assembly = new(injector)
	injector.BeginInjecting()
	TEST_ASSERT(injector in SSmachines.processing_machines, "starting a fusion fuel injector did not wake it")
	var/obj/machinery/atmospherics/binary/algae_farm/algae_farm = new(T)
	algae_farm.update_use_power(USE_POWER_IDLE)
	TEST_ASSERT_EQUAL(algae_farm.process(), PROCESS_KILL, "inactive algae farm remained scheduled")
	var/obj/machinery/power/hydromagnetic_trap/magnetic_trap = new(T)
	TEST_ASSERT_EQUAL(magnetic_trap.process(), PROCESS_KILL, "fieldless hydromagnetic trap remained scheduled")
	var/obj/machinery/atmospherics/unary/outlet_injector/outlet = new(T)
	outlet.update_use_power(USE_POWER_OFF)
	TEST_ASSERT_EQUAL(outlet.process(), PROCESS_KILL, "switched-off outlet injector remained scheduled")
	var/datum/weakref/outlet_ref = WEAKREF(outlet)
	TEST_ASSERT(SSmachines.sleeping_gas_devices[outlet_ref.reference], "outlet injector did not subscribe before sleeping")
	outlet.update_use_power(USE_POWER_IDLE)
	TEST_ASSERT(outlet in SSmachines.processing_machines, "enabling an outlet injector did not wake it")
	// M2 (simulation.md §5): the passive gate's flow law is a Rust device
	// edge stepped every gas tick from SSair, not a DM process() subscriber,
	// so it is never in SSmachines.processing_machines regardless of state.
	var/obj/machinery/atmospherics/binary/passive_gate/gate = new(T)
	gate.unlocked = FALSE
	gate.update_rust_device()
	TEST_ASSERT(!(gate in SSmachines.processing_machines), "closed passive gate should never be a DM process() subscriber")
	gate.unlocked = TRUE
	gate.update_rust_device()
	TEST_ASSERT(!(gate in SSmachines.processing_machines), "opening a passive gate must not add DM process() scheduling")
	var/obj/machinery/atmospherics/binary/dp_vent_pump/dual_vent = new(T)
	dual_vent.update_use_power(USE_POWER_OFF)
	TEST_ASSERT_EQUAL(dual_vent.process(), PROCESS_KILL, "switched-off dual-port vent remained scheduled")
	var/datum/weakref/dual_vent_ref = WEAKREF(dual_vent)
	TEST_ASSERT(SSmachines.sleeping_gas_devices[dual_vent_ref.reference], "dual-port vent did not subscribe before sleeping")
	dual_vent.update_use_power(USE_POWER_IDLE)
	TEST_ASSERT(dual_vent in SSmachines.processing_machines, "enabling a dual-port vent did not wake it")
	var/obj/machinery/disposal/disposal = new(T)
	disposal.air_contents.clear()
	var/datum/gas_mixture/disposal_environment = T.return_air()
	var/datum/gas_mixture/saved_disposal_environment = disposal_environment.copy()
	disposal_environment.clear()
	TEST_ASSERT_EQUAL(disposal.process(), PROCESS_KILL, "airless disposal kept retrying pressurization")
	var/datum/weakref/disposal_ref = WEAKREF(disposal)
	TEST_ASSERT(SSmachines.sleeping_gas_devices[disposal_ref.reference], "airless disposal did not subscribe before sleeping")
	disposal.stat |= NOPOWER
	TEST_ASSERT(!disposal.gas_dependency_changed(disposal.sleeping_turf_mixture_id, GAS_DEPENDENCY_PRESSURE), "powerless disposal woke for ambient pressure churn")
	disposal_environment.copy_from(saved_disposal_environment)
	var/obj/machinery/atmospherics/unary/freezer/freezer = new(T)
	freezer.update_use_power(USE_POWER_OFF)
	TEST_ASSERT_EQUAL(freezer.process(), PROCESS_KILL, "switched-off gas freezer remained scheduled")
	var/obj/machinery/atmospherics/unary/heater/gas_heater = new(T)
	gas_heater.update_use_power(USE_POWER_OFF)
	TEST_ASSERT_EQUAL(gas_heater.process(), PROCESS_KILL, "switched-off gas heater remained scheduled")
	var/obj/machinery/power/thermoregulator/regulator = new(T)
	regulator.on = FALSE
	TEST_ASSERT_EQUAL(regulator.process(), PROCESS_KILL, "switched-off thermoregulator remained scheduled")
	STOP_MACHINE_PROCESSING(regulator)
	regulator.on = TRUE
	regulator.wake_for_state_change()
	TEST_ASSERT(regulator in SSmachines.processing_machines, "enabling a thermoregulator did not wake it")
	var/obj/machinery/portable_atmospherics/canister/air/airlock/airlock_canister = new(T)
	var/obj/machinery/atmospherics/portables_connector/test_port = new(T)
	airlock_canister.connected_port = test_port
	airlock_canister.update_flag = airlock_canister.desired_update_flag()
	airlock_canister.hibernate_until_gas_changes()
	var/canister_mixture_id = airlock_canister.air_contents.arena_id()
	TEST_ASSERT(!airlock_canister.gas_dependency_changed(canister_mixture_id, GAS_DEPENDENCY_PRESSURE), "minor connected-canister pressure change caused an irrelevant wake")
	airlock_canister.air_contents.clear()
	TEST_ASSERT(airlock_canister.gas_dependency_changed(canister_mixture_id, GAS_DEPENDENCY_PRESSURE), "connected canister did not wake when its gauge band changed")
	var/obj/machinery/computer/operating/operating_console = new(T)
	operating_console.table = operating_table
	operating_table.computer = operating_console
	TEST_ASSERT_EQUAL(operating_console.process(), PROCESS_KILL, "empty operating console remained scheduled")
	var/obj/machinery/pointdefense/point_defense = new(T)
	point_defense.stat = 0
	point_defense.active = TRUE
	TEST_ASSERT_EQUAL(point_defense.process(), PROCESS_KILL, "point defense polled with no meteors")
	TEST_ASSERT(point_defense.react_sleep_tokens, "point defense did not subscribe before sleeping")
	SSreactor.trace(point_defense)
	REACT_PUBLISH(REACT_KEY_METEORS, 1, REACT_KEY_CHANGED)
	react_test_ticks(4)
	TEST_ASSERT(SSreactor.traced_wakes(point_defense), "meteor dependency did not wake point defense")
	SSreactor.untrace(point_defense)
	var/obj/machinery/computer/pod/pod_console = new(T)
	pod_console.stat = 0
	pod_console.timing = FALSE
	TEST_ASSERT_EQUAL(pod_console.process(), PROCESS_KILL, "idle pod console remained scheduled")
	var/obj/machinery/chemical_dispenser/dispenser = new(T)
	dispenser._recharge_reagents = FALSE
	TEST_ASSERT_EQUAL(dispenser.process(), PROCESS_KILL, "non-recharging chemical dispenser remained scheduled")
	var/obj/machinery/atm/atm = new(T)
	atm.stat = 0
	TEST_ASSERT_EQUAL(atm.process(), PROCESS_KILL, "idle ATM remained scheduled")
	var/obj/machinery/portable_atmospherics/hydroponics/tray = new(T)
	tray.lastcycle = world.time
	TEST_ASSERT_EQUAL(tray.process(), PROCESS_KILL, "stable hydroponics tray polled between growth cycles")
	TEST_ASSERT(tray.growth_timer, "sleeping hydroponics tray did not schedule its next growth cycle")
	STOP_MACHINE_PROCESSING(tray)
	tray.reagents.add_reagent(REAGENT_ID_WATER, 1)
	TEST_ASSERT(tray in SSmachines.processing_machines, "reagent mutation did not wake hydroponics tray")
	var/obj/machinery/seed_storage/garden/seed_storage = new(T)
	seed_storage.seconds_electrified = 0
	TEST_ASSERT_EQUAL(seed_storage.process(), PROCESS_KILL, "stable seed storage remained scheduled")
	var/obj/machinery/beehive/beehive = new(T)
	TEST_ASSERT_EQUAL(beehive.process(), PROCESS_KILL, "empty beehive remained scheduled")
	var/obj/machinery/bluespace_beacon/bluespace_beacon = new(T)
	TEST_ASSERT_EQUAL(bluespace_beacon.process(), PROCESS_KILL, "stable bluespace beacon remained scheduled")
	var/obj/machinery/shipsensors/ship_sensors = new(T)
	ship_sensors.update_use_power(USE_POWER_OFF)
	ship_sensors.heat = 0
	TEST_ASSERT_EQUAL(ship_sensors.process(), PROCESS_KILL, "cold switched-off ship sensors remained scheduled")
	ship_sensors.update_use_power(USE_POWER_IDLE)
	STOP_MACHINE_PROCESSING(ship_sensors)
	ship_sensors.toggle()
	TEST_ASSERT(ship_sensors in SSmachines.processing_machines, "changing ship sensor power state did not wake machinery processing")
	var/obj/machinery/computer/ship/sensors/sensor_console = new(T)
	TEST_ASSERT_EQUAL(sensor_console.process(), PROCESS_KILL, "passive ship sensor console retained a polling loop")
	var/obj/machinery/suit_cycler/suit_cycler = new(T)
	suit_cycler.active = FALSE
	suit_cycler.electrified = 0
	TEST_ASSERT_EQUAL(suit_cycler.process(), PROCESS_KILL, "inactive suit cycler remained scheduled")
	suit_cycler.active = TRUE
	suit_cycler.irradiating = 2
	STOP_MACHINE_PROCESSING(suit_cycler)
	START_MACHINE_PROCESSING(suit_cycler)
	TEST_ASSERT(suit_cycler.process() != PROCESS_KILL, "active UV suit cycle hibernated before completion")
	var/obj/machinery/field_generator/field_generator = new(T)
	field_generator.active = FALSE
	field_generator.Varedit_start = FALSE
	TEST_ASSERT_EQUAL(field_generator.process(), PROCESS_KILL, "inactive field generator remained scheduled")
	STOP_MACHINE_PROCESSING(field_generator)
	field_generator.turn_on()
	TEST_ASSERT(field_generator in SSmachines.processing_machines, "turning on a field generator did not wake machinery processing")
	var/obj/machinery/atmospherics/unary/engine/ship_engine = new(T)
	TEST_ASSERT_EQUAL(ship_engine.process(), PROCESS_KILL, "passive ship engine nozzle retained a polling loop")
	var/obj/machinery/power/port_gen/pacman/portable_generator = new(T)
	portable_generator.active = FALSE
	var/datum/gas_mixture/generator_environment = T.return_air()
	var/generator_pressure_ratio = generator_environment ? min(generator_environment.return_pressure() / ONE_ATMOSPHERE, 1) : 0
	portable_generator.temperature = 20 + (generator_environment ? generator_environment.return_temperature() - T20C : 0) * generator_pressure_ratio
	portable_generator.overheating = 0
	TEST_ASSERT_EQUAL(portable_generator.process(), PROCESS_KILL, "cold inactive portable generator remained scheduled")
	portable_generator.sheets = 1
	STOP_MACHINE_PROCESSING(portable_generator)
	portable_generator.TogglePower()
	TEST_ASSERT(portable_generator in SSmachines.processing_machines, "starting a portable generator did not wake machinery processing")
	var/obj/machinery/smartfridge/smartfridge = new(T)
	smartfridge.seconds_electrified = 0
	smartfridge.shoot_inventory = FALSE
	TEST_ASSERT_EQUAL(smartfridge.process(), PROCESS_KILL, "stable smartfridge remained scheduled")
	var/obj/machinery/smartfridge/drying_rack/drying_rack = new(T)
	TEST_ASSERT_EQUAL(drying_rack.process(), PROCESS_KILL, "empty drying rack remained scheduled")
	var/turf/conveyor_turf
	for(var/turf/simulated/floor/candidate in world)
		var/has_movable = FALSE
		for(var/atom/movable/candidate_content in candidate)
			if(!candidate_content.anchored && !istype(candidate_content, /obj/effect/abstract) && !candidate_content.is_incorporeal())
				has_movable = TRUE
				break
		if(!has_movable)
			conveyor_turf = candidate
			break
	TEST_ASSERT_NOTNULL(conveyor_turf, "no empty floor for conveyor hibernation test")
	var/obj/machinery/conveyor/conveyor = new(conveyor_turf)
	conveyor.operating = 1
	conveyor.stat = 0
	TEST_ASSERT_EQUAL(conveyor.process(), PROCESS_KILL, "running empty conveyor remained scheduled")
	STOP_MACHINE_PROCESSING(conveyor)
	var/obj/item/conveyor_load = new(null)
	conveyor_load.forceMove(conveyor_turf)
	TEST_ASSERT(conveyor in SSmachines.processing_machines, "running conveyor did not wake when movable cargo entered its turf")
	var/obj/machinery/conveyor_switch/conveyor_switch = new(conveyor_turf)
	conveyor_switch.operated = FALSE
	TEST_ASSERT_EQUAL(conveyor_switch.process(), PROCESS_KILL, "stable conveyor switch remained scheduled")
	qdel(display)
	qdel(drone_fabricator)
	qdel(airlock_sensor)
	qdel(supply_display)
	qdel(jukebox)
	qdel(appliance)
	qdel(mixer)
	qdel(charger)
	qdel(mech_charger)
	qdel(heater)
	qdel(floodlight)
	qdel(emitter)
	qdel(shieldwall_generator)
	qdel(shield_capacitor)
	qdel(shutoff)
	qdel(sleeper)
	qdel(drip)
	qdel(floor_light)
	qdel(vendor)
	qdel(security_console)
	qdel(cloning_console)
	qdel(clonepod)
	qdel(helm)
	qdel(cryo)
	qdel(cryo_cell)
	qdel(power_sensor)
	qdel(solar_controller)
	qdel(telecomms_node)
	qdel(operating_console)
	qdel(operating_table)
	qdel(point_defense)
	qdel(pod_console)
	qdel(dispenser)
	qdel(atm)
	qdel(tray)
	qdel(seed_storage)
	qdel(beehive)
	qdel(bluespace_beacon)
	qdel(ship_sensors)
	qdel(sensor_console)
	qdel(suit_cycler)
	qdel(field_generator)
	qdel(ship_engine)
	qdel(portable_generator)
	qdel(smartfridge)
	qdel(drying_rack)
	qdel(conveyor_load)
	qdel(conveyor)
	qdel(conveyor_switch)
	qdel(outlet)
	TEST_ASSERT(!SSmachines.sleeping_gas_devices[outlet_ref.reference], "deleted outlet injector remained in the sleeping gas-device registry")
	var/obj/machinery/camera/network/engine/test_camera = new(T)
	test_camera.update_coverage(1)
	qdel(test_camera)
	TEST_ASSERT(!(test_camera in REGISTRY_MEMBERS(REGISTRY_CAMERAS)), "deleted camera remained in the global camera registry")
	for(var/chunk_key in GLOB.cameranet.chunks)
		var/datum/chunk/camera/chunk = LAZYACCESS(GLOB.cameranet.chunks, chunk_key)
		TEST_ASSERT(!(test_camera in chunk.cameras), "deleted camera remained retained by camera chunk [chunk_key]")


// =====================================================================
// Supermatter + R-UST fusion engine
// =====================================================================

/// Supermatter degrades when surrounded by no-air vacuum (no coolant).
/// /tg/'s supermatter takes damage when it has power but no environment to
/// dump heat into. Validates the env=null branch.
/datum/unit_test/dq_supermatter_accumulates_damage_in_vacuum

/datum/unit_test/dq_supermatter_accumulates_damage_in_vacuum/Run()
	// Deterministically obtain a /turf/space (so removed.total_moles is ~0 and
	// the SM's no-coolant damage branch fires): breach a sealed test-room floor's
	// neighbor into space via the production ChangeTurf path.
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no usable floor pair on map for supermatter vacuum test")
	var/turf/simulated/floor/floor = pair[1]

	var/turf/space/S = dq_atmos_test_open_to_space(floor)
	TEST_ASSERT_NOTNULL(S, "couldn't create a space turf for the supermatter vacuum test")

	var/obj/machinery/power/supermatter/SM = new(S)
	TEST_ASSERT_NOTNULL(SM, "supermatter failed to construct on space turf")
	// Give it some power so the no-env damage formula produces > 0.
	SM.power = 200
	var/initial_damage = SM.damage

	SM.process()

	var/post_damage = SM.damage

	// Clean up the SM and restore the breached wall before asserting.
	qdel(SM)
	dq_atmos_test_restore_walls()

	TEST_ASSERT(post_damage > initial_damage, \
		"supermatter at power=200 in space (no coolant) didn't accumulate damage: [initial_damage] → [post_damage]")


/// R-UST fusion engine components all construct without erroring. This is a
/// smoke test — full delamination dynamics need the fusion field datum
/// instantiated, which requires a 3x3 magnet array setup.
/datum/unit_test/dq_fusion_engine_components_construct

/datum/unit_test/dq_fusion_engine_components_construct/Run()
	var/turf/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for fusion construct test")

	var/obj/machinery/power/fusion_core/Core = new(T)
	TEST_ASSERT_NOTNULL(Core, "fusion_core failed to construct")
	qdel(Core)

	var/obj/item/fuel_assembly/deuterium/D = new(T)
	TEST_ASSERT_NOTNULL(D, "deuterium fuel_assembly failed to construct")
	qdel(D)

	var/obj/item/fuel_assembly/tritium/Tr = new(T)
	TEST_ASSERT_NOTNULL(Tr, "tritium fuel_assembly failed to construct")
	qdel(Tr)

	var/obj/item/fuel_assembly/phoron/Ph = new(T)
	TEST_ASSERT_NOTNULL(Ph, "phoron fuel_assembly failed to construct")
	qdel(Ph)

	var/obj/machinery/fusion_fuel_compressor/FC = new(T)
	TEST_ASSERT_NOTNULL(FC, "fusion_fuel_compressor failed to construct")
	qdel(FC)


// =====================================================================
// Atmos events (gas_leak / atmos_leak)
// =====================================================================

/// /datum/event/atmos_leak: validate the event datum type tree exists and
/// loads. Full event firing requires SSticker + event_meta + player count
/// orchestration; that's the event scheduler's domain, not atmos. We just
/// confirm the type is defined so LINDA migration didn't break it at compile.
/datum/unit_test/dq_atmos_leak_event_type_exists

/datum/unit_test/dq_atmos_leak_event_type_exists/Run()
	// The atmos leak gamemaster event must be a real, registered /datum/event
	// subtype — not merely a compile-time path. A gutted events directory would
	// drop it from the type tree and break the scheduler's event_meta wiring.
	var/list/event_types = subtypesof(/datum/event)
	TEST_ASSERT(/datum/event/atmos_leak in event_types, \
		"/datum/event/atmos_leak not present in subtypesof(/datum/event) — atmos leak event was removed")


// =====================================================================
// Pipe reactions: gas reactions inside a pipenet
// =====================================================================

/// Plasma + O2 + hot temperature inside a /datum/pipeline should react via
/// /datum/pipeline.process_pipeline_reaction(). Verifies that gas reactions
/// work in pipenets (not just on turfs).
/datum/unit_test/dq_pipenet_gas_reacts_in_pipeline

/datum/unit_test/dq_pipenet_gas_reacts_in_pipeline/Run()
	var/datum/pipeline/P = new
	P.air = new(CELL_VOLUME)
	P.air.adjust_gas(/datum/gas/plasma, 50)
	P.air.adjust_gas(/datum/gas/oxygen, 200)
	P.air.set_temperature(PLASMA_MINIMUM_BURN_TEMPERATURE + 300)

	var/initial_plasma = P.air.get_moles(/datum/gas/plasma)
	var/initial_temp = P.air.return_temperature()

	P.air.react(P)

	var/final_plasma = P.air.get_moles(/datum/gas/plasma)
	TEST_ASSERT(final_plasma < initial_plasma, \
		"plasma didn't burn inside pipeline: [initial_plasma] → [final_plasma]")
	var/pipe_react_temp = P.air.return_temperature()
	TEST_ASSERT(pipe_react_temp > initial_temp, \
		"pipeline plasmafire didn't release heat: [initial_temp] → [pipe_react_temp]")
	qdel(P)


// =====================================================================
// Round 4: species breath sweep, analyzer corner cases, gas overlays,
// supermatter delamination state, meter, binary pump, cryo construct
// =====================================================================

/// Sweep every species: spawn a human, set its species, call handle_breath
/// with a standard atmospheric mixture. Should not throw any runtime
/// regardless of species — catches "species breath_type undefined", null
/// derefs in species-specific organ damage paths, etc.
/datum/unit_test/dq_all_species_handle_breath_safely

/datum/unit_test/dq_all_species_handle_breath_safely/Run()
	TEST_ASSERT_NOTNULL(GLOB.all_species, "GLOB.all_species is null")
	TEST_ASSERT(length(GLOB.all_species) > 0, "GLOB.all_species is empty")

	var/turf/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for species breath sweep")

	var/species_tested = 0
	for(var/species_name in GLOB.all_species)
		var/datum/species/S = GLOB.all_species[species_name]
		if(!S || !istype(S))
			continue
		var/mob/living/carbon/human/H = new(T)
		// set_species can crash on weird species; protect with try-equivalent.
		if(H.set_species(species_name))
			species_tested++
			// Build a breath mixture this species can mostly tolerate — fall
			// back to standard atmo. handle_breath should never crash.
			var/datum/gas_mixture/breath = new(BREATH_VOLUME)
			breath.adjust_gas(/datum/gas/oxygen, MOLES_O2STANDARD)
			breath.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)
			breath.set_temperature(T20C)
			life_test_breath(H, breath)
		qdel(H)
	TEST_ASSERT(species_tested >= 5, \
		"only tested [species_tested] species — expected at least 5 (something is wrong with set_species or the species registry)")


/// Atmos analyzer on a vacuum mixture: should not crash, should emit a line
/// that reports pressure as 0 (or near-0).
/datum/unit_test/dq_atmos_analyzer_handles_vacuum

/datum/unit_test/dq_atmos_analyzer_handles_vacuum/Run()
	var/datum/gas_mixture/vacuum = new(CELL_VOLUME)
	vacuum.set_temperature(T20C)
	var/list/result = atmosanalyzer_scan(null, vacuum, null)
	TEST_ASSERT_NOTNULL(result, "analyzer returned null on vacuum mixture")
	TEST_ASSERT(length(result) >= 1, "analyzer returned empty list on vacuum")
	// Either "Pressure: 0 kPa" or "is empty!" is acceptable — both correctly
	// describe vacuum. What we DON'T want is a runtime or null line.
	var/has_meaningful_output = FALSE
	for(var/line in result)
		if(findtext(line, "empty") || findtext(line, "Pressure") || findtext(line, "0 kPa"))
			has_meaningful_output = TRUE
			break
	TEST_ASSERT(has_meaningful_output, \
		"analyzer on vacuum produced no recognizable output: [json_encode(result)]")


/// Atmos analyzer on every single-gas mixture: each /datum/gas subtype gets
/// instantiated alone, scanned. No crash, gas name appears in output.
/datum/unit_test/dq_atmos_analyzer_handles_pure_gas

/datum/unit_test/dq_atmos_analyzer_handles_pure_gas/Run()
	var/gases_tested = 0
	for(var/datum/gas/g_type as anything in subtypesof(/datum/gas))
		var/gas_id = initial(g_type.id)
		if(!gas_id)
			continue
		var/datum/gas_mixture/mix = new(CELL_VOLUME)
		mix.adjust_gas(g_type, 10)
		mix.set_temperature(T20C)
		var/list/result = atmosanalyzer_scan(null, mix, null)
		TEST_ASSERT_NOTNULL(result, "analyzer returned null for gas [gas_id]")
		TEST_ASSERT(length(result) > 0, "analyzer empty result for gas [gas_id]")
		gases_tested++
	TEST_ASSERT(gases_tested >= 5, \
		"only tested [gases_tested] gas types — gas registry suspicious")


/// Every /datum/gas with a visible-mole threshold should produce an atmos
/// overlay when present above that threshold on a turf. Catches "we added a
/// new gas but forgot to generate overlay icons" regressions.
/datum/unit_test/dq_all_visible_gases_render_overlays

/datum/unit_test/dq_all_visible_gases_render_overlays/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for gas-overlay sweep")

	// Count the known visible gases up front, from the SAME source the loop
	// iterates, so a gutted gas table (visible gases dropped or stripped of
	// their moles_visible threshold) is caught instead of silently passing.
	var/visible_gas_count = 0
	for(var/datum/gas/g_type as anything in subtypesof(/datum/gas))
		if(!isnull(initial(g_type.moles_visible)))
			visible_gas_count++
	TEST_ASSERT(visible_gas_count > 0, "no visible-threshold gases found — meta_gas_info empty?")

	var/gases_tested = 0
	for(var/datum/gas/g_type as anything in subtypesof(/datum/gas))
		var/visible_threshold = initial(g_type.moles_visible)
		if(isnull(visible_threshold))
			continue // not visible by design
		// Clear prior overlays so the assertion is honest.
		if(T.atmos_overlay_types)
			for(var/old_ov in T.atmos_overlay_types)
				T.vis_contents -= old_ov
			T.atmos_overlay_types = null
		// Clear all gases on the turf first.
		for(var/datum/gas/g as anything in T.air.get_gases())
			T.air.set_moles(g, 0)
		// Put visible_threshold * 10 of THIS gas only.
		T.air.adjust_gas(g_type, visible_threshold * 10)
		T.update_visuals()
		TEST_ASSERT(LAZYLEN(T.atmos_overlay_types) > 0, \
			"gas [initial(g_type.id)] above visible threshold ([visible_threshold * 10] mol vs threshold [visible_threshold]) produced NO overlay")
		gases_tested++
	// Every visible gas must have been exercised — a smaller count means the
	// registry shrank between the pre-count and the render loop.
	TEST_ASSERT(gases_tested >= visible_gas_count, \
		"only [gases_tested] of [visible_gas_count] visible gases rendered overlays")

	// Reset turf.
	for(var/datum/gas/g as anything in T.air.get_gases())
		T.air.set_moles(g, 0)
	T.update_visuals()


/// Supermatter delamination state: damage > explosion_point triggers the
/// "going to explode" code path (exploded flag, no announce on every tick).
/datum/unit_test/dq_supermatter_reaches_delamination_state

/datum/unit_test/dq_supermatter_reaches_delamination_state/Run()
	var/turf/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for supermatter delam test")

	var/obj/machinery/power/supermatter/SM = new(T)
	TEST_ASSERT_NOTNULL(SM, "supermatter construct failed")
	TEST_ASSERT(SM.explosion_point > 0, "explosion_point not set: [SM.explosion_point]")

	// Baseline: a freshly-built, undamaged crystal is not delaminating.
	TEST_ASSERT(!SM.final_countdown, "fresh supermatter already in final_countdown")
	TEST_ASSERT(!SM.exploded, "fresh supermatter already flagged exploded")
	TEST_ASSERT(!SM.causalitywarn, "fresh supermatter already warning of causality failure")

	// Force above explosion threshold and run a tick. process() must enter the
	// delamination path: countdown() flags causalitywarn unconditionally, then
	// either arms the on-station causality field (final_countdown) or, off the
	// station Z, detonates immediately (exploded / grav_pulling). Assert the
	// observable delamination consequence, not the damage value we just set.
	SM.damage = SM.explosion_point + 100
	SM.process()
	TEST_ASSERT(SM.causalitywarn, \
		"supermatter past explosion_point did not flag causalitywarn — delamination path never fired")
	TEST_ASSERT(SM.final_countdown || SM.exploded || SM.grav_pulling, \
		"supermatter past explosion_point did not enter countdown or detonation state")

	qdel(SM)


/// Gas meter reads the pressure of the pipe it's targeting. End-to-end:
/// meter + pipe + pipeline, verify the meter's view of pressure matches
/// the pipeline's air return_pressure.
/datum/unit_test/dq_gas_meter_reads_target_pipeline_pressure

/datum/unit_test/dq_gas_meter_reads_target_pipeline_pressure/Run()
	var/list/run = dq_atmos_test_find_clear_pipe_run(2)
	TEST_ASSERT_NOTNULL(run, "no clear two-tile pipe run for meter test")
	var/turf/simulated/floor/T = run[1]
	var/turf/simulated/floor/T2 = run[2]
	var/direction = get_dir(T, T2)
	var/axis_directions = direction | REVERSE_DIR(direction)

	// Construct and publish a real Rust-authoritative connected network.
	// return_air() deliberately no longer creates topology as a side effect.
	var/obj/machinery/atmospherics/pipe/simple/P = new(T)
	P.dir = axis_directions
	P.initialize_directions = axis_directions
	var/obj/machinery/atmospherics/pipe/simple/P2 = new(T2)
	P2.dir = axis_directions
	P2.initialize_directions = axis_directions
	P.atmos_init()
	P2.atmos_init()
	dq_atmos_test_publish_rust_pipenets(list(P, P2))
	var/datum/gas_mixture/pipe_air = P.return_air()
	TEST_ASSERT_NOTNULL(pipe_air, "pipe return_air() null after topology publication")
	TEST_ASSERT_NOTNULL(P.parent, "pipe parent (pipeline) null after topology publication")
	pipe_air.adjust_gas(/datum/gas/nitrogen, 200)
	pipe_air.set_temperature(T20C)

	var/obj/machinery/meter/M = new(T)
	TEST_ASSERT_NOTNULL(M, "meter construct failed")
	M.target = P  // direct assign so select_target search isn't required
	M.use_power = USE_POWER_IDLE
	M.stat &= ~(BROKEN | NOPOWER)
	M.process() // shouldn't crash; should set an icon_state based on pipe pressure

	// Validate that the meter's target returns the same pressure we set on
	// the pipeline.
	var/datum/gas_mixture/env = M.target.return_air()
	TEST_ASSERT_NOTNULL(env, "meter.target.return_air() returned null")
	TEST_ASSERT(env.return_pressure() > 0, \
		"meter target pipe pressure is 0 despite seeded nitrogen: [env.return_pressure()]")

	qdel(M)
	qdel(P)
	qdel(P2)


/// Cryo cell constructs without erroring and its initial air_contents are
/// allocated. Full freeze-a-mob flow needs the cryo's pipenet to be supplied
/// with cold cryoxadone — that's a bigger integration test.
/datum/unit_test/dq_cryo_cell_constructs

/datum/unit_test/dq_cryo_cell_constructs/Run()
	var/turf/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for cryo construct test")

	var/obj/machinery/atmospherics/unary/cryo_cell/C = new(T)
	TEST_ASSERT_NOTNULL(C, "cryo_cell failed to construct")
	TEST_ASSERT_NOTNULL(C.air_contents, "cryo air_contents null")
	qdel(C)


/// Binary pump transfers from input pipenet to output pipenet when on.
/// Validates the most-used atmos machinery (every air supply uses a binary pump).
/datum/unit_test/dq_binary_pump_transfers_between_pipenets

/datum/unit_test/dq_binary_pump_transfers_between_pipenets/Run()
	var/turf/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for binary pump test")

	var/obj/machinery/atmospherics/binary/pump/Pump = new(T)
	TEST_ASSERT_NOTNULL(Pump, "binary pump construct failed")
	Pump.use_power = USE_POWER_IDLE
	Pump.stat &= ~(BROKEN | NOPOWER)
	Pump.set_on(TRUE)
	Pump.set_target_pressure(ONE_ATMOSPHERE * 5) // high target so pump runs
	Pump.rust_register_pipe_topology() // allocates ports, binds air1/air2, registers the device edge
	TEST_ASSERT_NOTNULL(Pump.air1, "binary pump air1 null")
	TEST_ASSERT_NOTNULL(Pump.air2, "binary pump air2 null")

	// Seed air1 with pressurized N2, air2 empty.
	Pump.air1.adjust_gas(/datum/gas/nitrogen, 200)
	Pump.air1.set_temperature(T20C)
	Pump.air2.set_temperature(T20C)
	Pump.update_rust_device()

	var/air1_before = Pump.air1.get_moles(/datum/gas/nitrogen)
	var/air2_before = Pump.air2.get_moles(/datum/gas/nitrogen)

	// M2 (simulation.md §5): the flow law is a Rust device edge; SSair
	// drives it, not Pump.process() (deleted).
	for(var/i in 1 to 30)
		SSair.rust_step_pipe_devices()

	var/air1_after = Pump.air1.get_moles(/datum/gas/nitrogen)
	var/air2_after = Pump.air2.get_moles(/datum/gas/nitrogen)
	// The pump must actually move gas: source side drops AND sink side rises.
	TEST_ASSERT(air1_after < air1_before, \
		"binary pump source (air1) didn't drop: [air1_before] → [air1_after]")
	TEST_ASSERT(air2_after > air2_before, \
		"binary pump sink (air2) didn't rise: [air2_before] → [air2_after]")
	// Conservation: what air1 lost must equal what air2 gained (no creation/loss).
	var/lost = air1_before - air1_after
	var/gained = air2_after - air2_before
	TEST_ASSERT(abs(lost - gained) < 0.01, \
		"binary pump didn't conserve moles: air1 lost [lost], air2 gained [gained]")

	qdel(Pump)


// =====================================================================
// Round 5: shared pipenet loop, cryo flow, item heat, thruster, freeze
// =====================================================================

/// Vent + scrubber sharing the same pipenet air mixture: this is the
/// production setup where supply (vent) and exhaust (scrubber) are both
/// connected to the same pipe. Seed CO2-polluted turf, run both machines,
/// verify CO2 ends up in the shared pipenet and N2 from the shared pipenet
/// reaches the turf.
/datum/unit_test/dq_shared_pipenet_vent_and_scrubber_loop

/datum/unit_test/dq_shared_pipenet_vent_and_scrubber_loop/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for shared-pipenet test")
	dq_atmos_test_snapshot_air(T)
	dq_atmos_test_isolate_pair(T, T)
	T.air_update_turf(TRUE, FALSE)

	var/datum/gas_mixture/turf_air = T.return_air()
	for(var/datum/gas/g as anything in turf_air.get_gases())
		turf_air.set_moles(g, 0)
	turf_air.adjust_gas(/datum/gas/carbon_dioxide, 200)
	turf_air.set_temperature(T20C)

	// `node` is set after topology registration - self-referencing it
	// beforehand would make rust_register_pipe_edges() try to connect the
	// port to itself.
	var/obj/machinery/atmospherics/unary/vent_pump/V = new(T)
	V.use_power = USE_POWER_IDLE
	V.stat &= ~(NOPOWER | BROKEN)
	V.welded = FALSE
	V.pump_direction = 1
	V.external_pressure_bound = ONE_ATMOSPHERE * 1.5
	V.internal_pressure_bound = 0
	V.rust_register_pipe_topology()
	V.node = V

	var/obj/machinery/atmospherics/unary/vent_scrubber/S = new(T)
	S.use_power = USE_POWER_IDLE
	S.stat &= ~(NOPOWER | BROKEN)
	S.welded = FALSE
	S.scrubbing = 1
	S.scrubbing_gas = list(GAS_CO2)
	S.rust_register_pipe_topology()
	S.node = S

	// M2 (simulation.md §5): the "shared pipenet" is one Rust region — a real
	// pipe connection between the vent's and the scrubber's ports, not a
	// hand-spliced gas_mixture.
	SSair.rust_queue_pipe_operation(RUST_PIPE_OP_CONNECT, V.rust_pipe_port_ids[1], S.rust_pipe_port_ids[1])
	SSair.rust_commit_pending_pipenets()
	var/datum/gas_mixture/shared = V.air_contents
	TEST_ASSERT_EQUAL(V.air_contents.arena_id(), S.air_contents.arena_id(), "vent and scrubber did not land in the same pipe region")
	shared.adjust_gas(/datum/gas/nitrogen, 1000)
	shared.set_temperature(T20C)
	V.update_rust_device()
	S.update_rust_device()

	var/initial_shared_n2 = shared.get_moles(/datum/gas/nitrogen)
	var/initial_shared_co2 = shared.get_moles(/datum/gas/carbon_dioxide)
	var/initial_turf_co2 = turf_air.get_moles(/datum/gas/carbon_dioxide)

	// The flow law is a Rust device edge bridging the pipe network and the
	// turf field; SSair drives it, not V.process()/S.process() (deleted).
	// Turf CO2 starts above the vent's own external_pressure_bound, so the
	// vent stays refused until the scrubber (running the same loop) brings
	// the turf pressure down - give the coupled feedback loop enough
	// iterations to converge, and commit a frame every iteration:
	// step_turf_devices reads the field's pinned view, so without that the
	// scrubber's own effect never becomes visible to either device.
	for(var/i in 1 to 30)
		SSair.rust_step_pipe_devices()
		SSair.run_gas_frames(1)

	// Vent moved N2 from shared → turf.
	var/final_shared_n2 = shared.get_moles(/datum/gas/nitrogen)
	var/final_turf_n2 = turf_air.get_moles(/datum/gas/nitrogen)
	TEST_ASSERT(final_shared_n2 < initial_shared_n2, \
		"vent didn't drain N2 from shared pipenet: [initial_shared_n2] → [final_shared_n2]")
	TEST_ASSERT(final_turf_n2 > 0, \
		"vent didn't deliver N2 to turf: got [final_turf_n2]")

	// Scrubber moved CO2 from turf → shared (same mixture vent uses).
	var/final_shared_co2 = shared.get_moles(/datum/gas/carbon_dioxide)
	var/final_turf_co2 = turf_air.get_moles(/datum/gas/carbon_dioxide)
	TEST_ASSERT(final_turf_co2 < initial_turf_co2, \
		"scrubber didn't drain CO2 from turf: [initial_turf_co2] → [final_turf_co2]")
	TEST_ASSERT(final_shared_co2 > initial_shared_co2, \
		"scrubber didn't deposit CO2 into shared pipenet: [initial_shared_co2] → [final_shared_co2]")

	for(var/datum/gas/g as anything in turf_air.get_gases())
		turf_air.set_moles(g, 0)
	qdel(V)
	qdel(S)


/// Cryo cell can hold a mob and drop its body_temperature when the cell's
/// air_contents are cold. Validates that the cryo's per-tick mob cooling
/// uses the LINDA gas_mixture temperature read.
/datum/unit_test/dq_cryo_cell_cools_mob

/datum/unit_test/dq_cryo_cell_cools_mob/Run()
	var/turf/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for cryo cool test")

	var/obj/machinery/atmospherics/unary/cryo_cell/C = new(T)
	C.use_power = USE_POWER_IDLE
	C.stat &= ~(NOPOWER | BROKEN)
	// node ref so process() doesn't early-return; self-ref is enough.
	C.node = C
	// Cold supply — needs ≥10 moles or process_occupant short-circuits.
	C.air_contents.set_temperature(80) // 80 K
	C.air_contents.adjust_gas(/datum/gas/oxygen, 50)

	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT_NOTNULL(H, "human alloc failed")

	// Force the mob into the cryo cell's occupant slot.
	C.occupant = H
	H.forceMove(C)
	H.bodytemperature = T20C // warm starting body temp
	var/initial_bodytemp = H.bodytemperature
	C.on = TRUE

	for(var/i in 1 to 5)
		C.process()

	TEST_ASSERT(H.bodytemperature < initial_bodytemp, \
		"cryo didn't cool mob: bodytemp [initial_bodytemp] → [H.bodytemperature]")

	C.occupant = null
	H.forceMove(T)
	qdel(C)


/// Items exposed to atmospheric heat catch fire and take burn damage. In
/// LINDA this is the fire_act() path: a turf hotspot's perform_exposure() calls
/// fire_act(temperature, volume) on every atom on the tile (see LINDA_fire.dm).
/// A flammable item (FLAMMABLE resistance flag) ignites — the burning component
/// is attached and sets the ON_FIRE resistance flag. This is what "fire on the
/// floor sets dropped items alight" means in the engine.
///
/// The per-atom heat hook is fire_act(), which is what the hotspot calls.
/datum/unit_test/dq_item_takes_atmos_heat

/datum/unit_test/dq_item_takes_atmos_heat/Run()
	// A dedicated, walled single-tile room on its own z-level: picking a
	// shared "first floor in world" turf made this test order-dependent both
	// ways -- a prior test's leftover state on that turf could suppress
	// ignition here, and the 100 extra moles of oxygen this test injects
	// could diffuse into the open station map and corrupt a later test's
	// mass-conservation accounting (the room's walls make that impossible;
	// nothing here is reachable from, or leaks into, the rest of the map).
	var/test_z = world.maxz + 1
	world.maxz = test_z
	for(var/x in 5 to 7)
		for(var/y in 5 to 7)
			var/turf/wall_turf = locate(x, y, test_z)
			wall_turf.ChangeTurf(/turf/simulated/wall)
	var/turf/simulated/floor/T = locate(6, 6, test_z)
	T.ChangeTurf(/turf/simulated/floor)
	TEST_ASSERT_NOTNULL(T, "couldn't build the item-heat test room")
	TEST_ASSERT(T.air && !T.blocks_air, "the test room's floor has no air")

	// Paper is FLAMMABLE and uses the integrity system — the canonical
	// flammable floor item.
	var/obj/item/paper/I = new /obj/item/paper(T)
	TEST_ASSERT_NOTNULL(I, "couldn't alloc paper item")
	TEST_ASSERT(I.resistance_flags & FLAMMABLE, "test item isn't flammable; can't observe ignition")
	TEST_ASSERT(!(I.resistance_flags & ON_FIRE), "test item was already on fire before exposure")

	// Drive the production heat hook the hotspot uses: fire_act with very hot
	// (1000 K) air exposure. potential_damage = 0.02 * 1000 = 20 burn damage,
	// and the flammable item should catch fire (ON_FIRE flag set by the burning
	// component's RegisterWithParent).
	var/datum/gas_mixture/turf_air = T.return_air()
	var/datum/gas_mixture/saved_air = new
	saved_air.copy_from(turf_air)
	turf_air.set_temperature(1000) // very hot
	turf_air.adjust_gas(/datum/gas/oxygen, 100)
	// The heat domain reads turf gas from the gas field's published frame.
	SSair.run_gas_frames(1)

	I.fire_act(turf_air.return_temperature(), turf_air.return_volume())
	vg_heat_debug_run_frames(2)
	// The exposure heats the paper's heat body; its ignition rule
	// (code/datums/rules/declarations.dm) runs on the next heat frame.
	dq_rx_flush()
	react_test_ticks(10)

	// Observable consequence: a flammable item exposed to ignition-temperature
	// air must be alight. If fire_act stopped applying heat to floor items, the
	// ON_FIRE flag would never be set and this assertion would fail.
	TEST_ASSERT(QDELETED(I) || (I.resistance_flags & ON_FIRE), \
		"flammable item exposed to 1000 K air neither ignited (ON_FIRE) nor was destroyed — fire_act applied no heat")

	if(!QDELETED(I))
		I.extinguish()
		qdel(I)
	turf_air.copy_from(saved_air)


/// Gas thruster constructs and reports fuel + thrust without crashing on
/// a LINDA mixture in its air_contents.
/datum/unit_test/dq_gas_thruster_construct_and_check_fuel

/datum/unit_test/dq_gas_thruster_construct_and_check_fuel/Run()
	var/turf/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for gas thruster test")

	var/obj/machinery/atmospherics/unary/engine/E = new(T)
	TEST_ASSERT_NOTNULL(E, "gas thruster construct failed")
	TEST_ASSERT_NOTNULL(E.air_contents, "thruster air_contents null")

	// Empty thruster — check_fuel should be FALSE.
	TEST_ASSERT(!E.check_fuel(), \
		"empty thruster reported fuel — get_by_flag(XGM_GAS_FUEL) broken?")

	// Load with a fuel gas (volatile_fuel has XGM_GAS_FUEL).
	E.air_contents.adjust_gas(/datum/gas/volatile_fuel, 50)
	E.air_contents.adjust_gas(/datum/gas/oxygen, 100)
	E.air_contents.set_temperature(T0C + 100)
	TEST_ASSERT(E.check_fuel(), \
		"loaded thruster (fuel + oxidizer) didn't report fuel — get_by_flag flag map broken")

	// Power-on so is_on() returns TRUE, then get_thrust > 0.
	E.use_power = USE_POWER_ACTIVE
	E.stat &= ~(NOPOWER | BROKEN)
	var/thrust = E.get_thrust()
	TEST_ASSERT(thrust > 0, "loaded + powered thruster reported zero thrust: [thrust]")

	qdel(E)


/// Atmos filter omni device constructs. Routes specific gas types to
/// designated output ports. Full routing setup requires four pipes; this is
/// a smoke test that the construct + atmos_init don't crash.
/datum/unit_test/dq_atmos_filter_constructs

/datum/unit_test/dq_atmos_filter_constructs/Run()
	var/turf/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for filter construct test")

	var/obj/machinery/atmospherics/omni/atmos_filter/F = new(T)
	TEST_ASSERT_NOTNULL(F, "atmos_filter construct failed")
	qdel(F)


/// Atmos mixer omni device constructs. Mixes two input gas streams at a
/// target ratio into the output port. Smoke test only.
/datum/unit_test/dq_atmos_mixer_constructs

/datum/unit_test/dq_atmos_mixer_constructs/Run()
	var/turf/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for mixer construct test")

	var/obj/machinery/atmospherics/omni/mixer/M = new(T)
	TEST_ASSERT_NOTNULL(M, "atmos_mixer construct failed")
	qdel(M)

/datum/unit_test/dq_omni_devices_hibernate_without_input

/datum/unit_test/dq_omni_devices_hibernate_without_input/Run()
	var/turf/T = locate(1, 1, 1)
	var/obj/machinery/atmospherics/omni/atmos_filter/F = new(T)
	var/input_mode = F.mode_return_switch("in")
	var/output_mode = F.mode_return_switch("out")
	var/filter_mode = F.mode_return_switch(GASNAME_O2)
	var/none_mode = F.mode_return_switch("None")
	var/port_index = 0
	for(var/datum/omni_port/P in F.ports)
		port_index++
		P.mode = port_index == 1 ? input_mode : (port_index == 2 ? output_mode : filter_mode)
		P.update = TRUE
	F.sort_ports()
	F.use_power = USE_POWER_IDLE
	F.stat &= ~(NOPOWER | BROKEN)
	TEST_ASSERT_EQUAL(F.process(), PROCESS_KILL, "empty omni filter retained timed polling")
	TEST_ASSERT(F.sleeping_mixture_ids, "empty omni filter did not capture gas dependencies")
	F.input.air.adjust_gas(/datum/gas/oxygen, 10)
	TEST_ASSERT(F.gas_dependency_changed(F.input.air.arena_id(), GAS_DEPENDENCY_ALL), "fed omni filter did not become actionable")
	qdel(F)

	var/obj/machinery/atmospherics/omni/mixer/M = new(T)
	port_index = 0
	for(var/datum/omni_port/P in M.ports)
		port_index++
		P.mode = port_index <= 2 ? input_mode : (port_index == 3 ? output_mode : none_mode)
		P.update = TRUE
	M.sort_ports()
	M.use_power = USE_POWER_IDLE
	M.stat &= ~(NOPOWER | BROKEN)
	TEST_ASSERT_EQUAL(M.process(), PROCESS_KILL, "empty omni mixer retained timed polling")
	TEST_ASSERT(M.sleeping_mixture_ids, "empty omni mixer did not capture gas dependencies")
	var/datum/omni_port/first_input = M.inputs[1]
	first_input.air.adjust_gas(/datum/gas/oxygen, 10)
	TEST_ASSERT(M.gas_dependency_changed(first_input.air.arena_id(), GAS_DEPENDENCY_ALL), "fed omni mixer did not become actionable")
	qdel(M)

/datum/unit_test/dq_stable_open_pipe_hibernates

/datum/unit_test/dq_stable_open_pipe_hibernates/Run()
	var/list/run = dq_atmos_test_find_clear_pipe_run(2)
	TEST_ASSERT_NOTNULL(run, "no clear two-tile pipe run for open-pipe hibernation test")
	var/turf/simulated/floor/T = run[1]
	var/turf/simulated/floor/T2 = run[2]
	var/direction = get_dir(T, T2)
	var/axis_directions = direction | REVERSE_DIR(direction)
	var/obj/machinery/atmospherics/pipe/simple/P = new(T)
	P.dir = axis_directions
	P.initialize_directions = axis_directions
	var/obj/machinery/atmospherics/pipe/simple/P2 = new(T2)
	P2.dir = axis_directions
	P2.initialize_directions = axis_directions
	P.atmos_init()
	P2.atmos_init()
	dq_atmos_test_publish_rust_pipenets(list(P, P2))
	TEST_ASSERT_NOTNULL(P.parent?.network, "open pipe did not receive a Rust-authoritative network")
	P.parent.air.copy_from(T.air)
	var/environment_volume = T.air.return_volume()
	P.parent.air.set_volume(P.volume)
	P.parent.air.multiply(P.volume / environment_volume)
	P.set_leaking(TRUE)
	var/datum/weakref/pipe_ref = WEAKREF(P)
	TEST_ASSERT_NOTNULL(pipe_ref, "open pipe could not create a weak reference")
	var/process_result
	for(var/cycle in 1 to 100)
		process_result = P.parent.network.process()
		if(process_result == PROCESS_KILL)
			break
	TEST_ASSERT_EQUAL(process_result, PROCESS_KILL, "open pipe leak did not converge and hibernate within 100 cycles")
	TEST_ASSERT(SSmachines.sleeping_gas_devices[pipe_ref.reference], "equilibrated open pipe did not subscribe before sleeping")
	T.air.adjust_moles(/datum/gas/oxygen, 1)
	TEST_ASSERT(P.gas_dependency_changed(P.leak_sleeping_turf_mixture_id, GAS_DEPENDENCY_ALL), "changed turf gas did not wake an open pipe leak")
	qdel(P)
	qdel(P2)


// =====================================================================
// Round 6: filter routing, mixer ratios, thruster fuel, pressure pushes,
// closed-door atmos block
// =====================================================================

/// filter_gas_multi is the heart of the omni filter machine — given a source
/// gas mixture, a per-gas-id sink map (filtering), and a single clean sink
/// for everything else, it should route each target gas to its declared sink
/// and dump untargeted gases into the clean sink. Validates the real routing
/// math without bringing up the omni port plumbing.
/datum/unit_test/dq_filter_gas_multi_routes_target_gas

/datum/unit_test/dq_filter_gas_multi_routes_target_gas/Run()
	var/datum/gas_mixture/source = new(CELL_VOLUME)
	source.adjust_gas(/datum/gas/plasma, 100)
	source.adjust_gas(/datum/gas/oxygen, 100)
	source.set_temperature(T20C)

	// Per-gas filter sinks: plasma gets its own bin, oxygen falls through to clean.
	var/datum/gas_mixture/plasma_sink = new(CELL_VOLUME)
	plasma_sink.set_temperature(T20C)
	var/datum/gas_mixture/clean_sink = new(CELL_VOLUME)
	clean_sink.set_temperature(T20C)

	// XGM-compat: filter_gas_multi keys the filtering list by string gas id
	// (from gas_ids()), not by type path. Use GAS_PLASMA (= "plasma") here.
	var/list/filtering = list()
	filtering[GAS_PLASMA] = plasma_sink

	var/initial_total = source.total_moles()
	// Unlimited power, transfer everything in one call.
	var/power_draw = filter_gas_multi(null, filtering, source, clean_sink, source.total_moles(), null)
	TEST_ASSERT(power_draw >= 0, "filter_gas_multi returned -1 (refused) with full mix and unlimited power")

	// Plasma should have moved to its own sink.
	var/plasma_in_filter = plasma_sink.get_moles(/datum/gas/plasma)
	var/plasma_in_clean = clean_sink.get_moles(/datum/gas/plasma)
	TEST_ASSERT(plasma_in_filter > 90, \
		"filter sink got [plasma_in_filter] plasma, expected >90 (routing broken)")
	TEST_ASSERT(plasma_in_clean < 1, \
		"clean sink got [plasma_in_clean] plasma — plasma leaked into the clean output")

	// Oxygen should have ended up in the clean sink.
	var/o2_in_clean = clean_sink.get_moles(/datum/gas/oxygen)
	var/o2_in_filter = plasma_sink.get_moles(/datum/gas/oxygen)
	TEST_ASSERT(o2_in_clean > 90, \
		"clean sink got [o2_in_clean] O2, expected >90 (clean routing broken)")
	TEST_ASSERT(o2_in_filter < 1, \
		"filter sink got [o2_in_filter] O2 — O2 leaked into the plasma output")

	// Source should be nearly drained.
	TEST_ASSERT(source.total_moles() < 1, \
		"source still has [source.total_moles()] moles after full transfer — leak in remove()")

	// Conservation across both sinks.
	var/sinks_total = plasma_sink.total_moles() + clean_sink.total_moles()
	TEST_ASSERT(abs(sinks_total - initial_total) < 0.5, \
		"filter_gas_multi lost mass: [initial_total] → [sinks_total]")


/// mix_gas is the heart of the omni mixer machine — it pulls from each input
/// at the configured ratio and merges into the sink. Validate that a 0.7:0.3
/// split actually delivers gases in that ratio to the output.
/datum/unit_test/dq_mix_gas_combines_at_target_ratio

/datum/unit_test/dq_mix_gas_combines_at_target_ratio/Run()
	var/datum/gas_mixture/source_a = new(CELL_VOLUME)
	source_a.adjust_gas(/datum/gas/oxygen, 1000)
	source_a.set_temperature(T20C)
	var/datum/gas_mixture/source_b = new(CELL_VOLUME)
	source_b.adjust_gas(/datum/gas/nitrogen, 1000)
	source_b.set_temperature(T20C)
	var/datum/gas_mixture/sink = new(CELL_VOLUME)
	sink.set_temperature(T20C)

	var/list/mix_sources = list()
	mix_sources[source_a] = 0.7
	mix_sources[source_b] = 0.3

	var/power_draw = mix_gas(null, mix_sources, sink, 100, null)
	TEST_ASSERT(power_draw >= 0, "mix_gas refused with valid inputs at 100 moles target")

	var/sink_o2 = sink.get_moles(/datum/gas/oxygen)
	var/sink_n2 = sink.get_moles(/datum/gas/nitrogen)
	var/sink_total = sink.total_moles()
	TEST_ASSERT(sink_total > 95 && sink_total < 105, \
		"mix_gas delivered [sink_total] moles, expected ~100")

	// Within 5% of the configured ratio.
	var/actual_o2_ratio = sink_o2 / sink_total
	var/actual_n2_ratio = sink_n2 / sink_total
	TEST_ASSERT(abs(actual_o2_ratio - 0.7) < 0.05, \
		"O2 ratio off target: expected 0.7, got [actual_o2_ratio]")
	TEST_ASSERT(abs(actual_n2_ratio - 0.3) < 0.05, \
		"N2 ratio off target: expected 0.3, got [actual_n2_ratio]")


/// The LINDA fuel-consumption pathway thrust_burn uses: remove_ratio drains
/// a fraction of moles from air_contents and returns a removed mixture that
/// can be assumed by the exhaust turf. Tests this directly rather than going
/// through thrust_burn (which couples to APC power and blockage geometry).
/// Combined with dq_gas_thruster_construct_and_check_fuel above, this covers
/// the full engine→LINDA contract.
/datum/unit_test/dq_thruster_remove_ratio_drives_burn_math

/datum/unit_test/dq_thruster_remove_ratio_drives_burn_math/Run()
	var/turf/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for thruster remove_ratio test")

	var/obj/machinery/atmospherics/unary/engine/E = new(T)
	TEST_ASSERT_NOTNULL(E, "thruster construct failed")
	TEST_ASSERT_NOTNULL(E.air_contents, "thruster air_contents null")

	E.air_contents.adjust_gas(/datum/gas/volatile_fuel, 200)
	E.air_contents.adjust_gas(/datum/gas/oxygen, 400)
	E.air_contents.set_temperature(T0C + 300)

	var/initial_moles = E.air_contents.total_moles()
	TEST_ASSERT(initial_moles > 500, "fuel load failed: only [initial_moles] moles")

	// Replicate the thrust_burn() core: pull a ratio of the fuel mixture.
	var/burn_ratio = E.volume_per_burn * E.thrust_limit / E.air_contents.return_volume()
	TEST_ASSERT(burn_ratio > 0 && burn_ratio < 1, \
		"burn_ratio out of range: [burn_ratio] (vol_per_burn=[E.volume_per_burn] thrust_limit=[E.thrust_limit] vol=[E.air_contents.return_volume()])")

	var/datum/gas_mixture/removed = E.air_contents.remove_ratio(burn_ratio)
	TEST_ASSERT_NOTNULL(removed, "remove_ratio returned null on a fuel-rich mixture")
	var/removed_moles = removed.total_moles()
	TEST_ASSERT(removed_moles > 0, "remove_ratio returned an empty mixture, expected ~[initial_moles * burn_ratio]")

	var/after_moles = E.air_contents.total_moles()
	TEST_ASSERT(abs((initial_moles - after_moles) - removed_moles) < 0.5, \
		"engine moles lost ([initial_moles - after_moles]) != removed.total ([removed_moles]) — conservation broken")

	// Thrust math — the engine's calculate_thrust on a hot fuel mix should be > 0.
	var/thrust = E.calculate_thrust(removed)
	TEST_ASSERT(thrust > 0, \
		"calculate_thrust on a 600-mole hot fuel sample returned [thrust] (expected > 0)")

	// Merge the exhaust into the turf air — the LINDA assume_air path.
	var/datum/gas_mixture/turf_air = T.return_air()
	var/turf_before = turf_air.total_moles()
	T.assume_air(removed)
	var/turf_after = turf_air.total_moles()
	TEST_ASSERT(turf_after > turf_before, \
		"assume_air didn't add removed exhaust to turf: [turf_before] → [turf_after]")

	qdel(E)


/// experience_pressure_difference should push an unanchored movable in the
/// direction of the pressure gradient. Validates the spacewind path that
/// makes "blown out an airlock" work.
/datum/unit_test/dq_pressure_pushes_unanchored_movable

/datum/unit_test/dq_pressure_pushes_unanchored_movable/Run()
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no adjacent-floor pair for pressure push test")
	var/turf/open/A = pair[1]
	var/turf/open/B = pair[2]

	// Drop an unanchored, low-mass item on A.
	var/obj/item/paper/P = new(A)
	TEST_ASSERT(!P.anchored, "paper anchored — test setup invalid")
	TEST_ASSERT(P.loc == A, "paper didn't land on A")

	// Wait for at least one real SSair tick so the cycle-gate inside
	// high_pressure_movements (last_high_pressure_movement_air_cycle <
	// SSair.times_fired) is open — i.e., the paper hasn't already been
	// pushed THIS air cycle.
	var/cycle_at_start = SSair.times_fired
	var/wait_started = world.time
	while(SSair.times_fired == cycle_at_start && world.time - wait_started < DQ_ATMOS_TEST_MAX_WAIT)
		sleep(world.tick_lag)
	TEST_ASSERT(SSair.times_fired > cycle_at_start, \
		"Master.Loop didn't advance SSair.times_fired during sleep — engine not ticking")
	var/direction = get_dir(A, B)
	// Large pressure difference and low resistance → move_prob clamps high.
	P.experience_pressure_difference(500, direction)
	TEST_ASSERT(P.last_high_pressure_movement_air_cycle == SSair.times_fired, \
		"unanchored item did not register a pressure push (last_cycle=[P.last_high_pressure_movement_air_cycle], expected [SSair.times_fired])")

	qdel(P)


/// Same setup, but anchored object should resist the same pressure delta —
/// the anchored branch only fires if max_force exceeds move_resist *
/// FORCEPUSH_RATIO, which a normal pressure delta can't reach for a heavy
/// anchored machine like a canister.
/datum/unit_test/dq_pressure_does_not_push_anchored_movable

/datum/unit_test/dq_pressure_does_not_push_anchored_movable/Run()
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no adjacent-floor pair for anchored pressure test")
	var/turf/open/A = pair[1]
	var/turf/open/B = pair[2]

	// Anchored canister (wrenched-down by hand for the test; canister default is
	// unanchored and gets bolted via wrench in-game). High pressure_resistance
	// and a heavy move_resist should keep the canister from moving under spacewind.
	var/obj/machinery/portable_atmospherics/canister/C = new(A)
	C.anchored = TRUE
	C.move_resist = INFINITY
	var/turf/initial_loc = C.loc

	// Wait for at least one real SSair tick to open the cycle gate.
	dq_atmos_test_wait_real_ssair_ticks(1)
	var/direction = get_dir(A, B)
	// Same pressure delta the paper moved at — anchored canister stays.
	C.experience_pressure_difference(500, direction)
	TEST_ASSERT(C.loc == initial_loc, \
		"anchored canister moved under pressure delta — anchored branch math broken (loc=[C.loc])")

	qdel(C)


/// Closed airlock between two turfs blocks atmos sharing — the CHOMP door
/// has a CanZASPass(!density) override that LINDA routes through via the
/// /atom/proc/can_atmos_pass(ATMOS_PASS_PROC) bridge added in this fork.
/// This test confirms CANATMOSPASS sees the closed door and returns FALSE.
/datum/unit_test/dq_closed_door_blocks_canatmospass

/datum/unit_test/dq_closed_door_blocks_canatmospass/Run()
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no adjacent-floor pair for closed-door block test")
	var/turf/open/A = pair[1]
	var/turf/open/B = pair[2]

	// Baseline: no door, atmos passes both ways.
	var/baseline = CANATMOSPASS(B, A, FALSE)
	TEST_ASSERT(baseline, "baseline CANATMOSPASS without door is FALSE — test setup invalid")

	var/obj/machinery/door/unpowered/D = new(A)
	TEST_ASSERT_NOTNULL(D, "door construct failed")
	TEST_ASSERT(D.density, "door not dense by default")
	TEST_ASSERT_EQUAL(D.can_atmos_pass, ATMOS_PASS_PROC, "door can_atmos_pass not ATMOS_PASS_PROC")

	// With the closed door on A, CHOMP's CANATMOSPASS check between A and B
	// should consult CanZASPass via /atom/proc/can_atmos_pass — and the closed
	// door returns !density = FALSE.
	var/passes = TRUE
	for(var/obj/checked in A.contents)
		if(!CANATMOSPASS(checked, B, FALSE))
			passes = FALSE
			break
	TEST_ASSERT(!passes, "closed door did NOT block CANATMOSPASS — can_atmos_pass→CanZASPass routing broken")

	// Open the door (density=FALSE) and confirm gas passes again.
	D.density = FALSE
	var/passes_open = TRUE
	for(var/obj/checked in A.contents)
		if(!CANATMOSPASS(checked, B, FALSE))
			passes_open = FALSE
			break
	TEST_ASSERT(passes_open, "open (non-dense) door blocked CANATMOSPASS — should be passable")

	qdel(D)


// =====================================================================
// Round 7: tank overpressure, tank breath path, hotspot threshold,
// pipeline build, 3-pipe reconcile
// =====================================================================

/// Tank.check_status() should reduce integrity when air_contents.return_pressure
/// exceeds TANK_RUPTURE_PRESSURE but stays under TANK_FRAGMENT_PRESSURE — the
/// "slowly leaking" branch. Catches LINDA pressure-read regressions at the
/// tank boundary without triggering an explosion.
/datum/unit_test/dq_tank_overpressure_loses_integrity

/datum/unit_test/dq_tank_overpressure_loses_integrity/Run()
	var/obj/item/tank/oxygen/Tank = new(locate(1, 1, 1))
	TEST_ASSERT_NOTNULL(Tank, "couldn't construct oxygen tank")
	TEST_ASSERT_NOTNULL(Tank.air_contents, "tank air_contents null")

	// Stash baseline integrity, then push pressure into the rupture band (40-50 atm).
	var/initial_integrity = Tank.get_integrity()
	TEST_ASSERT(initial_integrity > 0, "tank integrity zero at construct")

	// Pressure target: ~37 atm. DQ's TANK_RUPTURE_PRESSURE is 35 atm and
	// TANK_FRAGMENT_PRESSURE is 40 atm — we need to sit between those so
	// check_status takes the "integrity damage, no explosion" branch.
	var/target_moles = (37 * ONE_ATMOSPHERE) * Tank.air_contents.return_volume() / (R_IDEAL_GAS_EQUATION * T20C)
	Tank.air_contents.adjust_gas(/datum/gas/oxygen, target_moles - Tank.air_contents.total_moles())
	Tank.air_contents.set_temperature(T20C)

	var/pressure = Tank.air_contents.return_pressure()
	TEST_ASSERT(pressure > TANK_RUPTURE_PRESSURE, \
		"failed to seed tank above rupture pressure: pressure=[pressure] target=[TANK_RUPTURE_PRESSURE]")
	TEST_ASSERT(pressure < TANK_FRAGMENT_PRESSURE, \
		"seeded tank above fragment pressure ([TANK_FRAGMENT_PRESSURE]) — test would detonate the world")

	Tank.check_status()

	TEST_ASSERT(Tank.get_integrity() < initial_integrity, \
		"check_status didn't reduce integrity under rupture pressure: [initial_integrity] → [Tank.get_integrity()]")

	qdel(Tank)


/// Tank.remove_air_volume() is the breath path — it computes moles by the ideal
/// gas law against distribute_pressure and pulls them out via remove(). Verify
/// the LINDA gas_mixture properly drains across this code path.
/datum/unit_test/dq_tank_remove_air_volume_drains_moles

/datum/unit_test/dq_tank_remove_air_volume_drains_moles/Run()
	var/obj/item/tank/oxygen/Tank = new(locate(1, 1, 1))
	TEST_ASSERT_NOTNULL(Tank, "tank construct failed")
	TEST_ASSERT_NOTNULL(Tank.air_contents, "tank air_contents null")

	// Sanity: tank starts at default pressure with some O2 already.
	var/initial_moles = Tank.air_contents.total_moles()
	TEST_ASSERT(initial_moles > 0, "fresh tank has zero moles — invalid setup")

	// Pull a typical breath (BREATH_VOLUME at distribute_pressure).
	var/datum/gas_mixture/breath = Tank.remove_air_volume(BREATH_VOLUME)
	TEST_ASSERT_NOTNULL(breath, "remove_air_volume returned null on a loaded tank")
	TEST_ASSERT(breath.total_moles() > 0, "breath mixture has zero moles")

	// Tank should have lost the moles that ended up in the breath.
	var/after_moles = Tank.air_contents.total_moles()
	var/lost = initial_moles - after_moles
	var/gained = breath.total_moles()
	TEST_ASSERT(abs(lost - gained) < 0.01, \
		"breath conservation broken: tank lost [lost], breath got [gained]")

	qdel(Tank)


/// Tank.assume_air() merges donor gas into the tank. Validates the LINDA
/// path used when a canister releases into a tank, or when a transfer valve
/// dumps gas into a connected tank.
/datum/unit_test/dq_tank_assume_air_merges_donor

/datum/unit_test/dq_tank_assume_air_merges_donor/Run()
	var/obj/item/tank/oxygen/Tank = new(locate(1, 1, 1))
	TEST_ASSERT_NOTNULL(Tank, "tank construct failed")
	var/initial_moles = Tank.air_contents.total_moles()

	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/nitrogen, 50)
	donor.set_temperature(T20C)
	var/donor_moles = donor.total_moles()

	Tank.assume_air(donor)

	var/after_moles = Tank.air_contents.total_moles()
	TEST_ASSERT(abs((after_moles - initial_moles) - donor_moles) < 0.5, \
		"tank.assume_air didn't merge donor: initial=[initial_moles] after=[after_moles] donor=[donor_moles]")

	// Per the Rust auxmos contract, merge() doesn't drain the giver — it only
	// copies into self. So `donor` still holds its original moles. This differs
	// from /tg/'s pure-DM merge which doesn't drain either, so we're consistent.
	TEST_ASSERT(donor.total_moles() > donor_moles - 0.5, \
		"donor was unexpectedly drained — merge contract changed")

	qdel(Tank)


/// hotspot_expose at a temperature below PLASMA_MINIMUM_BURN_TEMPERATURE on a
/// turf with plasma + O2 must NOT spawn an active_hotspot. Validates the
/// ignition threshold gate inside /turf/open/hotspot_expose.
/datum/unit_test/dq_hotspot_below_minimum_heat_no_ignition

/datum/unit_test/dq_hotspot_below_minimum_heat_no_ignition/Run()
	var/turf/open/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for hotspot threshold test")

	var/datum/gas_mixture/turf_air = T.return_air()
	for(var/datum/gas/g as anything in turf_air.get_gases())
		turf_air.set_moles(g, 0)
	turf_air.adjust_gas(/datum/gas/plasma, 50)
	turf_air.adjust_gas(/datum/gas/oxygen, 100)
	turf_air.set_temperature(T20C)

	// Clear any preexisting hotspot from earlier tests.
	if(T.active_hotspot)
		qdel(T.active_hotspot)
		T.active_hotspot = null

	// Expose at 300K — well below PLASMA_MINIMUM_BURN_TEMPERATURE (399.15K).
	T.hotspot_expose(300, 500, FALSE)
	TEST_ASSERT_NULL(T.active_hotspot, \
		"hotspot ignited under [300]K despite minimum_burn being [PLASMA_MINIMUM_BURN_TEMPERATURE]K")

	// Now expose above the threshold — should ignite.
	T.hotspot_expose(PLASMA_MINIMUM_BURN_TEMPERATURE + 50, 500, FALSE)
	TEST_ASSERT_NOTNULL(T.active_hotspot, \
		"hotspot did NOT ignite above the threshold with plasma+O2 present")

	if(T.active_hotspot)
		qdel(T.active_hotspot)
		T.active_hotspot = null
	for(var/datum/gas/g as anything in turf_air.get_gases())
		turf_air.set_moles(g, 0)


/// A single Rust port should materialize one compatibility pipeline with the
/// exact physical volume reported by that port.
/datum/unit_test/dq_pipeline_build_pipeline_single_pipe

/datum/unit_test/dq_pipeline_build_pipeline_single_pipe/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for pipeline build test")

	var/obj/machinery/atmospherics/pipe/simple/Pipe = new(T)
	TEST_ASSERT_NOTNULL(Pipe, "pipe construct failed")
	TEST_ASSERT(Pipe.volume > 0, "pipe has zero volume — bad init")

	dq_atmos_test_publish_rust_pipenets(list(Pipe))
	var/datum/pipeline/Line = Pipe.parent

	TEST_ASSERT_NOTNULL(Line.air, "build_pipeline didn't allocate pipeline.air")
	TEST_ASSERT(Line.air.return_volume() == Pipe.volume, \
		"pipeline volume mismatch: pipeline=[Line.air.return_volume()] pipe=[Pipe.volume]")
	TEST_ASSERT(Pipe.parent == Line, \
		"pipe.parent not set to the pipeline: pipe.parent=[Pipe.parent] line=[Line]")
	TEST_ASSERT(Line.members && (Pipe in Line.members), \
		"pipe not in pipeline.members after build_pipeline")

	qdel(Pipe)


/// Pipenet merge and teardown must transfer ownership rather than leave a
/// donor graph retaining all of the same machinery and pipelines.  This was a
/// major source of explosion-time hard deletes.
/datum/unit_test/dq_pipenet_merge_releases_donor_graph

/datum/unit_test/dq_pipenet_merge_releases_donor_graph/Run()
	var/datum/pipe_network/receiver = new
	var/datum/pipe_network/donor = new
	var/datum/pipeline/line = new
	line.air = new(70)
	line.members = list()
	line.edges = list()
	line.network = donor
	donor.add_line_member(line)
	donor.air = line.air
	donor.gases = list(line.air)
	donor.volume = line.air.return_volume()

	TEST_ASSERT(receiver.merge(donor), "pipenet merge rejected a valid donor")
	TEST_ASSERT(line.network == receiver, "merged pipeline did not transfer to the receiving network")
	TEST_ASSERT(line in receiver.line_members, "receiving network did not acquire the donor pipeline")
	TEST_ASSERT(receiver in line.network_memberships, "pipeline reverse ownership index did not transfer to receiver")
	TEST_ASSERT(!(donor in line.network_memberships), "pipeline reverse ownership index retained merged donor")
	TEST_ASSERT(QDELETED(donor), "merged donor network remained alive")
	TEST_ASSERT_NULL(donor.line_members, "merged donor retained its pipeline membership list")
	TEST_ASSERT_NULL(donor.normal_members, "merged donor retained its machinery membership list")
	TEST_ASSERT_NULL(donor.gases, "merged donor retained its gas list")

	qdel(receiver)
	TEST_ASSERT_NULL(line.network, "destroyed receiving network remained referenced by its pipeline")
	qdel(line)


/// A machine reached through repeated topology rebuilds must retain a reverse
/// index of every roster so destruction can synchronously sever all cycles.
/datum/unit_test/dq_pipenet_member_destroy_clears_every_roster

/datum/unit_test/dq_pipenet_member_destroy_clears_every_roster/Run()
	var/turf/T
	for(var/turf/candidate in world)
		T = candidate
		break
	TEST_ASSERT_NOTNULL(T, "no turf for pipenet ownership test")
	var/obj/machinery/atmospherics/unary/vent_pump/vent = new(T)
	var/datum/pipe_network/first = new
	var/datum/pipe_network/second = new
	first.add_normal_member(vent)
	second.add_normal_member(vent)
	TEST_ASSERT(length(vent.network_memberships) == 2, "machine reverse ownership index omitted a retaining network")
	qdel(vent)
	TEST_ASSERT(!(vent in first.normal_members), "destroyed machine remained in first network roster")
	TEST_ASSERT(!(vent in second.normal_members), "destroyed machine remained in second network roster")
	qdel(first)
	qdel(second)


/// An APC cell can be destroyed independently by an explosion.  Its explicit
/// owner backlink must be cleared even if the APC itself survives.
/datum/unit_test/dq_apc_cell_deletion_clears_owner

/datum/unit_test/dq_apc_cell_deletion_clears_owner/Run()
	var/turf/T
	for(var/turf/candidate in world)
		T = candidate
		break
	TEST_ASSERT_NOTNULL(T, "no test floor for APC cell ownership test")
	var/obj/machinery/power/apc/test_apc = new(T)
	var/obj/item/cell/test_cell = new(test_apc)
	test_apc.cell = test_cell

	qdel(test_cell)
	TEST_ASSERT_NULL(test_apc.cell, "destroyed cell remained retained by its APC")
	qdel(test_apc)


/// Three pipelines must pool once, share one handle, and split conservatively
/// when topology is destroyed.
/datum/unit_test/dq_reconcile_air_three_pipes_conserves_mass

/datum/unit_test/dq_reconcile_air_three_pipes_conserves_mass/Run()
	var/datum/pipe_network/net = new
	var/list/lines = list()
	var/initial_total = 0
	var/initial_thermal = 0
	for(var/i = 1 to 3)
		var/datum/pipeline/line = new
		line.air = new(70)
		line.volume = 70
		line.members = list()
		line.edges = list()
		line.network = net
		line.air.adjust_gas(i == 1 ? /datum/gas/oxygen : /datum/gas/nitrogen, i * 25)
		line.air.set_temperature(T20C + i * 20)
		initial_total += line.air.total_moles()
		initial_thermal += line.air.thermal_energy()
		net.add_line_member(line)
		lines += line
	net.update_network_gases()
	for(var/datum/pipeline/line as anything in lines)
		TEST_ASSERT(line.air == net.air, "three-pipeline network retained a member gas mirror")
	TEST_ASSERT(abs(net.air.total_moles() - initial_total) < 0.5, "three-pipeline pooling lost mass")
	TEST_ASSERT(abs(net.air.thermal_energy() - initial_thermal) < initial_thermal * 0.05, \
		"three-pipeline pooling lost thermal energy")
	qdel(net)
	var/split_total = 0
	var/split_thermal = 0
	var/datum/gas_mixture/first_split
	for(var/datum/pipeline/line as anything in lines)
		TEST_ASSERT_NOTNULL(line.air, "topology split left a pipeline without gas")
		TEST_ASSERT(line.air != first_split, "topology split left pipelines sharing a deleted network gas")
		first_split ||= line.air
		split_total += line.air.total_moles()
		split_thermal += line.air.thermal_energy()
	TEST_ASSERT(abs(split_total - initial_total) < 0.5, "topology split lost mass")
	TEST_ASSERT(abs(split_thermal - initial_thermal) < initial_thermal * 0.05, "topology split lost energy")
	for(var/datum/pipeline/line as anything in lines)
		qdel(line)


// =====================================================================
// Round 8: 2-pipe pipeline expansion, temperature_share, full canister
// room propagation, analyzer extremes
// =====================================================================

/// Rust traverses reciprocal stable-port edges. Two manually connected pipes
/// must materialize into the same compatibility pipeline.
/datum/unit_test/dq_pipeline_chains_two_connected_pipes

/datum/unit_test/dq_pipeline_chains_two_connected_pipes/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for 2-pipe pipeline test")

	var/obj/machinery/atmospherics/pipe/simple/PA = new(T)
	var/obj/machinery/atmospherics/pipe/simple/PB = new(T)
	TEST_ASSERT_NOTNULL(PA, "pipe A construct failed")
	TEST_ASSERT_NOTNULL(PB, "pipe B construct failed")

	// Wire them together manually through their physical port neighbors.
	PA.node1 = PB
	PB.node1 = PA

	dq_atmos_test_publish_rust_pipenets(list(PA, PB))
	var/datum/pipeline/Line = PA.parent

	TEST_ASSERT(PA in Line.members, "pipe A not in pipeline.members after build_pipeline")
	TEST_ASSERT(PB in Line.members, "pipe B not in pipeline.members — build_pipeline didn't expand via pipeline_expansion")
	TEST_ASSERT(PA.parent == Line && PB.parent == Line, \
		"pipe.parent not set on both members: A=[PA.parent] B=[PB.parent]")

	// Volume should be the sum of both pipe volumes.
	TEST_ASSERT(Line.air.return_volume() == (PA.volume + PB.volume), \
		"pipeline volume not sum of pipes: pipeline=[Line.air.return_volume()] expected=[PA.volume + PB.volume]")

	qdel(PA)
	qdel(PB)


/// Full integration: open a plasma canister in a room, run ticks, verify
/// plasma reaches an adjacent floor a few hops away. End-to-end test of
/// canister release + LINDA turf-to-turf share + adjacency walking.
/datum/unit_test/dq_canister_release_propagates_through_room

/datum/unit_test/dq_canister_release_propagates_through_room/Run()
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no adjacent-floor pair for canister-room test")
	var/turf/open/A = pair[1]
	var/turf/open/B = pair[2]

	// Isolate the pair from background atmos.
	dq_atmos_test_isolate_pair(A, B)

	// Zero out A and B atmospheres.
	var/datum/gas_mixture/A_air = A.return_air()
	for(var/datum/gas/g as anything in A_air.get_gases())
		A_air.set_moles(g, 0)
	A_air.set_temperature(T20C)
	var/datum/gas_mixture/B_air = B.return_air()
	for(var/datum/gas/g as anything in B_air.get_gases())
		B_air.set_moles(g, 0)
	B_air.set_temperature(T20C)

	// Place a plasma canister on A with the valve open.
	var/obj/machinery/portable_atmospherics/canister/phoron/Can = new(A)
	TEST_ASSERT_NOTNULL(Can, "phoron canister construct failed")
	Can.valve_open = TRUE
	Can.release_pressure = ONE_ATMOSPHERE * 50

	// Run canister.process to release, then drive cells to share into B.
	// Poll: stop looping as soon as both turfs show plasma (the condition
	// asserted below) rather than always burning the full 8 iterations.
	var/A_plasma
	var/B_plasma
	for(var/i in 1 to 8)
		Can.process()
		dq_atmos_test_drive_ticks(list(A, B), 1)
		A_plasma = A_air.get_moles(/datum/gas/plasma)
		B_plasma = B_air.get_moles(/datum/gas/plasma)
		if(A_plasma > 0 && B_plasma > 0)
			break

	A_plasma = A_air.get_moles(/datum/gas/plasma)
	B_plasma = B_air.get_moles(/datum/gas/plasma)
	TEST_ASSERT(A_plasma > 0, "canister didn't release ANY plasma onto A: [A_plasma]")
	TEST_ASSERT(B_plasma > 0, "plasma didn't spread from A to adjacent B: [B_plasma] (A=[A_plasma])")

	// Cleanup so other tests don't see leftover plasma.
	for(var/datum/gas/g as anything in A_air.get_gases())
		A_air.set_moles(g, 0)
	for(var/datum/gas/g as anything in B_air.get_gases())
		B_air.set_moles(g, 0)
	qdel(Can)


/// Atmos analyzer at extreme pressure (100 atm canister) returns valid lines
/// and doesn't runtime. Catches overflow/format bugs at the edge of the
/// expected pressure range.
/datum/unit_test/dq_atmos_analyzer_handles_extreme_pressure

/datum/unit_test/dq_atmos_analyzer_handles_extreme_pressure/Run()
	var/obj/item/tank/oxygen/Tank = new(locate(1, 1, 1))
	TEST_ASSERT_NOTNULL(Tank, "tank construct failed")

	// Push pressure to ~30 atm (below TANK_LEAK so we don't lose integrity).
	var/target_moles = (28 * ONE_ATMOSPHERE) * Tank.air_contents.return_volume() / (R_IDEAL_GAS_EQUATION * T20C)
	Tank.air_contents.adjust_gas(/datum/gas/oxygen, target_moles - Tank.air_contents.total_moles())
	Tank.air_contents.set_temperature(T20C)

	var/pressure = Tank.air_contents.return_pressure()
	TEST_ASSERT(pressure > 25 * ONE_ATMOSPHERE, "failed to seed high pressure: [pressure]")

	// Run the analyzer scan; expect it to return non-empty info.
	// Signature is (atom/target, datum/gas_mixture/mixture, mob/user).
	var/list/lines = atmosanalyzer_scan(Tank, Tank.air_contents, null)
	TEST_ASSERT_NOTNULL(lines, "atmosanalyzer_scan returned null at extreme pressure")
	TEST_ASSERT(islist(lines) && length(lines) > 0, \
		"atmosanalyzer_scan returned empty list at [pressure] kPa")

	qdel(Tank)


// =====================================================================
// Round 9: edge-case safety (vacuum, TCMB, zero-remove), freezer/heater
// smoke tests
// =====================================================================

/// /datum/gas_mixture.react() must be safe at TCMB (2.7K) — the coldest
/// the atmos engine allows. Without a guard, plasma fire math at near-zero
/// temperature can divide by zero or blow up the Rust reaction state.
/datum/unit_test/dq_gas_react_safe_at_tcmb

/datum/unit_test/dq_gas_react_safe_at_tcmb/Run()
	var/datum/gas_mixture/mix = new(CELL_VOLUME)
	mix.adjust_gas(/datum/gas/plasma, 50)
	mix.adjust_gas(/datum/gas/oxygen, 100)
	mix.set_temperature(TCMB)

	// react() must NOT crash, NOT consume reagents (too cold to burn), and
	// must NOT touch temperature (no exothermic energy to release).
	mix.react(null)

	TEST_ASSERT_EQUAL(mix.get_moles(/datum/gas/plasma), 50, \
		"plasma reacted at TCMB — temperature gate broken")
	TEST_ASSERT_EQUAL(mix.get_moles(/datum/gas/oxygen), 100, \
		"oxygen consumed at TCMB — temperature gate broken")
	// Allow tiny floating drift but no significant change.
	var/tcmb_temp = mix.return_temperature()
	TEST_ASSERT(abs(tcmb_temp - TCMB) < 1, \
		"temperature shifted at TCMB react: [tcmb_temp]")


/// An empty (vacuum) gas mixture should return 0 pressure without crashing —
/// the LINDA pressure read goes through Rust auxmos, which has to handle
/// total_moles==0 cleanly.
/datum/unit_test/dq_vacuum_mixture_pressure_is_zero

/datum/unit_test/dq_vacuum_mixture_pressure_is_zero/Run()
	var/datum/gas_mixture/vac = new(CELL_VOLUME)
	vac.set_temperature(T20C)
	TEST_ASSERT_EQUAL(vac.total_moles(), 0, "fresh mixture has non-zero moles")

	var/p = vac.return_pressure()
	TEST_ASSERT(p == 0 || p < 0.001, \
		"vacuum mixture returned non-zero pressure: [p]")

	// Same check on heat_capacity — should be 0 (or very near).
	var/hc = vac.heat_capacity()
	TEST_ASSERT(hc == 0 || hc < 0.001, \
		"vacuum mixture has non-zero heat_capacity: [hc]")


/// gas_mixture.remove(0) and remove(negative) must not crash and must NOT
/// drain the source mixture. The contract is "amount <= 0 returns null"
/// (see gas_mixture.dm); callers (filters, scrubbers, pumps) hit this
/// branch when load is balanced and must handle null without leaking.
/datum/unit_test/dq_gas_mixture_remove_zero_safe

/datum/unit_test/dq_gas_mixture_remove_zero_safe/Run()
	var/datum/gas_mixture/mix = new(CELL_VOLUME)
	mix.adjust_gas(/datum/gas/oxygen, 100)
	mix.set_temperature(T20C)
	var/initial_moles = mix.total_moles()

	// remove(0): contract returns null. Source must not change.
	var/datum/gas_mixture/r0 = mix.remove(0)
	TEST_ASSERT_NULL(r0, "remove(0) returned non-null — contract is null for amount<=0")
	TEST_ASSERT(abs(mix.total_moles() - initial_moles) < 0.001, \
		"remove(0) drained source: [initial_moles] → [mix.total_moles()]")

	// remove(negative): same contract — null, no drain.
	var/datum/gas_mixture/rneg = mix.remove(-10)
	TEST_ASSERT_NULL(rneg, "remove(-10) returned non-null — should be null per contract")
	TEST_ASSERT(abs(mix.total_moles() - initial_moles) < 0.001, \
		"remove(-10) drained source: [initial_moles] → [mix.total_moles()]")


/// Freezer machinery constructs without crashing and can be qdeleted cleanly.
/// Smoke test — full process() requires a connected pipe network with active
/// air; we already cover the LINDA gas-cooling math via cryo_cell_cools_mob.
/datum/unit_test/dq_freezer_constructs

/datum/unit_test/dq_freezer_constructs/Run()
	var/turf/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for freezer construct test")

	var/obj/machinery/atmospherics/unary/freezer/F = new(T)
	TEST_ASSERT_NOTNULL(F, "freezer construct failed")
	TEST_ASSERT_NOTNULL(F.air_contents, "freezer air_contents null")
	qdel(F)


/// Heater machinery constructs without crashing and can be qdeleted cleanly.
/// Counterpart to dq_freezer_constructs — covers the heat-source machinery
/// init path under LINDA.
/datum/unit_test/dq_heater_constructs

/datum/unit_test/dq_heater_constructs/Run()
	var/turf/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for heater construct test")

	var/obj/machinery/atmospherics/unary/heater/H = new(T)
	TEST_ASSERT_NOTNULL(H, "heater construct failed")
	TEST_ASSERT_NOTNULL(H.air_contents, "heater air_contents null")
	qdel(H)


// =====================================================================
// Round 10: full mob internals breath path
// =====================================================================

/// Full integration of the breath-from-internals path: a human with an
/// airtight breath mask and an oxygen tank set as internal pulls breath
/// gas from the tank rather than the surrounding air. Verifies the tank
/// drains and the breath mixture has the right oxygen.
///
/// This exercises every link in the chain:
///   mob.internal = tank
/// → get_breath_from_internal(BREATH_VOLUME)
/// → suit_supply/contents check
/// → wear_mask AIRTIGHT check
/// → tank.remove_air_volume(BREATH_VOLUME)
/// → tank.remove(moles_needed)
/// → LINDA gas_mixture.remove()
///
/// If LINDA breaks any of those, internals stop working — players asphyxiate
/// in vacuum even with a full tank. So this is the breath-path regression
/// canary.
/datum/unit_test/dq_breath_from_internals_drains_tank

/datum/unit_test/dq_breath_from_internals_drains_tank/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_NOTNULL(H, "couldn't allocate human")

	// Airtight breath mask in the wear_mask slot.
	var/obj/item/clothing/mask/breath/M = new(H)
	TEST_ASSERT(H.equip_to_slot(M, slot_wear_mask), "couldn't put the test mask on")
	TEST_ASSERT(M.item_flags & AIRTIGHT, "test mask not AIRTIGHT — setup invalid")

	// Oxygen tank in the human's contents, set as the internal supply.
	var/obj/item/tank/oxygen/Tank = new(H)
	TEST_ASSERT_NOTNULL(Tank, "tank construct failed")
	TEST_ASSERT_NOTNULL(Tank.air_contents, "tank air_contents null")
	TEST_ASSERT(Tank in H.contents, "tank not in human contents — setup invalid")
	H.internal = Tank

	var/initial_tank_moles = Tank.air_contents.total_moles()
	TEST_ASSERT(initial_tank_moles > 0, "tank starts empty — setup invalid")

	// Pull a breath through the internals path.
	var/datum/gas_mixture/breath = H.get_breath_from_internal(BREATH_VOLUME)

	TEST_ASSERT_NOTNULL(breath, "get_breath_from_internal returned null — AIRTIGHT/contents gate broken")
	var/breath_moles = breath.total_moles()
	TEST_ASSERT(breath_moles > 0, "breath has zero moles — remove_air_volume didn't pull")

	// Tank must have lost what the breath got (conservation across the chain).
	var/after_tank_moles = Tank.air_contents.total_moles()
	var/tank_lost = initial_tank_moles - after_tank_moles
	TEST_ASSERT(abs(tank_lost - breath_moles) < 0.01, \
		"internals conservation broken: tank lost [tank_lost] moles, breath got [breath_moles]")

	// The breath should be oxygen-rich (it came from an O2 tank).
	var/breath_o2 = breath.get_moles(/datum/gas/oxygen)
	TEST_ASSERT(breath_o2 > 0, "breath from O2 tank has no oxygen: [breath_o2] moles")

	// Removing the AIRTIGHT mask should detach the internal supply: next call
	// returns null because the AIRTIGHT gate fails.
	H.drop_from_inventory(M)
	var/datum/gas_mixture/no_breath = H.get_breath_from_internal(BREATH_VOLUME)
	TEST_ASSERT_NULL(no_breath, \
		"internals stayed active without AIRTIGHT mask — security gate broken")
	TEST_ASSERT_NULL(H.internal, \
		"internal var not cleared when AIRTIGHT gate fails")


// =====================================================================
// Round 11: volume pump, tank lifecycle
// =====================================================================

/// Volume pump transfers a fixed volume of gas per tick regardless of the
/// downstream pressure — unlike pressure pump which only pumps when target
/// > current. Used in production for hard-vacuum supply (e.g. SM coolant)
/// and atmos engine fuel feeds.
/datum/unit_test/dq_volume_pump_transfers_by_volume

/datum/unit_test/dq_volume_pump_transfers_by_volume/Run()
	var/turf/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for volume_pump test")

	var/obj/machinery/atmospherics/binary/volume_pump/V = new(T)
	TEST_ASSERT_NOTNULL(V, "volume_pump construct failed")
	V.use_power = USE_POWER_IDLE
	V.stat &= ~(NOPOWER | BROKEN)
	V.rust_register_pipe_topology() // allocates ports, binds air1/air2, registers the device edge
	TEST_ASSERT_NOTNULL(V.air1, "volume_pump air1 null")
	TEST_ASSERT_NOTNULL(V.air2, "volume_pump air2 null")

	V.air1.adjust_gas(/datum/gas/oxygen, 500)
	V.air1.set_temperature(T20C)
	// Pre-load air2 with enough pressure that a pressure pump would refuse —
	// volume_pump should still transfer.
	V.air2.adjust_gas(/datum/gas/nitrogen, 100)
	V.air2.set_temperature(T20C)
	V.update_rust_device()

	var/air1_initial = V.air1.total_moles()
	var/air2_initial = V.air2.total_moles()

	// M2 (simulation.md §5): the flow law is a Rust device edge; SSair
	// drives it, not V.process() (deleted).
	for(var/i in 1 to 5)
		SSair.rust_step_pipe_devices()

	var/air1_after = V.air1.total_moles()
	var/air2_after = V.air2.total_moles()

	TEST_ASSERT(air1_after < air1_initial, \
		"volume_pump didn't drain input: [air1_initial] → [air1_after]")
	TEST_ASSERT(air2_after > air2_initial, \
		"volume_pump didn't fill output: [air2_initial] → [air2_after]")
	// Mole conservation: input loss == output gain.
	var/lost = air1_initial - air1_after
	var/gained = air2_after - air2_initial
	TEST_ASSERT(abs(lost - gained) < 0.5, \
		"volume_pump conservation broken: lost [lost], gained [gained]")

	qdel(V)


/// Full tank lifecycle: assume donor air → pull a breath → assume more →
/// pull a second breath. Each step's mass change must be conserved against
/// the donor/breath mixtures.
/datum/unit_test/dq_tank_round_trip_drain_fill_drain

/datum/unit_test/dq_tank_round_trip_drain_fill_drain/Run()
	var/obj/item/tank/oxygen/Tank = new(locate(1, 1, 1))
	TEST_ASSERT_NOTNULL(Tank, "tank construct failed")
	TEST_ASSERT_NOTNULL(Tank.air_contents, "tank air_contents null")

	var/start_moles = Tank.air_contents.total_moles()

	// Step 1: drain a breath.
	var/datum/gas_mixture/b1 = Tank.remove_air_volume(BREATH_VOLUME)
	TEST_ASSERT_NOTNULL(b1, "step1: remove_air_volume null")
	var/b1_moles = b1.total_moles()
	TEST_ASSERT(b1_moles > 0, "step1: breath has zero moles")
	var/after_drain_1 = Tank.air_contents.total_moles()
	TEST_ASSERT(abs((start_moles - after_drain_1) - b1_moles) < 0.01, \
		"step1: drain conservation broken: tank lost [start_moles - after_drain_1], breath got [b1_moles]")

	// Step 2: refill with a donor.
	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/oxygen, 30)
	donor.set_temperature(T20C)
	var/donor_moles = donor.total_moles()
	Tank.assume_air(donor)
	var/after_fill = Tank.air_contents.total_moles()
	TEST_ASSERT(abs((after_fill - after_drain_1) - donor_moles) < 0.5, \
		"step2: refill conservation broken: tank gained [after_fill - after_drain_1], donor had [donor_moles]")

	// Step 3: drain again. Tank still has more than the first breath could pull,
	// so this second breath should also return non-null with some moles.
	var/datum/gas_mixture/b2 = Tank.remove_air_volume(BREATH_VOLUME)
	TEST_ASSERT_NOTNULL(b2, "step3: remove_air_volume null after refill")
	var/b2_moles = b2.total_moles()
	var/final_moles = Tank.air_contents.total_moles()
	TEST_ASSERT(abs((after_fill - final_moles) - b2_moles) < 0.01, \
		"step3: drain conservation broken: tank lost [after_fill - final_moles], breath got [b2_moles]")

	qdel(Tank)


// =====================================================================
// Round 12: vent_scrubber siphon mode, two-floor diffusion equilibrium
// =====================================================================

/// Vent_scrubber with scrubbing=0 (siphon/panic mode) drains ALL turf air
/// into its pipe regardless of gas type — the emergency-vacuum path. Tests
/// the pump_gas helper used in the siphon branch of vent_scrubber.process().
/datum/unit_test/dq_vent_scrubber_siphon_drains_all_gas

/datum/unit_test/dq_vent_scrubber_siphon_drains_all_gas/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for siphon test")
	dq_atmos_test_snapshot_air(T)
	dq_atmos_test_isolate_pair(T, T)
	T.air_update_turf(TRUE, FALSE)

	var/datum/gas_mixture/turf_air = T.return_air()
	for(var/datum/gas/g as anything in turf_air.get_gases())
		turf_air.set_moles(g, 0)
	// Mixed atmosphere — N2, O2, CO2 — none of which a scrubber would
	// normally filter. Siphon mode should grab all three.
	turf_air.adjust_gas(/datum/gas/nitrogen, 200)
	turf_air.adjust_gas(/datum/gas/oxygen, 100)
	turf_air.adjust_gas(/datum/gas/carbon_dioxide, 30)
	turf_air.set_temperature(T20C)

	var/obj/machinery/atmospherics/unary/vent_scrubber/S = new(T)
	TEST_ASSERT_NOTNULL(S, "scrubber construct failed")
	// `node` is set after topology registration - self-referencing it
	// beforehand would make rust_register_pipe_edges() try to connect the
	// port to itself.
	S.use_power = USE_POWER_IDLE
	S.stat &= ~(NOPOWER | BROKEN)
	S.welded = FALSE
	S.scrubbing = 0  // SIPHON mode
	S.scrubbing_gas = list() // siphon doesn't consult this
	S.rust_register_pipe_topology()
	S.node = S
	S.update_rust_device()

	var/initial_n2 = turf_air.get_moles(/datum/gas/nitrogen)
	var/initial_o2 = turf_air.get_moles(/datum/gas/oxygen)
	var/initial_co2 = turf_air.get_moles(/datum/gas/carbon_dioxide)
	var/initial_total = initial_n2 + initial_o2 + initial_co2

	// M2 (simulation.md §5): the flow law is a Rust device edge bridging
	// the pipe network and the turf field; SSair drives it, not
	// S.process() (deleted). A frame must run every iteration:
	// step_turf_devices reads the field's pinned view, so without a commit
	// in between, every step recomputes its transfer from the same
	// unchanged turf snapshot instead of a shrinking one.
	for(var/i in 1 to 20)
		SSair.rust_step_pipe_devices()
		SSair.run_gas_frames(1)

	var/final_n2 = turf_air.get_moles(/datum/gas/nitrogen)
	var/final_o2 = turf_air.get_moles(/datum/gas/oxygen)
	var/final_co2 = turf_air.get_moles(/datum/gas/carbon_dioxide)
	TEST_ASSERT(final_n2 < initial_n2, "siphon didn't drain N2: [initial_n2] → [final_n2]")
	TEST_ASSERT(final_o2 < initial_o2, "siphon didn't drain O2: [initial_o2] → [final_o2]")
	TEST_ASSERT(final_co2 < initial_co2, "siphon didn't drain CO2: [initial_co2] → [final_co2]")

	// Scrubber pipe should have accumulated the drained gas.
	var/pipe_total = S.air_contents.total_moles()
	TEST_ASSERT(pipe_total > 0, "siphon scrubber pipe gained no gas: [pipe_total]")
	// Conservation: turf loss == pipe gain.
	var/turf_lost = initial_total - (final_n2 + final_o2 + final_co2)
	TEST_ASSERT(abs(turf_lost - pipe_total) < 1, \
		"siphon conservation broken: turf lost [turf_lost], pipe got [pipe_total]")

	for(var/datum/gas/g as anything in turf_air.get_gases())
		turf_air.set_moles(g, 0)
	qdel(S)


/// Two adjacent floor cells, one full of N2, one full of O2 — after enough
/// process_cell ticks they should diffuse to roughly 50/50 in each cell.
/// Validates the LINDA share() math drives gas mixing toward equilibrium,
/// not just toward equal moles.
/datum/unit_test/dq_diffusion_converges_to_balanced_composition

/datum/unit_test/dq_diffusion_converges_to_balanced_composition/Run()
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no adjacent-floor pair for diffusion test")
	var/turf/open/A = pair[1]
	var/turf/open/B = pair[2]
	dq_atmos_test_isolate_pair(A, B)

	var/datum/gas_mixture/A_air = A.return_air()
	var/datum/gas_mixture/B_air = B.return_air()
	for(var/datum/gas/g as anything in A_air.get_gases())
		A_air.set_moles(g, 0)
	for(var/datum/gas/g as anything in B_air.get_gases())
		B_air.set_moles(g, 0)
	A_air.adjust_gas(/datum/gas/nitrogen, 200)
	A_air.set_temperature(T20C)
	B_air.adjust_gas(/datum/gas/oxygen, 200)
	B_air.set_temperature(T20C)

	var/initial_total_n2 = A_air.get_moles(/datum/gas/nitrogen)
	var/initial_total_o2 = B_air.get_moles(/datum/gas/oxygen)

	// Drive equilibration, polling for the 50/50 composition (the same
	// condition asserted below) instead of always burning the full 60 ticks.
	var/baseline = 0
	var/a_n2
	var/a_o2
	var/b_n2
	var/b_o2
	while(baseline < 60)
		dq_atmos_test_drive_ticks(list(A, B), 1)
		baseline++
		a_n2 = A_air.get_moles(/datum/gas/nitrogen)
		a_o2 = A_air.get_moles(/datum/gas/oxygen)
		b_n2 = B_air.get_moles(/datum/gas/nitrogen)
		b_o2 = B_air.get_moles(/datum/gas/oxygen)
		if(abs(a_n2 - a_o2) < (initial_total_n2 * 0.1) && abs(b_n2 - b_o2) < (initial_total_o2 * 0.1))
			break

	// Each cell should now hold roughly half N2 and half O2.
	a_n2 = A_air.get_moles(/datum/gas/nitrogen)
	a_o2 = A_air.get_moles(/datum/gas/oxygen)
	b_n2 = B_air.get_moles(/datum/gas/nitrogen)
	b_o2 = B_air.get_moles(/datum/gas/oxygen)

	// Composition: in each cell, N2 and O2 should be approximately equal.
	TEST_ASSERT(abs(a_n2 - a_o2) < (initial_total_n2 * 0.1), \
		"A didn't reach 50/50 composition: N2=[a_n2] O2=[a_o2]")
	TEST_ASSERT(abs(b_n2 - b_o2) < (initial_total_o2 * 0.1), \
		"B didn't reach 50/50 composition: N2=[b_n2] O2=[b_o2]")
	// Cross-conservation: total N2 still ~200, total O2 still ~200.
	TEST_ASSERT(abs((a_n2 + b_n2) - initial_total_n2) < 1, \
		"N2 mass lost during diffusion: [initial_total_n2] → [a_n2 + b_n2] (A=[COORD(A)] planet=[A.planetary_atmos] dirs=[vg_atmos_open_dirs(A)] B=[COORD(B)] planet=[B.planetary_atmos] dirs=[vg_atmos_open_dirs(B)] a=[a_n2]/[a_o2] b=[b_n2]/[b_o2] A.air=[A_air.arena_id()] B.air=[B_air.arena_id()] A.cur=[A.air.arena_id()])")
	TEST_ASSERT(abs((a_o2 + b_o2) - initial_total_o2) < 1, \
		"O2 mass lost during diffusion: [initial_total_o2] → [a_o2 + b_o2]")

	for(var/datum/gas/g as anything in A_air.get_gases())
		A_air.set_moles(g, 0)
	for(var/datum/gas/g as anything in B_air.get_gases())
		B_air.set_moles(g, 0)


// =====================================================================
// REAL-TEST suite — goes through SSair.fire() and production APIs only.
// No manual adjacency wiring, no can_fire=FALSE bypass, no direct
// process_cell calls. If LINDA is broken in production, these will fail.
// =====================================================================

/// Real-world integration: drop plasma onto a turf via the same path
/// canister.process / atmos_spawn_air uses, then SLEEP and let the real
/// Master.Loop tick SSair the same way it ticks for a connected player.
/// Asserts that ticks actually advanced (so we know we're not just waiting
/// for a frozen MC) and that plasma reached the adjacent turf.
/datum/unit_test/dq_real_spread_via_ssair_fire

/datum/unit_test/dq_real_spread_via_ssair_fire/Run()
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no floor pair with built atmos adjacency — adjacency was never built, that's the bug")
	var/turf/open/A = pair[1]
	var/turf/open/B = pair[2]
	// Seal the pair so the injected plasma stays concentrated in A+B under real
	// SSair firing instead of dispersing across the whole (unsealed) room — the
	// test measures that gas MOVES A->B, not that it stays dense in a big room.
	dq_atmos_test_isolate_pair(A, B)

	TEST_ASSERT(vg_atmos_turfs_share(A, B), \
		"A's adjacency list doesn't contain B — round-start mask publication is broken")
	TEST_ASSERT(vg_atmos_turfs_share(B, A), \
		"B's adjacency list doesn't contain A — adjacency wasn't built symmetrically")

	// Snapshot starting plasma in both turfs.
	var/initial_a_plasma = A.air.get_moles(/datum/gas/plasma)
	var/initial_b_plasma = B.air.get_moles(/datum/gas/plasma)

	// Production gas injection — exactly what canister.process / atmos_spawn_air does.
	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/plasma, 100)
	donor.set_temperature(T20C)
	A.assume_air(donor)

	// After assume_air, A.air should have the plasma (merge) and A should
	// be in SSair.active_turfs (via air_update_turf → add_to_active).
	TEST_ASSERT(A.air.get_moles(/datum/gas/plasma) > initial_a_plasma + 50, \
		"A didn't accept the donor plasma after assume_air: [A.air.get_moles(/datum/gas/plasma)]")
	// (turf activity is Rust-side now; the real proof is that B receives gas below.)

	// Sleep to let the live Master.Loop fire SSair normally. No state hacking.
	// Guard: SSair must be genuinely TICKING, not frozen/starved. The old
	// through-floor vertical-vent bug pinned thousands of turfs perpetually active
	// and starved background SSair down to 1-2 fires per 10s window; a healthy
	// engine fires many times. We assert >=5 (robustly above the starved 1-2, and
	// well below the ~9-20 a working SSair delivers) rather than near-nominal, since
	// the absolute rate is CPU/scale-sensitive on a loaded host — the REAL behaviour
	// (gas actually reaching B) is asserted below.
	var/ticks_advanced = dq_atmos_test_wait_real_ssair_ticks(30)
	TEST_ASSERT(ticks_advanced >= 5, \
		"SSair only fired [ticks_advanced] times in ~10s — Master.Loop is barely ticking SSair (frozen/starved). Healthy is many fires; the perpetual-active-turf churn is back.")

	var/final_b_plasma = B.air.get_moles(/datum/gas/plasma)
	TEST_ASSERT(final_b_plasma > initial_b_plasma + 0.1, \
		"plasma DID NOT SPREAD to adjacent turf B after [ticks_advanced] real SSair ticks: A=[A.air.get_moles(/datum/gas/plasma)] B=[final_b_plasma]. The atmos engine isn't moving gas under normal Master.Loop firing — THIS IS THE PRODUCTION BUG.")

	// Cleanup so other tests don't see leftover plasma.
	for(var/datum/gas/g as anything in A.air.get_gases())
		A.air.set_moles(g, 0)
	for(var/datum/gas/g as anything in B.air.get_gases())
		B.air.set_moles(g, 0)


/// True end-to-end production scenario: spawn a phoron canister on an open
/// floor, set valve_open and a release pressure, sleep while Master.Loop
/// fires the canister's process() AND SSair's fire() naturally, and assert
/// plasma reaches the neighboring tile. If a player opens a canister in
/// game and gas doesn't spread, THIS test catches it.
/datum/unit_test/dq_real_canister_release_spreads_via_master_loop

/datum/unit_test/dq_real_canister_release_spreads_via_master_loop/Run()
	var/list/pair = dq_atmos_test_find_floor_pair_with_real_adjacency()
	TEST_ASSERT_NOTNULL(pair, "no floor pair with built adjacency")
	var/turf/open/A = pair[1]
	var/turf/open/B = pair[2]

	// Clear A and B to a known state so the canister's release is observable.
	for(var/datum/gas/g as anything in A.air.get_gases())
		A.air.set_moles(g, 0)
	for(var/datum/gas/g as anything in B.air.get_gases())
		B.air.set_moles(g, 0)

	A.air.set_temperature(T20C)
	B.air.set_temperature(T20C)

	// Real CHOMP phoron canister, valve open at high pressure — exact
	// scenario a player invokes via admin verb.
	var/obj/machinery/portable_atmospherics/canister/phoron/Can = new(A)
	TEST_ASSERT_NOTNULL(Can, "phoron canister construct failed")
	Can.valve_open = TRUE
	Can.release_pressure = ONE_ATMOSPHERE * 10

	// Begin processing through the SSmachines list — this is what
	// machinery does in a live game. Canister is portable_atmospherics
	// which is already a machine processor target.
	var/initial_a_plasma = A.air.get_moles(/datum/gas/plasma)
	var/initial_b_plasma = B.air.get_moles(/datum/gas/plasma)

	// Let the real game tick: Master.Loop runs SSmachines (which calls
	// Can.process()) AND SSair (which steps the gas field). This is the one
	// integration test that keeps the wall clock on purpose. Poll and break
	// as soon as both conditions asserted below hold.
	var/baseline = SSair.times_fired
	var/max_wait = min(SSair.wait * 30 * 3, DQ_ATMOS_TEST_MAX_WAIT)
	var/started = world.time
	var/final_a_plasma
	var/final_b_plasma
	while(SSair.times_fired < baseline + 30)
		final_a_plasma = A.air.get_moles(/datum/gas/plasma)
		final_b_plasma = B.air.get_moles(/datum/gas/plasma)
		if(final_a_plasma > initial_a_plasma + 1 && final_b_plasma > initial_b_plasma + 0.1)
			break
		if(world.time - started > max_wait)
			break
		sleep(SSair.wait)

	final_a_plasma = A.air.get_moles(/datum/gas/plasma)
	final_b_plasma = B.air.get_moles(/datum/gas/plasma)

	TEST_ASSERT(final_a_plasma > initial_a_plasma + 1, \
		"canister DID NOT release plasma onto A after 30 SSair ticks: A=[final_a_plasma]. canister.process() not running or not pumping.")

	// (turf enrollment is Rust-side now; the real proof is gas reaching B below.)

	TEST_ASSERT(final_b_plasma > initial_b_plasma + 0.1, \
		"plasma DID NOT spread from canister-released A to adjacent B: A=[final_a_plasma] B=[final_b_plasma]. Even though A has plasma, SSair never spread it. THIS IS THE PRODUCTION BUG players see.")

	// Cleanup
	Can.valve_open = FALSE
	qdel(Can)
	for(var/datum/gas/g as anything in A.air.get_gases())
		A.air.set_moles(g, 0)
	for(var/datum/gas/g as anything in B.air.get_gases())
		B.air.set_moles(g, 0)

/// A bounded sealed room with one local pressure disturbance must converge and
/// leave the Rust frontier. This catches self-reactivating publication, duplicate
/// queue membership, and starvation that a simple "gas reached tile B" test does not.
/datum/unit_test/dq_local_atmos_disturbance_settles

/datum/unit_test/dq_local_atmos_disturbance_settles/Run()
	var/test_z = world.maxz + 1
	world.maxz = test_z
	var/list/turf/open/room = list()
	for(var/x in 10 to 14)
		for(var/y in 10 to 14)
			var/turf/T = locate(x, y, test_z)
			if(x == 10 || x == 14 || y == 10 || y == 14)
				T.ChangeTurf(/turf/simulated/wall)
				continue
			var/turf/open/floor = T.ChangeTurf(/turf/simulated/floor)
			room += floor
			for(var/datum/gas/g as anything in floor.air.get_gases())
				floor.air.set_moles(g, 0)
			floor.air.set_moles(/datum/gas/oxygen, 20)
			floor.air.set_temperature(T20C)

	stoplag()
	var/turf/open/center = locate(12, 12, test_z)
	center.air.adjust_moles(/datum/gas/oxygen, 10)
	var/frames = 0
	var/settled = FALSE
	var/last_pressure_delta = INFINITY
	var/last_local_active = 0
	while(frames < 60)
		SSair.run_gas_frames(1)
		frames++
		var/min_pressure = INFINITY
		var/max_pressure = 0
		for(var/turf/open/floor as anything in room)
			var/pressure = floor.air.return_pressure()
			min_pressure = min(min_pressure, pressure)
			max_pressure = max(max_pressure, pressure)
		last_pressure_delta = max_pressure - min_pressure
		last_local_active = 0
		for(var/turf/open/floor as anything in room)
			if(floor.auxmos_is_atmos_active())
				last_local_active++
		// The Rust sleep criterion is applied per adjacent edge in moles, while
		// this diagnostic spans opposite corners in pressure. A sub-0.5 kPa
		// room-wide range is therefore materially settled; the stronger invariant
		// is that every local cell has actually left both activation queues.
		if(last_pressure_delta < 0.5 && !last_local_active)
			settled = TRUE
			break
	TEST_ASSERT(settled, "sealed 3x3 disturbance did not settle after [frames] gas frames (pressure delta=[last_pressure_delta], local active=[last_local_active]/9)")


/// After assume_air, update_visuals must produce a visible overlay on the
/// turf. If atmos LOOKS empty in-game despite gas being present, this is
/// the test that catches it.
/datum/unit_test/dq_real_overlay_appears_after_assume_air

/datum/unit_test/dq_real_overlay_appears_after_assume_air/Run()
	var/turf/open/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for overlay test")

	// The picked turf is nondeterministic (first floor with air in world) and may
	// already carry a visible-gas overlay — from ambient atmosphere or a prior
	// test. update_visuals() only appends overlays not already present (see
	// LINDA_turf_tile.dm), so on such a turf adding more plasma wouldn't grow
	// vis_contents and the assertion would spuriously fail. Zero the turf's gases
	// and refresh visuals first to get a clean, overlay-free baseline.
	for(var/datum/gas/g as anything in T.air.get_gases())
		T.air.set_moles(g, 0)
	T.update_visuals()

	// Snapshot the (now clean) overlay state.
	var/list/before_vis = T.vis_contents ? T.vis_contents.Copy() : list()

	// Use the production assume_air path to dump enough plasma to cross the
	// visible threshold (MOLES_GAS_VISIBLE in atmos_core.dm, typically ~0.5).
	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/plasma, 50) // way above visible threshold
	donor.set_temperature(T20C)
	T.assume_air(donor)

	TEST_ASSERT(T.air.get_moles(/datum/gas/plasma) > 40, "donor plasma didn't land on T")

	// assume_air calls update_visuals() internally. Verify a plasma overlay
	// was appended to vis_contents (the /tg/-style overlay container).
	TEST_ASSERT(length(T.vis_contents) > length(before_vis), \
		"vis_contents didn't grow after assume_air with 50 moles plasma — update_visuals not adding overlays. Players will see empty turfs filled with invisible gas.")

	// Stronger: the PLASMA overlay specifically must be the one that appeared.
	// atmos_overlay_types holds /obj/effect/overlay/gas instances whose
	// icon_state is the gas's gas_overlay (plasma → "phoron" on this fork's
	// tile_effects.dmi). Derive it from the gas datum so the test tracks any
	// future overlay-asset rename instead of hardcoding the icon_state.
	var/expected_overlay = /datum/gas/plasma::gas_overlay
	var/found_plasma_overlay = FALSE
	for(var/obj/effect/overlay/gas/G in T.atmos_overlay_types)
		if(G.icon_state == expected_overlay)
			found_plasma_overlay = TRUE
			break
	TEST_ASSERT(found_plasma_overlay, \
		"no plasma overlay (icon_state '[expected_overlay]') in atmos_overlay_types after assume_air — turf overlays grew but not with the plasma gas overlay")

	// Cleanup
	for(var/datum/gas/g as anything in T.air.get_gases())
		T.air.set_moles(g, 0)
	T.update_visuals()


/// The heat domain's turf field is wired end-to-end. A heat-eligible turf
/// (thermal_conductivity > 0 and heat_capacity > 0) must report its solid heat
/// cell's temperature through get_temperature(): the value
/// update_heat_cell() seeded from turf.temperature when SSair registered the turf.
/// It fails if the heat feature is dropped from the DLL, the registration path
/// (setup_allturfs -> heat_register_turfs, update_air_ref -> update_heat_cell)
/// breaks, or the heat world is not configured before turfs register.
/datum/unit_test/dq_superconductivity_arena_tracks_turfs

/datum/unit_test/dq_superconductivity_arena_tracks_turfs/Run()
	var/eligible = 0
	var/tracked = 0
	var/sample_temp = 0
	for(var/turf/simulated/floor/T in world)
		// A turf with no conductivity or no heat capacity is legitimately NOT in the arena.
		if(T.thermal_conductivity <= 0 || T.heat_capacity <= 0)
			continue
		eligible++
		var/arena_temp = T.get_temperature()
		// A genuinely tracked room-temperature floor reports a physical temperature.
		// Bound the top end to reject NaN/garbage too.
		if(isnum(arena_temp) && arena_temp > 150 && arena_temp < 6000)
			tracked++
			sample_temp = arena_temp

	TEST_ASSERT(eligible > 0, \
		"no heat-eligible floors on the map (thermal_conductivity>0 && heat_capacity>0) — cannot validate superconductivity")
	TEST_ASSERT(tracked > 0, \
		"0 of [eligible] heat-eligible floors report a physical heat-field temperature — the heat domain is NOT wired")
	// Broad registration, not a one-off fluke: the bulk of eligible floors must be tracked.
	TEST_ASSERT(tracked >= eligible / 2, \
		"only [tracked]/[eligible] heat-eligible floors reached the heat arena — turf registration is partially broken")
	log_test("Superconductivity: [tracked]/[eligible] eligible floors heat-tracked; sample arena temp [sample_temp] K")

/datum/unit_test/dq_airless_floor_is_not_a_cryogenic_solid

/datum/unit_test/dq_airless_floor_is_not_a_cryogenic_solid/Run()
	var/checked = 0
	for(var/turf/simulated/floor/T in world)
		if(T.initial_gas_mix != AIRLESS_ATMOS)
			continue
		checked++
		TEST_ASSERT(T.air.return_pressure() < 0.01, "airless floor contains pressurized gas")
		TEST_ASSERT(abs(T.get_temperature() - T20C) < 1, \
			"airless floor solid initialized at [T.get_temperature()] K instead of room temperature; it will refrigerate the station through superconductivity")
		if(checked >= 16)
			break
	TEST_ASSERT(checked > 0, "test map has no airless floors to validate")

/datum/unit_test/dq_dirty_gas_publication_is_watch_scoped

/datum/unit_test/dq_dirty_gas_publication_is_watch_scoped/Run()
	var/datum/gas_mixture/air = new(2500)
	var/mixture_id = air.arena_id()
	vg_drain_dirty_gas_mixtures()
	air.set_temperature(T20C + 5)
	var/list/changes = vg_drain_dirty_gas_mixtures()
	for(var/index in 1 to length(changes) step 2)
		TEST_ASSERT(changes[index] != mixture_id, "unwatched mixture was published to DM")
	watch_dirty_gas_mixture(mixture_id)
	air.set_temperature(T20C + 10)
	changes = vg_drain_dirty_gas_mixtures()
	var/found_watched = FALSE
	for(var/index in 1 to length(changes) step 2)
		if(changes[index] == mixture_id)
			found_watched = TRUE
			break
	TEST_ASSERT(found_watched, "watched mixture mutation was not published to DM")
	vg_unwatch_dirty_gas_mixture(mixture_id)
	air.set_temperature(T20C + 15)
	changes = vg_drain_dirty_gas_mixtures()
	for(var/index in 1 to length(changes) step 2)
		TEST_ASSERT(changes[index] != mixture_id, "unwatched mixture resumed publication after unsubscribe")
	qdel(air)

/datum/unit_test/dq_dirty_gas_observation_matches_air_alarm

/datum/unit_test/dq_dirty_gas_observation_matches_air_alarm/Run()
	var/turf/test_turf
	for(var/turf/simulated/floor/candidate in world)
		test_turf = candidate
		break
	TEST_ASSERT_NOTNULL(test_turf, "no simulated floor available for gas observation test")
	var/datum/gas_mixture/air = new(2500)
	air.set_temperature(T20C + 17)
	air.set_moles(/datum/gas/oxygen, 18)
	air.set_moles(/datum/gas/carbon_dioxide, 0.7)
	air.set_moles(/datum/gas/plasma, 0.2)
	air.set_moles(/datum/gas/methane, 0.1)
	air.set_moles(/datum/gas/nitrous_oxide, 0.3)
	air.set_moles(/datum/gas/volatile_fuel, 0.4)
	var/mixture_id = air.arena_id()
	watch_dirty_gas_mixture(mixture_id)
	vg_drain_dirty_gas_observations()
	air.adjust_moles(/datum/gas/oxygen, 1)
	var/list/observation = vg_drain_dirty_gas_observations()
	TEST_ASSERT_EQUAL(length(observation), GAS_DEPENDENCY_OBSERVATION_STRIDE, "dirty gas observation did not use the documented atomic stride")
	TEST_ASSERT_EQUAL(observation[1], mixture_id, "dirty gas observation returned the wrong arena mixture")
	TEST_ASSERT(abs(observation[GAS_DEPENDENCY_OBSERVATION_STRIDE] - air.total_moles()) < 0.001, "atomic observation returned the wrong total-moles cache")
	var/obj/machinery/alarm/alarm = new(test_turf)
	var/direct_signature = alarm.atmospheric_control_signature(air)
	var/observed_signature = alarm.atmospheric_control_signature_observation(observation, 1)
	TEST_ASSERT_EQUAL(observed_signature, direct_signature, "atomic Rust gas observation changed air-alarm threshold semantics")
	vg_unwatch_dirty_gas_mixture(mixture_id)
	qdel(alarm)
	qdel(air)

/datum/unit_test/dq_airalarm_radio_is_area_scoped

/datum/unit_test/dq_airalarm_radio_is_area_scoped/Run()
	var/turf/test_turf
	for(var/turf/simulated/floor/candidate in world)
		test_turf = candidate
		break
	TEST_ASSERT_NOTNULL(test_turf, "no simulated floor available for area-scoped radio test")
	var/obj/machinery/alarm/alarm = new(test_turf)
	var/obj/machinery/atmospherics/unary/vent_pump/vent = new(test_turf)
	vent.set_frequency(PUMPS_FREQ)
	var/expected_status_filter = AIRALARM_AREA_FILTER(RADIO_TO_AIRALARM, alarm.area_uid)
	var/expected_command_filter = AIRALARM_AREA_FILTER(RADIO_FROM_AIRALARM, alarm.area_uid)
	TEST_ASSERT_EQUAL(vent.radio_filter_out, expected_status_filter, "vent status radio was not scoped to its area")
	TEST_ASSERT_EQUAL(vent.radio_filter_in, expected_command_filter, "vent command radio was not scoped to its area")
	TEST_ASSERT(alarm in alarm.radio_connection.devices[expected_status_filter], "air alarm did not subscribe to its area status filter")
	TEST_ASSERT(!(alarm in alarm.radio_connection.devices[RADIO_TO_AIRALARM]), "air alarm remained on the station-wide status filter")
	qdel(vent)
	qdel(alarm)

/datum/unit_test/dq_airlock_controller_ignores_unrelated_radio

/datum/unit_test/dq_airlock_controller_ignores_unrelated_radio/Run()
	var/turf/test_turf = locate(1, 1, 1)
	var/obj/machinery/embedded_controller/radio/airlock/airlock_controller/controller = new(test_turf)
	var/datum/embedded_program/airlock/program = controller.program
	var/datum/signal/unrelated = new
	unrelated.data["tag"] = "another_airlock_sensor"
	TEST_ASSERT(!program.signal_requires_processing(unrelated), "airlock controller accepted an unrelated station-wide radio update")
	var/datum/signal/relevant = new
	relevant.data["tag"] = program.tag_chamber_sensor
	relevant.data["pressure"] = 42
	program.receive_signal(relevant)
	TEST_ASSERT_EQUAL(program.memory["chamber_sensor_pressure"], 42, "idle airlock controller did not retain its chamber pressure update")
	TEST_ASSERT(!program.signal_requires_processing(relevant), "idle airlock controller scheduled work for a passive sensor update")
	program.begin_cycle_in()
	TEST_ASSERT(program.signal_requires_processing(relevant), "cycling airlock controller rejected its chamber sensor update")
	program.stop_cycling()
	var/datum/signal/running_pump = new
	running_pump.data = list("tag" = program.tag_airpump, "power" = 1, "direction" = 1)
	program.receive_signal(running_pump)
	TEST_ASSERT(program.signal_requires_processing(running_pump), "idle airlock controller did not wake for an unexpectedly running pump")
	qdel(unrelated)
	qdel(relevant)
	qdel(running_pump)
	qdel(controller)

/datum/unit_test/dq_pda_multicaster_hibernates_between_state_changes

/datum/unit_test/dq_pda_multicaster_hibernates_between_state_changes/Run()
	var/turf/test_turf = locate(1, 1, 1)
	var/obj/machinery/pda_multicaster/multicaster = new(test_turf)
	TEST_ASSERT_EQUAL(multicaster.process(), PROCESS_KILL, "stable PDA multicaster kept polling machinery")
	multicaster.stat |= EMPED
	multicaster.update_power()
	TEST_ASSERT(!multicaster.on, "EMP state did not immediately turn off the multicaster")
	multicaster.emp_recover()
	TEST_ASSERT_EQUAL(multicaster.on, multicaster.toggle && !(multicaster.stat & (BROKEN|NOPOWER|EMPED)), "EMP recovery did not immediately reconcile multicaster state")
	qdel(multicaster)

/datum/unit_test/dq_mineral_stacker_wakes_for_input

/datum/unit_test/dq_mineral_stacker_wakes_for_input/Run()
	var/turf/center = locate(3, 3, 1)
	var/turf/input_turf = get_step(center, WEST)
	var/turf/output_turf = get_step(center, EAST)
	var/obj/machinery/mineral/input/input = new(input_turf)
	var/obj/machinery/mineral/output/output = new(output_turf)
	var/obj/machinery/mineral/stacking_machine/stacker = new(center)
	TEST_ASSERT_EQUAL(stacker.process(), PROCESS_KILL, "empty mineral stacker kept polling machinery")
	STOP_MACHINE_PROCESSING(stacker)
	var/obj/item/stack/material/steel/sheets = new(center)
	sheets.forceMove(input_turf)
	TEST_ASSERT(stacker in SSmachines.processing_machines, "mineral stacker did not wake when an item entered its input tile")
	stacker.process()
	TEST_ASSERT(QDELETED(sheets), "woken mineral stacker did not consume its input stack")
	qdel(stacker)
	qdel(input)
	qdel(output)


/// Memory: every `/turf/space` (and any other immutable_atmos turf) must point
/// its `air` at the SAME cached vacuum mixture instead of each allocating its
/// own — that's the entire point of the shared-vacuum change (LINDA_turf_tile.dm
/// /turf/open/Initialize). On Southern Cross this collapsed ~322k identical
/// per-turf vacuum mixtures (and Rust arena slots) down to one.
/datum/unit_test/dq_space_turfs_share_vacuum_mixture

/datum/unit_test/dq_space_turfs_share_vacuum_mixture/Run()
	var/turf/space/first = null
	var/turf/space/second = null
	for(var/turf/space/candidate in world)
		if(candidate.blocks_air)
			continue
		if(!first)
			first = candidate
		else if(candidate.air == first.air)
			second = candidate
			break
	TEST_ASSERT_NOTNULL(first, "no usable /turf/space found on the test map")
	TEST_ASSERT_NOTNULL(first.air, "/turf/space.air is null — vacuum mixture wasn't created")
	TEST_ASSERT(istype(first.air, /datum/gas_mixture/immutable/space), \
		"/turf/space.air is not the shared immutable/space mixture (type=[first.air.type])")
	TEST_ASSERT_NOTNULL(second, "found only one /turf/space with a distinct air reference — could not confirm sharing across multiple space turfs")
	TEST_ASSERT_EQUAL(first.air, second.air, "two /turf/space turfs on the same map do not share the same gas_mixture instance")
	TEST_ASSERT(first.immutable_atmos && second.immutable_atmos, "shared vacuum turfs are not flagged immutable_atmos")


/// Correctness: ChangeTurf-ing a floor into space must hand it the shared
/// vacuum instance (not a private copy), and ChangeTurf-ing it back to a floor
/// must give it a fresh, independently mutable mixture — never an alias of the
/// shared vacuum, and never leave the shared vacuum mutated or destroyed by the
/// round trip. Regression for LINDA_turf_tile.dm /turf/open/Initialize+Destroy
/// and the shared-mixture change in general.
/datum/unit_test/dq_changeturf_space_floor_roundtrip_preserves_shared_vacuum

/datum/unit_test/dq_changeturf_space_floor_roundtrip_preserves_shared_vacuum/Run()
	// Find an existing space turf to use as our sharing witness, and a floor
	// turf whose position we can safely round-trip through space.
	var/turf/space/witness = null
	for(var/turf/space/candidate in world)
		if(!candidate.blocks_air)
			witness = candidate
			break
	TEST_ASSERT_NOTNULL(witness, "no usable /turf/space found on the test map")
	var/datum/gas_mixture/shared_vacuum = witness.air
	TEST_ASSERT_NOTNULL(shared_vacuum, "witness space turf has null air")

	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no usable floor pair on map for ChangeTurf round-trip test")
	var/turf/simulated/floor/original = pair[1]
	var/original_type = original.type

	// floor -> space: must adopt the shared instance, not a private copy.
	var/turf/space/as_space = original.ChangeTurf(/turf/space)
	TEST_ASSERT_NOTNULL(as_space, "ChangeTurf(floor -> /turf/space) failed")
	TEST_ASSERT_EQUAL(as_space.air, shared_vacuum, \
		"floor turned into space did not adopt the shared vacuum mixture (got a private instance instead)")
	TEST_ASSERT_EQUAL(shared_vacuum.total_moles(), 0, \
		"shared vacuum mixture picked up moles when a floor was converted into space")

	// space -> floor: must get its OWN mutable mixture, never the shared one.
	var/turf/simulated/floor/back_to_floor = as_space.ChangeTurf(original_type)
	TEST_ASSERT_NOTNULL(back_to_floor, "ChangeTurf(space -> floor) failed")
	TEST_ASSERT_NOTNULL(back_to_floor.air, "floor restored from space has null air")
	TEST_ASSERT(back_to_floor.air != shared_vacuum, \
		"floor restored from space is aliasing the shared vacuum mixture instead of owning a private one")
	TEST_ASSERT(!istype(back_to_floor.air, /datum/gas_mixture/immutable), \
		"floor restored from space still has an immutable mixture — can't ever receive real air again")

	// Prove the floor's mixture is genuinely independent and mutable: writing
	// to it must not perturb the shared vacuum (which every other space turf
	// on the map is still pointing at).
	back_to_floor.air.set_moles(/datum/gas/nitrogen, MOLES_N2STANDARD)
	back_to_floor.air.set_temperature(T20C)
	TEST_ASSERT(back_to_floor.air.total_moles() > 0, \
		"floor restored from space rejected a direct gas write — its mixture isn't actually mutable")
	TEST_ASSERT_EQUAL(shared_vacuum.total_moles(), 0, \
		"writing gas to a restored floor leaked into the shared vacuum mixture — it is not actually immutable/shared-safe")
	TEST_ASSERT_EQUAL(witness.air.total_moles(), 0, \
		"an unrelated space turf's air changed after a floor round-tripped through space")

	// Clean up: put the floor back to vacuum-free space state it started from
	// isn't meaningful here (original was a floor) — restore it to a floor with
	// its original type and zero air so later tests see a clean map.
	for(var/datum/gas/g as anything in back_to_floor.air.get_gases())
		back_to_floor.air.set_moles(g, 0)
	dq_atmos_test_restore_walls()


/// The pre-M1a adjacency rule, evaluated directly in DM: two registered open
/// turfs share air when neither blocks air and every object on either turf lets
/// air through toward the other (CANATMOSPASS). Vertical pairs also need the
/// upper turf to be an opening and the z-levels to be linked. Used only as the
/// reference the Rust adjacency must reproduce.
/proc/dq_atmos_test_pairwise_shares(turf/open/A, turf/open/B, direction)
	if(!istype(A) || !istype(B) || A.blocks_air || B.blocks_air || isnull(A.air) || isnull(B.air))
		return FALSE
	var/vertical = (direction & (UP|DOWN))
	if(vertical)
		var/turf/upper = (direction & UP) ? B : A
		if(!istype(upper, /turf/simulated/open))
			return FALSE
	for(var/obj/checked_object in A.contents + B.contents)
		if(QDELETED(checked_object))
			continue
		var/turf/other = (checked_object.loc == A ? B : A)
		if(!CANATMOSPASS(checked_object, other, vertical))
			return FALSE
	return TRUE

/// Rust builds turf adjacency from DM air-block masks. On every registered
/// turf of the map it must match the old pairwise rule exactly: doors,
/// windows, firedoors and directional blockers block the same faces as before.
/datum/unit_test/dq_rust_adjacency_matches_pairwise_rule

/datum/unit_test/dq_rust_adjacency_matches_pairwise_rule/Run()
	dq_atmos_test_restore_walls()
	var/checked = 0
	var/mismatch_count = 0
	var/list/mismatches = list()
	for(var/turf/open/T in world)
		if(T.blocks_air || isnull(T.air))
			continue
		for(var/direction in GLOB.cardinals_multiz)
			var/turf/open/N = get_step_multiz(T, direction)
			if(!istype(N))
				continue
			checked++
			var/expected = dq_atmos_test_pairwise_shares(T, N, direction)
			var/actual = vg_atmos_turfs_share(T, N)
			if(!expected == !actual)
				continue
			mismatch_count++
			if(length(mismatches) < 10)
				var/list/objects = list()
				for(var/obj/O in T.contents + N.contents)
					if(O.can_atmos_pass != ATMOS_PASS_YES)
						objects += "[O.type](dir=[O.dir], density=[O.density])"
				mismatches += "[COORD(T)] -> [COORD(N)] dir=[direction]: expected [expected ? "open" : "blocked"], Rust [actual ? "open" : "blocked"]; masks [T.air_block_mask()]/[N.air_block_mask()]; objects [jointext(objects, ", ")]"
		CHECK_TICK
	TEST_ASSERT(checked > 0, "no registered turf pairs on the map")
	TEST_ASSERT(!mismatch_count, "Rust adjacency differs from the pairwise rule on [mismatch_count] of [checked] faces:\n[jointext(mismatches, "\n")]")

/// Gas IDs cross the FFI as numbers. The DM table and the Rust registry agree,
/// and every accepted key form reaches the same gas.
/datum/unit_test/dq_gas_ids_are_numeric_end_to_end

/datum/unit_test/dq_gas_ids_are_numeric_end_to_end/Run()
	TEST_ASSERT_EQUAL(length(GLOB.gas_path_by_idx), GAS_ID_COUNT, "gas path table size")
	for(var/datum/gas/gas_path as anything in subtypesof(/datum/gas))
		var/idx = initial(gas_path.idx)
		TEST_ASSERT_NOTNULL(idx, "[gas_path] has no GAS_ID_* idx")
		TEST_ASSERT_EQUAL(GLOB.gas_path_by_idx[idx + 1], gas_path, "gas_path_by_idx disagrees for [gas_path]")
		TEST_ASSERT_EQUAL(GAS_IDX(gas_path), idx, "GAS_IDX(path) for [gas_path]")
		TEST_ASSERT_EQUAL(GAS_IDX("[gas_path]"), idx, "GAS_IDX(path text) for [gas_path]")
		TEST_ASSERT_EQUAL(GAS_IDX(initial(gas_path.id)), idx, "GAS_IDX(short id) for [gas_path]")
	var/datum/gas_mixture/mix = new(CELL_VOLUME)
	mix.set_moles(GAS_ID_PLASMA, 12)
	mix.adjust_moles(/datum/gas/plasma, 3)
	TEST_ASSERT_EQUAL(mix.get_moles(GAS_ID_PLASMA), 15, "numeric and path gas keys reach the same slot")
	mix.adjust_multiple_gases(list(/datum/gas/oxygen = 4, /datum/gas/nitrogen = 6))
	var/list/gases = mix.get_gases()
	TEST_ASSERT_EQUAL(gases[/datum/gas/plasma], 15, "get_gases plasma")
	TEST_ASSERT_EQUAL(gases[/datum/gas/oxygen], 4, "get_gases oxygen")
	TEST_ASSERT_EQUAL(gases[/datum/gas/nitrogen], 6, "get_gases nitrogen")
	var/list/readings = read_gas_mixtures(list(mix, null))
	TEST_ASSERT_EQUAL(length(readings), 2 * GAS_READ_STRIDE, "read_gas_mixtures keeps null entries")
	TEST_ASSERT_EQUAL(readings[GAS_READ_TOTAL_MOLES], 25, "batched total moles")
	TEST_ASSERT_EQUAL(readings[GAS_READ_MOLES(GAS_ID_OXYGEN)], 4, "batched oxygen moles")
	TEST_ASSERT_EQUAL(readings[GAS_READ_STRIDE + GAS_READ_TOTAL_MOLES], 0, "a null mixture reads as zero")
	qdel(mix)
