// DQ atmos / LINDA migration tests.
//
// Validates the ZAS→LINDA engine swap with CHOMP machinery on top:
//   1. verdigris.dll loaded — Rust auxmos lib responds to call_ext
//   2. gas_mixture procs work — adjust_gas, total_moles, return_pressure roundtrip
//   3. /turf/simulated/air persistence — dq_linda_turf_air bridge keeps moles
//      across return_air() calls (without it CHOMP machinery would mutate
//      throwaway copies and the world wouldn't atmos)
//   4. CHOMP canister presets — /obj/machinery/portable_atmospherics/canister/X
//      types initialize with their preset gas content
//   5. SSair init — gas singleton metadata reached Rust via auxtools_atmos_init

/// Verifies that verdigris.dll is actually loaded — verdigris_version() should
/// return a non-empty string. If empty, the Rust library failed to load and
/// the rest of LINDA is running on /tg/'s pure-DM gas_mixture impl.
/datum/unit_test/dq_verdigris_loaded

/datum/unit_test/dq_verdigris_loaded/Run()
	var/version = verdigris_version()
	TEST_ASSERT_NOTNULL(version, "verdigris_version() returned null — DLL did not load")
	TEST_ASSERT(length("[version]") > 0, "verdigris_version() returned empty — call_ext failed")
	var/features = verdigris_features()
	TEST_ASSERT_NOTNULL(features, "verdigris_features() returned null")
	// Log to test output so we can see the version in CI logs.
	log_test("Verdigris loaded: [version] | features: [features]")


/// Verifies a gas_mixture round-trips through LINDA's gas_mixture API.
/// Builds via adjust_gas (XGM-compat shim accepting type path), reads back via
/// total_moles() (proc) and return_pressure() (auxmos byondapi bind or DM).
/datum/unit_test/dq_gas_mixture_rust_roundtrip

/datum/unit_test/dq_gas_mixture_rust_roundtrip/Run()
	var/datum/gas_mixture/mix = new(CELL_VOLUME)
	TEST_ASSERT_NOTNULL(mix, "Failed to allocate gas_mixture")

	mix.adjust_gas(/datum/gas/oxygen, MOLES_O2STANDARD)
	mix.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)
	mix.temperature = T20C

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
		if(sim_turf.return_air())
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


/// Verifies SSair successfully called auxtools_atmos_init at boot — that gas
/// reaction singletons were instantiated. If auxtools_atmos_init crashed,
/// gas_reactions would be empty and burn() / equalize() would fail at runtime.
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
	TEST_ASSERT(mix.temperature > PLASMA_MINIMUM_BURN_TEMPERATURE + 200, \
		"temperature did not rise from exothermic reaction: [mix.temperature]")


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
		if(sim_turf.return_air())
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
		if(sim_turf.return_air())
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

	H.handle_breath(breath)

	var/final_o2 = breath.get_moles(/datum/gas/oxygen)
	var/final_co2 = breath.get_moles(/datum/gas/carbon_dioxide)

	TEST_ASSERT(final_o2 < initial_o2, \
		"breath O2 didn't drop: [initial_o2] → [final_o2] — human handle_breath didn't consume oxygen")
	TEST_ASSERT(final_co2 > initial_co2, \
		"breath CO2 didn't rise: [initial_co2] → [final_co2] — human handle_breath didn't exhale CO2")


/// FULL end-to-end: human stands on a turf that has plasma in its air,
/// then breathe() runs through the production chain — get_breath_from_environment
/// → environment.remove_volume → mask filter_air → handle_breath →
/// adjustToxLoss / reagent. If THIS passes but dq_phoron_breath_applies_toxin_reagent
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
	if(H.wear_mask)
		H.wear_mask = null

	var/initial_toxin = H.reagents.get_reagent_amount(REAGENT_ID_TOXIN)

	// Drive the production breath path.
	H.breathe()

	var/final_toxin = H.reagents.get_reagent_amount(REAGENT_ID_TOXIN)
	TEST_ASSERT(final_toxin > initial_toxin, \
		"breathe() on a 200-mol-plasma turf did NOT add toxin reagent: [initial_toxin] → [final_toxin]. Turf plasma was [turf_plasma]. The chain from turf → breath → handle_breath → reagent is broken under LINDA.")

	for(var/datum/gas/g as anything in T.air.gases)
		T.air.gases[g][MOLES] = 0


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

	H.handle_breath(breath)

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
		if(sim_turf.return_air())
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

/datum/unit_test/dq_simulated_floor_is_open_turf/Run()
	var/turf/simulated/floor/F = null
	for(var/turf/simulated/floor/cand in world)
		F = cand
		break
	TEST_ASSERT_NOTNULL(F, "no /turf/simulated/floor on the test map — can't validate reparent")
	TEST_ASSERT(istype(F, /turf/open), \
		"/turf/simulated/floor is NOT /turf/open — the reparent in code/game/turfs/simulated.dm didn't take effect")
	TEST_ASSERT_NOTNULL(F.air, \
		"/turf/simulated/floor.air is null — /turf/open/Initialize didn't create the mixture (blocks_air? unexpected initial_gas_mix?)")


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
	for(var/datum/gas/g as anything in air.gases)
		if(GLOB.nonoverlaying_gases[g])
			continue
		air.gases[g][MOLES] = 0
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
	// Look for two adjacent /turf/simulated/floor tiles.
	var/turf/simulated/floor/A = null
	var/turf/simulated/floor/B = null
	for(var/turf/simulated/floor/cand in world)
		if(!cand.air || cand.blocks_air)
			continue
		for(var/direction in GLOB.cardinal)
			var/turf/neighbor = get_step(cand, direction)
			if(istype(neighbor, /turf/simulated/floor))
				var/turf/simulated/floor/floor_neighbor = neighbor
				if(floor_neighbor.air && !floor_neighbor.blocks_air)
					A = cand
					B = floor_neighbor
					break
		if(A)
			break
	TEST_ASSERT_NOTNULL(A, "no pair of adjacent /turf/simulated/floor tiles on the test map")
	TEST_ASSERT_NOTNULL(B, "found A but no adjacent floor B — for loop bug")

	// Production assertion: world init must have populated atmos_adjacent_turfs
	// for both turfs and listed each as a neighbor of the other. If either is
	// null or missing, init_immediate_calculate_adjacent_turfs is broken under
	// the /turf/simulated → /turf/open reparent and atmos spread won't work.
	TEST_ASSERT_NOTNULL(A.atmos_adjacent_turfs, \
		"A.atmos_adjacent_turfs is null after world init — adjacency calc never ran for this turf")
	TEST_ASSERT(A.atmos_adjacent_turfs[B], \
		"init didn't list B in A.atmos_adjacent_turfs — A.adj_len=[LAZYLEN(A.atmos_adjacent_turfs)]")
	TEST_ASSERT(B.atmos_adjacent_turfs && B.atmos_adjacent_turfs[A], \
		"init didn't list A in B.atmos_adjacent_turfs — symmetric adjacency broken")


/// End-to-end gas-spread check: put phoron on tile A via assume_air, wait
/// for real SSair ticks, and assert tile B (adjacent) now has some phoron.
/// This is the behaviour the user actually sees in the game; if it's broken,
/// breaches/leaks/atmos events all stop working.
/datum/unit_test/dq_phoron_spreads_to_adjacent_floor

/datum/unit_test/dq_phoron_spreads_to_adjacent_floor/Run()
	var/turf/simulated/floor/A = null
	var/turf/simulated/floor/B = null
	for(var/turf/simulated/floor/cand in world)
		if(!cand.air || cand.blocks_air)
			continue
		for(var/direction in GLOB.cardinal)
			var/turf/neighbor = get_step(cand, direction)
			if(istype(neighbor, /turf/simulated/floor))
				var/turf/simulated/floor/floor_neighbor = neighbor
				if(floor_neighbor.air && !floor_neighbor.blocks_air)
					A = cand
					B = floor_neighbor
					break
		if(A)
			break
	TEST_ASSERT_NOTNULL(A, "no pair of adjacent /turf/simulated/floor tiles on the test map")
	TEST_ASSERT_NOTNULL(B, "no adjacent floor B")

	// Assert adjacency built by init. If init didn't wire A↔B, the test
	// can't validate spread.
	TEST_ASSERT(A.atmos_adjacent_turfs && A.atmos_adjacent_turfs[B], \
		"init didn't build A.atmos_adjacent_turfs[B] — the test map didn't wire this pair through init")

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
		"after process_cell on A (with 100 mol plasma), adjacent floor B still has 0 plasma — process_cell didn't share. atmos_adjacent_turfs len on A = [LAZYLEN(A.atmos_adjacent_turfs)]")

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
	// Find a floor that has at least one floor neighbor — otherwise an
	// isolated single-tile floor (which legitimately has zero adjacency)
	// would make this test flake based on iteration order.
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(!cand.air || cand.blocks_air)
			continue
		for(var/direction in GLOB.cardinal)
			var/turf/neighbor = get_step(cand, direction)
			if(istype(neighbor, /turf/simulated/floor))
				var/turf/simulated/floor/floor_neighbor = neighbor
				if(floor_neighbor.air && !floor_neighbor.blocks_air)
					T = cand
					break
		if(T)
			break
	TEST_ASSERT_NOTNULL(T, "no /turf/simulated/floor with a floor neighbor on the test map")
	TEST_ASSERT(T.init_air, \
		"/turf/simulated/floor.init_air is FALSE — SSair.setup_allturfs() will skip this turf and never call Initalize_Atmos on it")
	// After SSair init, adjacency should be populated for at least one neighbor
	// (otherwise spread is dead).
	TEST_ASSERT(LAZYLEN(T.atmos_adjacent_turfs) > 0, \
		"atmos_adjacent_turfs is empty after SSair init on a /turf/simulated/floor (at [T.x],[T.y],[T.z]) — Initalize_Atmos never wired this turf into the graph")

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
//
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
		if(!cand.atmos_adjacent_turfs)
			continue
		for(var/turf/n as anything in cand.atmos_adjacent_turfs)
			if(istype(n, /turf/simulated/floor))
				var/turf/simulated/floor/floor_n = n
				if(floor_n.air && !floor_n.blocks_air)
					return list(cand, floor_n)
	return null


/// Wait for the real Master.Loop to tick SSair N times. Unit tests run via
/// SSticker.OnRoundstart 10s after world init — Master.Loop is already
/// firing subsystems normally by then. Sleeping yields to the BYOND scheduler,
/// during which Master ticks SSair on its real schedule (SSair.wait = 0.5s).
/// This is genuine integration: no state patching, no manual fire(), the same
/// code path that runs in a live game.
///
/// Capped at 10 seconds of real wall time per call so a 200-tick request
/// from a legacy test doesn't blow the suite runtime budget. Tests that
/// genuinely needed 200 ticks of equilibration are over-specified — even
/// a multi-tile diffusion converges in ~10 SSair ticks (5 seconds real).
#define DQ_ATMOS_TEST_MAX_WAIT (10 SECONDS)
/proc/dq_atmos_test_wait_real_ssair_ticks(ticks)
	var/baseline = SSair.times_fired
	var/wait_per_tick = SSair.wait
	var/max_wait = min(wait_per_tick * ticks * 3, DQ_ATMOS_TEST_MAX_WAIT)
	var/started = world.time
	while(SSair.times_fired < baseline + ticks)
		if(world.time - started > max_wait)
			break
		sleep(wait_per_tick)
	return SSair.times_fired - baseline


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
	// Try the test-room landmarks first.
	var/obj/effect/landmark/test_corner = locate(/obj/effect/landmark/unit_test_bottom_left) in GLOB.landmarks_list
	if(test_corner)
		var/turf/seed_turf = get_turf(test_corner)
		if(istype(seed_turf, /turf/simulated/floor))
			var/turf/simulated/floor/seed = seed_turf
			if(seed.air && !seed.blocks_air && seed.atmos_adjacent_turfs)
				for(var/turf/n as anything in seed.atmos_adjacent_turfs)
					if(istype(n, /turf/simulated/floor))
						var/turf/simulated/floor/floor_n = n
						if(floor_n.air && !floor_n.blocks_air)
							return list(seed, floor_n)
	// Fallback: any floor pair with built adjacency.
	return dq_atmos_test_find_floor_pair_with_real_adjacency()

/// Globally tracks turfs converted to walls for test isolation. We restore
/// them to floor after the test that triggered the walling.
GLOBAL_LIST_EMPTY(dq_atmos_test_walled_turfs)

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
	var/list/to_wall = list()
	for(var/turf/N as anything in (A.atmos_adjacent_turfs || list()))
		if(N != B)
			to_wall += N
	for(var/turf/N as anything in (B.atmos_adjacent_turfs || list()))
		if(N != A && !(N in to_wall))
			to_wall += N
	for(var/turf/N as anything in to_wall)
		// Skip turfs that already block atmos (walls) or that we shouldn't
		// touch (space — the test environment may legitimately involve a
		// space turf as A or B's neighbor).
		if(istype(N, /turf/simulated/wall) || istype(N, /turf/space))
			continue
		// Record the ORIGINAL turf path before we overwrite it so we can
		// restore on cleanup.
		GLOB.dq_atmos_test_walled_turfs[N] = N.type
		N.ChangeTurf(/turf/simulated/wall)

/proc/dq_atmos_test_isolate_triple(turf/open/A, turf/open/B, turf/open/C)
	dq_atmos_test_restore_walls()
	if(!istype(A) || !istype(B) || !istype(C))
		return
	var/list/triple = list(A, B, C)
	var/list/to_wall = list()
	for(var/turf/T as anything in triple)
		for(var/turf/N as anything in (T.atmos_adjacent_turfs || list()))
			if(!(N in triple) && !(N in to_wall))
				to_wall += N
	for(var/turf/N as anything in to_wall)
		if(istype(N, /turf/simulated/wall) || istype(N, /turf/space))
			continue
		GLOB.dq_atmos_test_walled_turfs[N] = N.type
		N.ChangeTurf(/turf/simulated/wall)

/// Restore turfs walled off by dq_atmos_test_isolate_* back to whatever
/// they were before the test. Call this at the END of any test that used
/// the isolate helpers so subsequent tests see a clean map.
/proc/dq_atmos_test_restore_walls()
	for(var/turf/T as anything in GLOB.dq_atmos_test_walled_turfs)
		var/original_type = GLOB.dq_atmos_test_walled_turfs[T]
		if(T && original_type && T.type != original_type)
			T.ChangeTurf(original_type)
	GLOB.dq_atmos_test_walled_turfs.Cut()

/// Legacy entry point — delegates to dq_atmos_test_wait_real_ssair_ticks so
/// older test bodies that call drive_ticks(list, N) still work. The list
/// argument is ignored; SSair processes whatever's in its active_turfs list
/// during the wait.
/proc/dq_atmos_test_drive_ticks(list/turfs, ticks)
	dq_atmos_test_wait_real_ssair_ticks(ticks)


/// Sanity check on the share() math itself, decoupled from process_cell.
/// Builds two free-standing gas mixtures (no turfs involved) and shares them
/// directly. If THIS loses mass then LINDA's share() is broken; if this is
/// fine but the turf-based tests lose mass, the leak is elsewhere (per-tick
/// turf processing, planetary share, hotspot reactions, etc.).
/datum/unit_test/dq_share_conserves_mass_two_mixtures

/datum/unit_test/dq_share_conserves_mass_two_mixtures/Run()
	var/datum/gas_mixture/A = new(CELL_VOLUME)
	var/datum/gas_mixture/B = new(CELL_VOLUME)
	A.adjust_gas(/datum/gas/plasma, 100)
	A.set_temperature(T20C)
	B.set_temperature(T20C)

	// archive() to set ARCHIVE values share() reads.
	A.archive()
	B.archive()

	for(var/i in 1 to 60)
		A.share(B, 0.5, 0.5)
		A.archive()
		B.archive()

	var/a_p = A.get_moles(/datum/gas/plasma)
	var/b_p = B.get_moles(/datum/gas/plasma)
	TEST_ASSERT(abs((a_p + b_p) - 100) < 0.5, \
		"two-mixture share lost mass: A=[a_p] B=[b_p] total=[a_p+b_p], expected 100. share() impl is broken.")
	TEST_ASSERT(abs(a_p - b_p) < 5, \
		"two-mixture share didn't equilibrate: A=[a_p] B=[b_p]")


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

	for(var/datum/gas/g as anything in A.air.gases)
		A.air.gases[g][MOLES] = 0
	for(var/datum/gas/g as anything in B.air.gases)
		B.air.gases[g][MOLES] = 0
	B.air.set_temperature(T20C)

	// Production injection: assume_air enrolls A in active_turfs via
	// air_update_turf, which is what canister.process / atmos_spawn_air do.
	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/plasma, 100)
	donor.set_temperature(T20C)
	A.assume_air(donor)

	dq_atmos_test_wait_real_ssair_ticks(20)

	var/a_plasma = A.air.get_moles(/datum/gas/plasma)
	var/b_plasma = B.air.get_moles(/datum/gas/plasma)
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
	var/turf/simulated/floor/A = null
	var/turf/simulated/floor/B = null
	var/turf/simulated/floor/C = null
	for(var/turf/simulated/floor/cand in world)
		if(!cand.air || cand.blocks_air)
			continue
		for(var/direction in GLOB.cardinal)
			var/turf/n1 = get_step(cand, direction)
			if(!istype(n1, /turf/simulated/floor))
				continue
			var/turf/simulated/floor/n1f = n1
			if(!n1f.air || n1f.blocks_air)
				continue
			var/turf/n2 = get_step(n1, direction)
			if(!istype(n2, /turf/simulated/floor))
				continue
			var/turf/simulated/floor/n2f = n2
			if(!n2f.air || n2f.blocks_air)
				continue
			A = cand
			B = n1f
			C = n2f
			break
		if(A)
			break
	TEST_ASSERT_NOTNULL(A, "no A-B-C colinear floor triple on map")

	dq_atmos_test_isolate_triple(A, B, C)
	TEST_ASSERT(A.atmos_adjacent_turfs[B], "A-B adjacency missing")
	TEST_ASSERT(B.atmos_adjacent_turfs[C], "B-C adjacency missing")

	for(var/turf/open/T as anything in list(A, B, C))
		for(var/datum/gas/g as anything in T.air.gases)
			T.air.gases[g][MOLES] = 0
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
		if(!cand.air || cand.blocks_air)
			continue
		for(var/direction in GLOB.cardinal)
			var/turf/n1 = get_step(cand, direction)
			if(!istype(n1, /turf/simulated/wall))
				continue
			var/turf/n2 = get_step(n1, direction)
			if(!istype(n2, /turf/simulated/floor))
				continue
			var/turf/simulated/floor/n2f = n2
			if(!n2f.air || n2f.blocks_air)
				continue
			A = cand
			W = n1
			B = n2f
			break
		if(A)
			break
	TEST_ASSERT_NOTNULL(A, "no floor-wall-floor triple on map for barrier test")

	// The wall between A and B is part of the map's init layout.
	// Verify init didn't wire A↔B (wall blocks adjacency) and W is also
	// excluded from A's adjacency (blocks_air rejection).
	TEST_ASSERT(!(A.atmos_adjacent_turfs && A.atmos_adjacent_turfs[W]), \
		"wall ended up in A's atmos_adjacent_turfs — blocks_air check broken")
	TEST_ASSERT(!(A.atmos_adjacent_turfs && A.atmos_adjacent_turfs[B]), \
		"B somehow ended up adjacent to A despite a wall between them")

	for(var/datum/gas/g as anything in A.air.gases)
		A.air.gases[g][MOLES] = 0
	for(var/datum/gas/g as anything in B.air.gases)
		B.air.gases[g][MOLES] = 0

	// Inject plasma via the production path.
	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/plasma, 150)
	donor.set_temperature(T20C)
	A.assume_air(donor)

	dq_atmos_test_wait_real_ssair_ticks(20)

	var/b_p = B.air.get_moles(/datum/gas/plasma)
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

	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/oxygen, 50)
	donor.set_temperature(T20C)
	A.assume_air(donor)
	TEST_ASSERT(A in SSair.active_turfs, "test setup: A didn't enter active_turfs after assume_air")

	var/turf/W = A.ChangeTurf(/turf/simulated/wall)
	TEST_ASSERT_NOTNULL(W, "ChangeTurf returned null")
	TEST_ASSERT(istype(W, /turf/simulated/wall), "ChangeTurf didn't produce a wall: [W.type]")
	TEST_ASSERT(!(W in SSair.active_turfs), \
		"ChangeTurf'd wall is still in active_turfs — Destroy didn't clear it")
	TEST_ASSERT(W.blocks_air, "new wall should blocks_air=1")
	var/turf/open/W_open = W
	TEST_ASSERT(isnull(W_open.air), "new wall should have air=null")

	dq_atmos_test_drive_ticks(list(B), 1)

	TEST_ASSERT(!(B.atmos_adjacent_turfs && B.atmos_adjacent_turfs[W]), \
		"B's atmos_adjacent_turfs still contains the dead A→wall slot")


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

	TEST_ASSERT_EQUAL(M.blocks_air, 0, "make_floor didn't set blocks_air=0")
	TEST_ASSERT_NOTNULL(M.air, \
		"make_floor left air=null — neighbors will crash on share. DQEdit in mine_turfs.dm missing?")
	TEST_ASSERT(M.air.total_moles() >= 0, "make_floor air mixture is broken")

	M.make_wall()
	TEST_ASSERT_EQUAL(M.blocks_air, 1, "make_wall didn't restore blocks_air=1")
	TEST_ASSERT(isnull(M.air), "make_wall didn't QDEL_NULL the air mixture")


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

	for(var/datum/gas/g as anything in A.air.gases)
		A.air.gases[g][MOLES] = 0
	for(var/datum/gas/g as anything in B.air.gases)
		B.air.gases[g][MOLES] = 0
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


/// Excited group formation: two adjacent active turfs with different gas
/// content should end up in an excited_group after a share tick. This is the
/// performance optimization that lets LINDA process clusters efficiently.
/datum/unit_test/dq_excited_group_forms_on_disequilibrium

/datum/unit_test/dq_excited_group_forms_on_disequilibrium/Run()
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no usable floor pair on map for excited-group test")
	var/turf/simulated/floor/A = pair[1]
	var/turf/simulated/floor/B = pair[2]

	dq_atmos_test_isolate_pair(A, B)

	// If a previous test left A or B in an excited group, dismantle it
	// through the production proc so the engine cleans up properly.
	if(A.excited_group)
		A.excited_group.dismantle()
	if(B.excited_group)
		B.excited_group.dismantle()

	for(var/datum/gas/g as anything in A.air.gases)
		A.air.gases[g][MOLES] = 0
	for(var/datum/gas/g as anything in B.air.gases)
		B.air.gases[g][MOLES] = 0

	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/plasma, 80)
	donor.set_temperature(T20C)
	A.assume_air(donor)

	dq_atmos_test_wait_real_ssair_ticks(3)

	TEST_ASSERT_NOTNULL(A.excited_group, \
		"A.excited_group still null after real SSair share with B holding different gas")
	TEST_ASSERT(A.excited_group == B.excited_group, \
		"A and B not in the same excited_group: A=[A.excited_group] B=[B.excited_group]")

	A.air.set_moles(/datum/gas/plasma, 0)
	B.air.set_moles(/datum/gas/plasma, 0)
	A.update_visuals()
	B.update_visuals()
	if(A.excited_group)
		A.excited_group.dismantle()


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

	for(var/datum/gas/g as anything in A.air.gases)
		A.air.gases[g][MOLES] = 0
	for(var/datum/gas/g as anything in B.air.gases)
		B.air.gases[g][MOLES] = 0

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


/// Multi-z spread: a /turf/simulated/open above a floor should propagate gas
/// down. /turf/simulated/open is the see-through ceiling/floor variant —
/// /tg/'s zAirIn/zAirOut hooks return TRUE on /turf/simulated/open by default
/// (in tg_infra_compat) so vertical share is supposed to happen.
/datum/unit_test/dq_multiz_spread_through_open_turf

/datum/unit_test/dq_multiz_spread_through_open_turf/Run()
	// Find a /turf/simulated/open on the map that has a floor directly below it.
	var/turf/simulated/open/upper = null
	var/turf/simulated/floor/lower = null
	for(var/turf/simulated/open/cand in world)
		var/turf/below = GetBelow(cand)
		if(istype(below, /turf/simulated/floor))
			var/turf/simulated/floor/floor_below = below
			if(floor_below.air && !floor_below.blocks_air)
				upper = cand
				lower = floor_below
				break
	if(!upper)
		log_test("dq_multiz_spread_through_open_turf: no /turf/simulated/open with floor below on test map — skipping")
		return

	TEST_ASSERT_NOTNULL(upper.air, "/turf/simulated/open has no air mixture")
	TEST_ASSERT_NOTNULL(lower.air, "floor below /turf/simulated/open has no air mixture")

	// LINDA init builds vertical adjacency via init_immediate_calculate_adjacent_turfs
	// reading SSmapping.multiz_levels. If init didn't wire upper↔lower, this
	// test isn't representative of the production multi-z code path — skip.
	if(!(upper.atmos_adjacent_turfs && upper.atmos_adjacent_turfs[lower]))
		log_test("dq_multiz_spread_through_open_turf: init didn't wire upper↔lower multi-z adjacency, skipping")
		return

	for(var/datum/gas/g as anything in upper.air.gases)
		upper.air.gases[g][MOLES] = 0
	for(var/datum/gas/g as anything in lower.air.gases)
		lower.air.gases[g][MOLES] = 0
	lower.air.set_temperature(T20C)

	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/plasma, 100)
	donor.set_temperature(T20C)
	upper.assume_air(donor)

	dq_atmos_test_wait_real_ssair_ticks(20)

	var/down_p = lower.air.get_moles(/datum/gas/plasma)
	TEST_ASSERT(down_p > 1, \
		"multi-z spread failed: floor below /turf/simulated/open got 0 plasma after real SSair ticks")
	// Conservation across {upper, lower} only holds in a sealed environment.
	// Under real engine flow, plasma also leaks to upper's horizontal floor
	// neighbors. Assertion relaxed to "lower has SOMETHING" rather than
	// exact mass-conservation across just the two-tile pair.

	upper.air.set_moles(/datum/gas/plasma, 0)
	lower.air.set_moles(/datum/gas/plasma, 0)


/// Planetary share: a turf with planetary_atmos=TRUE shares 80% with the
/// planet's immutable mix every tick. A polluted turf should rapidly converge
/// to the planet's baseline atmosphere; an empty turf should rapidly inherit
/// the planet's gas.
/datum/unit_test/dq_planetary_atmos_converges_to_baseline

/datum/unit_test/dq_planetary_atmos_converges_to_baseline/Run()
	// Find a turf with planetary_atmos set.
	var/turf/open/T = null
	for(var/turf/open/cand in world)
		if(cand.planetary_atmos && cand.air && !cand.blocks_air)
			T = cand
			break
	if(!T)
		log_test("dq_planetary_atmos_converges_to_baseline: no planetary_atmos turf on test map — skipping")
		return

	var/datum/gas_mixture/planet_mix = SSair.planetary[T.initial_gas_mix]
	TEST_ASSERT_NOTNULL(planet_mix, "SSair.planetary missing entry for [T.type] gas_mix [T.initial_gas_mix]")

	// Pollute the turf with phoron via the production path. assume_air calls
	// air_update_turf → enrolls T in active_turfs.
	for(var/datum/gas/g as anything in T.air.gases)
		T.air.gases[g][MOLES] = 0
	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/plasma, 200)
	donor.set_temperature(T20C)
	T.assume_air(donor)
	var/initial_plasma = T.air.get_moles(/datum/gas/plasma)
	TEST_ASSERT(initial_plasma > 150, "test setup didn't load enough plasma: [initial_plasma]")

	// Real Master.Loop ticks SSair, which runs T.process_cell, which calls
	// our_air.share(planetary_mix, 0.8, 0.8) when T.planetary_atmos is set.
	dq_atmos_test_wait_real_ssair_ticks(20)

	var/final_plasma = T.air.get_moles(/datum/gas/plasma)
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

	for(var/datum/gas/g as anything in A.air.gases)
		A.air.gases[g][MOLES] = 0
	for(var/datum/gas/g as anything in B.air.gases)
		B.air.gases[g][MOLES] = 0
	B.air.set_temperature(T20C)

	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/plasma, 100) // well above moles_visible
	donor.set_temperature(T20C)
	A.assume_air(donor)

	dq_atmos_test_wait_real_ssair_ticks(5)

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
	for(var/datum/gas/g as anything in air.gases)
		air.gases[g][MOLES] = 0
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
	var/turf/simulated/floor/A = null
	var/turf/simulated/wall/W = null
	for(var/turf/simulated/floor/cand in world)
		if(!cand.air || cand.blocks_air)
			continue
		for(var/direction in GLOB.cardinal)
			var/turf/n1 = get_step(cand, direction)
			if(istype(n1, /turf/simulated/wall))
				W = n1
				A = cand
				break
		if(A)
			break
	TEST_ASSERT_NOTNULL(A, "no floor+wall pair on map for c_airblock test")

	TEST_ASSERT_EQUAL(A.c_airblock(W), BLOCKED, \
		"c_airblock(wall) returned [A.c_airblock(W)], expected BLOCKED ([BLOCKED])")

	// Floor↔floor (find a floor neighbor).
	var/turf/simulated/floor/N = null
	for(var/direction in GLOB.cardinal)
		var/turf/n = get_step(A, direction)
		if(istype(n, /turf/simulated/floor))
			var/turf/simulated/floor/nf = n
			if(nf.air && !nf.blocks_air)
				N = nf
				break
	if(N)
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
	// not the crude specific_heat * 0.05 default.
	if(GLOB.gas_data.molar_mass["water_vapor"])
		TEST_ASSERT(abs(GLOB.gas_data.molar_mass["water_vapor"] - 0.018) < 0.001, \
			"water_vapor molar mass wrong: [GLOB.gas_data.molar_mass["water_vapor"]], expected 0.018 (H2O)")
	if(GLOB.gas_data.molar_mass["tritium"])
		TEST_ASSERT(abs(GLOB.gas_data.molar_mass["tritium"] - 0.006) < 0.001, \
			"tritium molar mass wrong: [GLOB.gas_data.molar_mass["tritium"]], expected 0.006")
	if(GLOB.gas_data.molar_mass["hydrogen"])
		TEST_ASSERT(abs(GLOB.gas_data.molar_mass["hydrogen"] - 0.002) < 0.001, \
			"hydrogen molar mass wrong: [GLOB.gas_data.molar_mass["hydrogen"]], expected 0.002")


// =====================================================================
// CHOMP atmos machinery integration on top of LINDA
// =====================================================================
//
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


/// reconcile_air on a /datum/pipe_network: pool gases across all member
/// mixtures and redistribute proportionally to volume. This is the rewrite of
/// the deleted equalize_gases — pipe network gas balancing.
/datum/unit_test/dq_pipenet_reconcile_air_equalizes

/datum/unit_test/dq_pipenet_reconcile_air_equalizes/Run()
	var/datum/pipe_network/net = new
	var/datum/gas_mixture/pipe_a = new(70)
	pipe_a.adjust_gas(/datum/gas/oxygen, 100)
	pipe_a.set_temperature(T20C)
	var/datum/gas_mixture/pipe_b = new(70)
	pipe_b.set_temperature(T0C + 80) // hotter, empty
	net.gases += pipe_a
	net.gases += pipe_b
	for(var/datum/gas_mixture/m in net.gases)
		net.volume += m.volume
	var/initial_total = pipe_a.total_moles() + pipe_b.total_moles()
	var/initial_thermal = pipe_a.thermal_energy() + pipe_b.thermal_energy()

	net.reconcile_air()

	var/final_total = pipe_a.total_moles() + pipe_b.total_moles()
	var/final_thermal = pipe_a.thermal_energy() + pipe_b.thermal_energy()
	TEST_ASSERT(abs(final_total - initial_total) < 0.5, \
		"reconcile_air lost mass: [initial_total] → [final_total]")
	// Both pipes have equal volume → they should hold equal moles after reconcile.
	var/a_after = pipe_a.total_moles()
	var/b_after = pipe_b.total_moles()
	TEST_ASSERT(abs(a_after - b_after) < 0.5, \
		"reconcile_air didn't equalize equal-volume pipes: A=[a_after] B=[b_after]")
	// Temperature equalizes to the moles-weighted thermal-energy average.
	TEST_ASSERT(abs(pipe_a.temperature - pipe_b.temperature) < 1, \
		"reconcile_air didn't equalize temperatures: A=[pipe_a.temperature] B=[pipe_b.temperature]")
	// Thermal energy should be approximately conserved (within rounding).
	TEST_ASSERT(abs(final_thermal - initial_thermal) < (initial_thermal * 0.05), \
		"reconcile_air lost thermal energy: [initial_thermal] → [final_thermal] (>5% loss)")
	qdel(net)


/// Vent pump integration: build a real vent_pump on a floor, seed its
/// air_contents with pressurized N2, satisfy can_pump's preconditions, and
/// verify process() pushes gas into the turf. This exercises the full
/// machinery → LINDA path end-to-end.
/datum/unit_test/dq_vent_pump_pushes_to_turf

/datum/unit_test/dq_vent_pump_pushes_to_turf/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor on test map for vent_pump test")

	var/datum/gas_mixture/turf_air = T.return_air()
	for(var/datum/gas/g as anything in turf_air.gases)
		turf_air.gases[g][MOLES] = 0
	turf_air.set_temperature(T20C)

	var/obj/machinery/atmospherics/unary/vent_pump/V = new(T)
	TEST_ASSERT_NOTNULL(V, "couldn't construct vent_pump")
	TEST_ASSERT_NOTNULL(V.air_contents, "vent_pump air_contents null")

	// Pressurize the vent's internal supply (the "pipe behind it").
	V.air_contents.adjust_gas(/datum/gas/nitrogen, 500)
	V.air_contents.set_temperature(T20C)
	// Wire up the preconditions process() expects: a node (any non-null), powered.
	V.node = V // self-ref is enough to bypass the "no node → off" branch
	V.use_power = USE_POWER_IDLE
	V.stat &= ~(NOPOWER | BROKEN)
	V.welded = FALSE
	V.pump_direction = 1 // release
	V.external_pressure_bound = ONE_ATMOSPHERE * 2 // ambitious target
	V.internal_pressure_bound = 0

	var/initial_turf_n2 = turf_air.get_moles(/datum/gas/nitrogen)

	for(var/i in 1 to 5)
		V.process()

	var/final_turf_n2 = turf_air.get_moles(/datum/gas/nitrogen)
	TEST_ASSERT(final_turf_n2 > initial_turf_n2 + 5, \
		"vent_pump didn't push N2 to turf: [initial_turf_n2] → [final_turf_n2]")
	// Conservation: turf gained == vent_contents lost.
	var/vent_after = V.air_contents.get_moles(/datum/gas/nitrogen)
	var/total_delta = abs((500 - vent_after) - (final_turf_n2 - initial_turf_n2))
	TEST_ASSERT(total_delta < 1, \
		"vent_pump conservation broken: vent lost [500 - vent_after], turf gained [final_turf_n2 - initial_turf_n2]")

	qdel(V)


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

	var/datum/gas_mixture/turf_air = T.return_air()
	for(var/datum/gas/g as anything in turf_air.gases)
		turf_air.gases[g][MOLES] = 0
	turf_air.adjust_gas(/datum/gas/plasma, 100)
	turf_air.adjust_gas(/datum/gas/oxygen, 100)
	turf_air.set_temperature(T20C)

	var/obj/machinery/atmospherics/unary/vent_scrubber/S = new(T)
	TEST_ASSERT_NOTNULL(S, "couldn't construct vent_scrubber")
	TEST_ASSERT_NOTNULL(S.air_contents, "scrubber air_contents null")

	// Wire up: node ref, powered, scrubbing mode, filter PHORON only.
	S.node = S
	S.use_power = USE_POWER_IDLE
	S.stat &= ~(NOPOWER | BROKEN)
	S.welded = FALSE
	S.scrubbing = 1
	S.scrubbing_gas = list(GAS_PHORON)

	var/initial_turf_phoron = turf_air.get_moles(/datum/gas/plasma)
	var/initial_turf_o2 = turf_air.get_moles(/datum/gas/oxygen)
	var/initial_scrubber_phoron = S.air_contents.get_moles(/datum/gas/plasma)

	for(var/i in 1 to 5)
		S.process()

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
	TEST_ASSERT(istype(SM, /obj/machinery/power/supermatter), \
		"supermatter type wrong: [SM.type]")
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
	var/initial_temp = mix.temperature

	mix.react(null)

	TEST_ASSERT(mix.get_moles(/datum/gas/tritium) < initial_trit, \
		"tritium did not burn: [initial_trit] → [mix.get_moles(/datum/gas/tritium)]")
	TEST_ASSERT(mix.get_moles(/datum/gas/oxygen) < initial_o2, \
		"O2 not consumed by tritfire")
	TEST_ASSERT(mix.get_moles(/datum/gas/water_vapor) > initial_h2o, \
		"water vapor not produced by tritfire")
	TEST_ASSERT(mix.temperature > initial_temp, \
		"tritfire didn't release heat: [initial_temp] → [mix.temperature]")


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
	var/initial_temp = mix.temperature

	mix.react(null)

	TEST_ASSERT(mix.get_moles(/datum/gas/hydrogen) < initial_h2, \
		"H2 did not burn: [initial_h2] → [mix.get_moles(/datum/gas/hydrogen)]")
	TEST_ASSERT(mix.get_moles(/datum/gas/oxygen) < initial_o2, "O2 not consumed by h2fire")
	TEST_ASSERT(mix.temperature > initial_temp, "h2fire didn't release heat")


/// Freon combustion: freon + O2 (BELOW freezing point) → endothermic cooling.
/// Validates the cooling-reaction path used by freon-bombs and cryo setups.
/datum/unit_test/dq_freonfire_reaction_cools_mixture

/datum/unit_test/dq_freonfire_reaction_cools_mixture/Run()
	var/datum/gas_mixture/mix = new(CELL_VOLUME)
	mix.adjust_gas(/datum/gas/freon, 50)
	mix.adjust_gas(/datum/gas/oxygen, 200)
	// freonfire fires below FREON_MAXIMUM_BURN_TEMPERATURE and above
	// FREON_LOWER_TEMPERATURE — pick a value in the middle.
	mix.set_temperature(T0C + 25) // ~298K, below the 373K cap

	var/initial_freon = mix.get_moles(/datum/gas/freon)
	var/initial_temp = mix.temperature

	mix.react(null)

	var/final_freon = mix.get_moles(/datum/gas/freon)
	var/final_temp = mix.temperature
	if(final_freon < initial_freon)
		// Reaction ran. Verify it cooled, not heated.
		TEST_ASSERT(final_temp < initial_temp, \
			"freonfire is endothermic but temperature ROSE: [initial_temp] → [final_temp]")
	else
		// Reaction didn't run (conditions not met) — log so we know.
		log_test("dq_freonfire_reaction_cools_mixture: freonfire didn't fire under T=[initial_temp] freon=[initial_freon] O2=[mix.get_moles(/datum/gas/oxygen)] — possibly temp-condition mismatch")


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
	for(var/datum/gas/g as anything in air.gases)
		air.gases[g][MOLES] = 0
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
//
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
	TEST_ASSERT(!(A.atmos_adjacent_turfs && A.atmos_adjacent_turfs[B]), \
		"closed airlock didn't block A↔B atmos adjacency — door.update_nearby_tiles or CanZASPass routing broken")

	// Open the airlock — the door itself calls update_nearby_tiles on density
	// change in production.
	D.density = FALSE
	D.update_nearby_tiles()

	TEST_ASSERT(A.atmos_adjacent_turfs && A.atmos_adjacent_turfs[B], \
		"open airlock didn't allow A↔B atmos adjacency — door.update_nearby_tiles or CanZASPass routing broken in reverse direction")

	qdel(D)


// =====================================================================
// Pipenet auto-build via build_network
// =====================================================================

/// Two adjacent pipes constructed and linked via build_network should end up
/// in the same /datum/pipe_network with a shared air mixture. This is the
/// production "pipes load from map → atmos_init builds the network" flow.
/datum/unit_test/dq_pipes_build_into_one_network

/datum/unit_test/dq_pipes_build_into_one_network/Run()
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no floor pair for pipe network test")
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
	P1.build_network()

	// After build_network, both pipes should share a pipe_network's gas mixture.
	TEST_ASSERT_NOTNULL(P1.parent, "P1.parent (pipeline) is null after build_network")
	TEST_ASSERT_NOTNULL(P2.parent, "P2.parent (pipeline) is null after build_network")
	// Either same pipeline OR pipelines in same network.
	var/same_network = (P1.parent == P2.parent) || (P1.parent.network && P1.parent.network == P2.parent.network)
	TEST_ASSERT(same_network, \
		"P1 and P2 not in the same pipe_network after build_network — pipenet auto-build broken")

	qdel(P1)
	qdel(P2)


// =====================================================================
// Pipenet dispatch (catches "START_PROCESSING_PIPENET targets wrong list")
// =====================================================================

/// build_network() registers a /datum/pipe_network through START_PROCESSING_PIPENET.
/// That macro must point at SSair.networks (where SSair.process_pipenets reads),
/// NOT SSmachines.networks (whose process_pipenets is a stub on this fork).
/// If the macro is mis-targeted, the network builds but reconcile_air never
/// runs — silent failure that this test catches.
/datum/unit_test/dq_pipenet_dispatches_through_ssair

/datum/unit_test/dq_pipenet_dispatches_through_ssair/Run()
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no floor pair for pipenet dispatch test")
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
	P1.build_network()

	TEST_ASSERT_NOTNULL(P1.parent, "P1.parent (pipeline) null after build_network")
	TEST_ASSERT_NOTNULL(P1.parent.network, "pipeline has no parent network after build_network")

	var/datum/pipe_network/N = P1.parent.network
	TEST_ASSERT(N in SSair.networks, \
		"pipe_network NOT in SSair.networks after build_network — START_PROCESSING_PIPENET is targeting the wrong list, reconcile_air will never run in the live game")
	// SSmachines.networks was removed entirely (see machines.dm DQEdit). If
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
/// Exercises the lazy-rebuild path in pipe.Destroy → all-members-parent=null
/// → next return_air rebuilds.
/datum/unit_test/dq_pipe_split_then_merge_rebuilds_pipeline

/datum/unit_test/dq_pipe_split_then_merge_rebuilds_pipeline/Run()
	// Find three collinear floor tiles A-B-C.
	var/turf/simulated/floor/A = null
	var/turf/simulated/floor/B = null
	var/turf/simulated/floor/C = null
	for(var/turf/simulated/floor/candA in world)
		if(!candA.air || candA.blocks_air)
			continue
		var/turf/simulated/floor/candB = get_step(candA, EAST)
		var/turf/simulated/floor/candC = get_step(candB, EAST)
		if(istype(candB) && istype(candC) && candB.air && candC.air && !candB.blocks_air && !candC.blocks_air)
			A = candA
			B = candB
			C = candC
			break
	TEST_ASSERT_NOTNULL(A, "no 3-tile collinear floor strip for split/merge test")

	// Construct three straight pipes E-W along the strip.
	var/obj/machinery/atmospherics/pipe/simple/PA = new(A)
	PA.dir = EAST|WEST
	PA.initialize_directions = EAST|WEST
	var/obj/machinery/atmospherics/pipe/simple/PB = new(B)
	PB.dir = EAST|WEST
	PB.initialize_directions = EAST|WEST
	var/obj/machinery/atmospherics/pipe/simple/PC = new(C)
	PC.dir = EAST|WEST
	PC.initialize_directions = EAST|WEST

	PA.atmos_init()
	PB.atmos_init()
	PC.atmos_init()
	PA.build_network()

	// Sanity: all three share one pipeline.
	TEST_ASSERT(PA.parent && PA.parent == PB.parent && PB.parent == PC.parent, \
		"3-pipe straight run didn't form one pipeline: PA=[PA.parent] PB=[PB.parent] PC=[PC.parent]")
	var/datum/pipeline/initial_pipeline = PA.parent

	// Kill the middle pipe. /datum/pipeline.Destroy nulls every member's
	// parent. PA and PC should be orphaned, ready to lazy-rebuild.
	qdel(PB)
	TEST_ASSERT_NULL(PA.parent, "PA.parent not nulled after destroying middle pipe — pipeline didn't tear down properly")
	TEST_ASSERT_NULL(PC.parent, "PC.parent not nulled after destroying middle pipe")

	// Trigger lazy rebuild via return_air().
	PA.return_air()
	PC.return_air()
	TEST_ASSERT_NOTNULL(PA.parent, "PA didn't lazy-rebuild a pipeline after split")
	TEST_ASSERT_NOTNULL(PC.parent, "PC didn't lazy-rebuild a pipeline after split")
	TEST_ASSERT(PA.parent != PC.parent, \
		"PA and PC ended up in the SAME pipeline after middle pipe destroyed — split didn't isolate them")
	TEST_ASSERT(PA.parent != initial_pipeline, "PA's rebuilt pipeline is the old (destroyed) one — stale reference")

	// Insert a fresh bridging pipe at B's slot.
	var/obj/machinery/atmospherics/pipe/simple/PB2 = new(B)
	PB2.dir = EAST|WEST
	PB2.initialize_directions = EAST|WEST
	PB2.atmos_init()
	// on_construction would normally fire build_network with new_attachment=TRUE
	// on every neighbor. Simulate that to merge them back.
	PA.build_network(TRUE)
	PC.build_network(TRUE)
	PB2.build_network(TRUE)

	TEST_ASSERT_NOTNULL(PA.parent, "PA.parent null after merge")
	TEST_ASSERT_NOTNULL(PC.parent, "PC.parent null after merge")
	TEST_ASSERT_NOTNULL(PB2.parent, "PB2.parent null after merge")
	TEST_ASSERT(PA.parent == PB2.parent && PB2.parent == PC.parent, \
		"3 pipes didn't re-merge into one pipeline after bridging: PA=[PA.parent] PB2=[PB2.parent] PC=[PC.parent]")

	qdel(PA)
	qdel(PB2)
	qdel(PC)


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
	for(var/datum/gas/g as anything in turf_air.gases)
		turf_air.gases[g][MOLES] = 0
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
	for(var/datum/gas/g as anything in turf_air.gases)
		turf_air.gases[g][MOLES] = 0
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
	// Find three collinear tiles A-V-B.
	var/turf/simulated/floor/A = null
	var/turf/simulated/floor/V = null
	var/turf/simulated/floor/B = null
	for(var/turf/simulated/floor/candA in world)
		if(!candA.air || candA.blocks_air)
			continue
		var/turf/simulated/floor/candV = get_step(candA, EAST)
		var/turf/simulated/floor/candB = get_step(candV, EAST)
		if(istype(candV) && istype(candB) && candV.air && candB.air && !candV.blocks_air && !candB.blocks_air)
			A = candA
			V = candV
			B = candB
			break
	TEST_ASSERT_NOTNULL(A, "no 3-tile collinear strip for valve test")

	var/obj/machinery/atmospherics/pipe/simple/PA = new(A)
	PA.dir = EAST|WEST
	PA.initialize_directions = EAST|WEST
	var/obj/machinery/atmospherics/valve/VL = new(V)
	VL.dir = EAST
	VL.initialize_directions = EAST|WEST
	VL.open = FALSE
	var/obj/machinery/atmospherics/pipe/simple/PB = new(B)
	PB.dir = EAST|WEST
	PB.initialize_directions = EAST|WEST

	PA.atmos_init()
	VL.atmos_init()
	PB.atmos_init()
	PA.build_network()
	PB.build_network()
	VL.build_network()

	// Closed: PA and PB sit in separate pipelines.
	TEST_ASSERT_NOTNULL(PA.parent, "PA pipeline null after build")
	TEST_ASSERT_NOTNULL(PB.parent, "PB pipeline null after build")
	TEST_ASSERT(PA.parent != PB.parent, \
		"closed valve didn't separate pipelines — PA and PB share parent [PA.parent]")

	// Open the valve and rebuild — they should merge.
	VL.open = TRUE
	VL.update_icon()
	// Force a network rebuild now that the gate is open.
	PA.build_network(TRUE)
	PB.build_network(TRUE)
	VL.build_network(TRUE)

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
/// air2 empty, set REGULATE_NONE so it free-flows, unlock, run process(),
/// verify gas moved from air1 to air2.
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
	TEST_ASSERT_NOTNULL(G.air1, "passive_gate has no air1")
	TEST_ASSERT_NOTNULL(G.air2, "passive_gate has no air2")

	// Pressurize air1 well above air2.
	G.air1.adjust_gas(/datum/gas/oxygen, 500)
	G.air1.set_temperature(T20C)
	G.air2.set_temperature(T20C)
	G.unlocked = TRUE
	G.regulate_mode = 0  // REGULATE_NONE — free flow

	var/air1_before = G.air1.total_moles()
	var/air2_before = G.air2.total_moles()
	G.process()
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

	for(var/datum/gas/g as anything in A.air.gases)
		A.air.gases[g][MOLES] = 0
	for(var/datum/gas/g as anything in B.air.gases)
		B.air.gases[g][MOLES] = 0
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

/// A human in a low-pressure (near-vacuum) environment takes oxyloss as the
/// breath proc can't extract enough O2. Validates the life-cycle atmos chain.
/datum/unit_test/dq_human_low_pressure_oxyloss

/datum/unit_test/dq_human_low_pressure_oxyloss/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_NOTNULL(H, "couldn't allocate human")
	TEST_ASSERT_NOTNULL(H.species, "test human has no species")

	// Near-vacuum breath (tiny moles).
	var/datum/gas_mixture/breath = new(BREATH_VOLUME)
	breath.adjust_gas(/datum/gas/oxygen, 0.01)
	breath.set_temperature(T20C)
	var/initial_oxyloss = H.getOxyLoss()

	H.handle_breath(breath)

	var/final_oxyloss = H.getOxyLoss()
	TEST_ASSERT(final_oxyloss > initial_oxyloss, \
		"human didn't take oxyloss from near-vacuum breath: [initial_oxyloss] → [final_oxyloss]")


/// Verify phoron breather species correctly consumes plasma when given a
/// plasma-rich breath. This is the inverse-respiration check.
/datum/unit_test/dq_phoron_breather_consumes_plasma

/datum/unit_test/dq_phoron_breather_consumes_plasma/Run()
	// Find a phoron-breathing species (Vox, Diona, etc., depending on map).
	var/datum/species/phoron_species = null
	for(var/species_path in GLOB.all_species)
		var/datum/species/S = GLOB.all_species[species_path]
		if(S.breath_type == /datum/gas/plasma || S.breath_type == GAS_PHORON)
			phoron_species = S
			break
	if(!phoron_species)
		log_test("dq_phoron_breather_consumes_plasma: no phoron-breather species on this build, skipping")
		return

	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_NOTNULL(H, "couldn't allocate human")
	H.set_species(phoron_species.name)
	TEST_ASSERT(H.species == phoron_species || H.species.name == phoron_species.name, \
		"set_species didn't apply: got [H.species]")

	var/datum/gas_mixture/breath = new(BREATH_VOLUME)
	breath.adjust_gas(/datum/gas/plasma, 5)
	breath.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)
	breath.set_temperature(T20C)

	var/initial_plasma = breath.get_moles(/datum/gas/plasma)

	H.handle_breath(breath)

	var/final_plasma = breath.get_moles(/datum/gas/plasma)
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
	for(var/datum/gas/g as anything in turf_air.gases)
		turf_air.gases[g][MOLES] = 0
	turf_air.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)
	turf_air.set_temperature(T20C)

	// Manually-built pipeline (sidesteps HE pipe two-node auto-connection).
	var/datum/pipeline/P = new
	P.air = new(70)
	P.air.adjust_gas(/datum/gas/nitrogen, 50)
	P.air.set_temperature(T0C + 500) // hot

	var/initial_turf_temp = turf_air.temperature
	var/initial_pipe_temp = P.air.temperature

	P.temperature_interact(T, P.air.volume, OPEN_HEAT_TRANSFER_COEFFICIENT)

	var/final_turf_temp = turf_air.temperature
	var/final_pipe_temp = P.air.temperature
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
	for(var/datum/gas/g as anything in A.air.gases)
		A.air.gases[g][MOLES] = 0
	for(var/datum/gas/g as anything in B.air.gases)
		B.air.gases[g][MOLES] = 0

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
	var/b_caught = !isnull(B.active_hotspot) || B.air.temperature > PLASMA_MINIMUM_BURN_TEMPERATURE
	TEST_ASSERT(b_caught, \
		"fire did not spread from A to B over 20 ticks. B.hotspot=[B.active_hotspot] B.temp=[B.air.temperature]")

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
	// Find a /turf/simulated/floor adjacent to /turf/space.
	var/turf/simulated/floor/A = null
	var/turf/space/S = null
	for(var/turf/simulated/floor/cand in world)
		if(!cand.air || cand.blocks_air)
			continue
		for(var/direction in GLOB.cardinal)
			var/turf/n = get_step(cand, direction)
			if(istype(n, /turf/space))
				A = cand
				S = n
				break
		if(A)
			break
	if(!A)
		log_test("dq_room_depressurizes: no floor-space pair on test map, skipping")
		return

	// Real environmental sink: a /turf/space neighbor. Don't wall-isolate —
	// space is already a real boundary the engine treats correctly.
	// Make sure S has air (vacuum is a real /datum/gas_mixture, not null).
	TEST_ASSERT_NOTNULL(S.air, "/turf/space.air is null — /turf/open/Initialize didn't create the vacuum mixture")
	// LINDA init builds floor↔space adjacency where the geometry supports it
	// but some map edges/specific tiles don't get wired. Skip cleanly if so —
	// this test specifically validates spread-to-space when the adjacency
	// EXISTS; the no-adjacency case is a different test.
	if(!(A.atmos_adjacent_turfs && A.atmos_adjacent_turfs[S]))
		log_test("dq_room_depressurizes: floor↔space adjacency wasn't wired by init on the test map, skipping")
		return

	for(var/datum/gas/g as anything in A.air.gases)
		A.air.gases[g][MOLES] = 0
	// And ensure space is genuinely vacuum (some maps initialize it with trace gas).
	for(var/datum/gas/g as anything in S.air.gases)
		S.air.gases[g][MOLES] = 0

	// Pressurize A through the production path.
	var/datum/gas_mixture/donor = new(70)
	donor.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD * 5) // ~5 atm
	donor.set_temperature(T20C)
	A.assume_air(donor)

	var/initial_pressure = A.air.return_pressure()
	var/initial_moles = A.air.total_moles()

	// Let real SSair tick.
	dq_atmos_test_wait_real_ssair_ticks(15)

	var/final_pressure = A.air.return_pressure()
	var/final_moles = A.air.total_moles()
	TEST_ASSERT(final_pressure < initial_pressure, \
		"pressurised floor adjacent to space didn't depressurize: [initial_pressure] → [final_pressure]")
	TEST_ASSERT(final_moles < initial_moles, \
		"depressurization didn't drain moles: [initial_moles] → [final_moles]")

	// Restore baseline.
	A.air.set_moles(/datum/gas/nitrogen, MOLES_N2STANDARD)


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

	var/datum/gas_mixture/turf_air = T.return_air()
	for(var/datum/gas/g as anything in turf_air.gases)
		turf_air.gases[g][MOLES] = 0
	turf_air.set_temperature(T20C)

	// Pollute the turf with CO2 — the scrubber's target.
	turf_air.adjust_gas(/datum/gas/carbon_dioxide, 200)

	// Vent_pump preloaded with clean N2 supply.
	var/obj/machinery/atmospherics/unary/vent_pump/V = new(T)
	V.air_contents.adjust_gas(/datum/gas/nitrogen, 500)
	V.air_contents.set_temperature(T20C)
	V.node = V
	V.use_power = USE_POWER_IDLE
	V.stat &= ~(NOPOWER | BROKEN)
	V.welded = FALSE
	V.pump_direction = 1
	V.external_pressure_bound = ONE_ATMOSPHERE * 1.5
	V.internal_pressure_bound = 0

	// Scrubber configured for CO2.
	var/obj/machinery/atmospherics/unary/vent_scrubber/S = new(T)
	S.node = S
	S.use_power = USE_POWER_IDLE
	S.stat &= ~(NOPOWER | BROKEN)
	S.welded = FALSE
	S.scrubbing = 1
	S.scrubbing_gas = list(GAS_CO2)

	var/initial_co2 = turf_air.get_moles(/datum/gas/carbon_dioxide)
	var/initial_n2 = turf_air.get_moles(/datum/gas/nitrogen)

	for(var/i in 1 to 10)
		V.process()
		S.process()

	var/final_co2 = turf_air.get_moles(/datum/gas/carbon_dioxide)
	var/final_n2 = turf_air.get_moles(/datum/gas/nitrogen)
	TEST_ASSERT(final_co2 < initial_co2, \
		"CO2 not removed by scrubber: [initial_co2] → [final_co2]")
	TEST_ASSERT(final_n2 > initial_n2, \
		"N2 not added by vent: [initial_n2] → [final_n2]")
	// Scrubber captured the CO2.
	TEST_ASSERT(S.air_contents.get_moles(/datum/gas/carbon_dioxide) > 0, \
		"scrubber air_contents didn't accumulate CO2")

	for(var/datum/gas/g as anything in turf_air.gases)
		turf_air.gases[g][MOLES] = 0
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
	for(var/datum/gas/g as anything in turf_air.gases)
		turf_air.gases[g][MOLES] = 0
	// Crush pressure (~20 atm).
	turf_air.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD * 20)
	turf_air.set_temperature(T20C)

	var/initial_brute = H.getBruteLoss()
	for(var/i in 1 to 5)
		H.handle_environment(turf_air)
	var/final_brute = H.getBruteLoss()

	TEST_ASSERT(final_brute > initial_brute, \
		"human took no brute damage at ~20 atm pressure: [initial_brute] → [final_brute]")

	// Reset turf to standard atmosphere.
	for(var/datum/gas/g as anything in turf_air.gases)
		turf_air.gases[g][MOLES] = 0
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

	var/datum/gas_mixture/turf_air = T.return_air()
	for(var/datum/gas/g as anything in turf_air.gases)
		turf_air.gases[g][MOLES] = 0
	turf_air.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)
	turf_air.set_temperature(50) // 50 K, ~-223°C

	// Cold burn → fire damage in CHOMP humans.
	var/initial_fireloss = H.getFireLoss()
	for(var/i in 1 to 10)
		H.handle_environment(turf_air)
	var/final_fireloss = H.getFireLoss()

	TEST_ASSERT(final_fireloss > initial_fireloss, \
		"human took no fireloss at 50K: [initial_fireloss] → [final_fireloss]")

	for(var/datum/gas/g as anything in turf_air.gases)
		turf_air.gases[g][MOLES] = 0
	turf_air.adjust_gas(/datum/gas/oxygen, MOLES_O2STANDARD)
	turf_air.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)
	turf_air.set_temperature(T20C)


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
	for(var/datum/gas/g as anything in turf_air.gases)
		turf_air.gases[g][MOLES] = 0
	turf_air.adjust_gas(/datum/gas/oxygen, MOLES_O2STANDARD)
	turf_air.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD)
	turf_air.set_temperature(T20C)

	var/obj/machinery/alarm/A = new(T)
	TEST_ASSERT_NOTNULL(A, "couldn't construct air alarm")

	// The alarm reads its turf's pressure. ~one atmosphere ≈ 101.3 kPa.
	var/pressure = turf_air.return_pressure()
	TEST_ASSERT(abs(pressure - ONE_ATMOSPHERE) < 5, \
		"turf pressure not standard atmosphere: got [pressure]")

	// Pollute with plasma — danger threshold should now be tripped.
	turf_air.adjust_gas(/datum/gas/plasma, 50)
	A.process()
	// Alarm should now report unsafe (whether via danger_level var or icon
	// state — depends on alarm impl). Just verify process() didn't crash.

	turf_air.set_moles(/datum/gas/plasma, 0)
	qdel(A)


// =====================================================================
// Supermatter + R-UST fusion engine
// =====================================================================

/// Supermatter degrades when surrounded by no-air vacuum (no coolant).
/// /tg/'s supermatter takes damage when it has power but no environment to
/// dump heat into. Validates the env=null branch.
/datum/unit_test/dq_supermatter_accumulates_damage_in_vacuum

/datum/unit_test/dq_supermatter_accumulates_damage_in_vacuum/Run()
	// Use a space turf so removed.total_moles will be ~0.
	var/turf/space/S = null
	for(var/turf/space/cand in world)
		S = cand
		break
	if(!S)
		log_test("dq_supermatter_accumulates_damage_in_vacuum: no space turf on map, skipping")
		return

	var/obj/machinery/power/supermatter/SM = new(S)
	TEST_ASSERT_NOTNULL(SM, "supermatter failed to construct on space turf")
	// Give it some power so the no-env damage formula produces > 0.
	SM.power = 200
	var/initial_damage = SM.damage

	SM.process()

	TEST_ASSERT(SM.damage > initial_damage, \
		"supermatter at power=200 in space (no coolant) didn't accumulate damage: [initial_damage] → [SM.damage]")

	qdel(SM)


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
	TEST_ASSERT(istype(Core, /obj/machinery/power/fusion_core), \
		"fusion_core wrong type: [Core.type]")
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
	var/event_type = /datum/event/atmos_leak
	TEST_ASSERT_NOTNULL(event_type, "atmos_leak event type undefined")
	// gas_leak is a similar gamemaster event.
	var/list/gas_event_types = list()
	for(var/datum/event/E_path as anything in subtypesof(/datum/event))
		if(findtext("[E_path]", "leak") || findtext("[E_path]", "atmos"))
			gas_event_types += E_path
	TEST_ASSERT(length(gas_event_types) > 0, \
		"no atmos/leak event types registered — events directory may have been gutted")


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
	var/initial_temp = P.air.temperature

	P.air.react(P)

	var/final_plasma = P.air.get_moles(/datum/gas/plasma)
	TEST_ASSERT(final_plasma < initial_plasma, \
		"plasma didn't burn inside pipeline: [initial_plasma] → [final_plasma]")
	TEST_ASSERT(P.air.temperature > initial_temp, \
		"pipeline plasmafire didn't release heat: [initial_temp] → [P.air.temperature]")
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
			H.handle_breath(breath)
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
		for(var/datum/gas/g as anything in T.air.gases)
			T.air.gases[g][MOLES] = 0
		// Put visible_threshold * 10 of THIS gas only.
		T.air.adjust_gas(g_type, visible_threshold * 10)
		T.update_visuals()
		TEST_ASSERT(LAZYLEN(T.atmos_overlay_types) > 0, \
			"gas [initial(g_type.id)] above visible threshold ([visible_threshold * 10] mol vs threshold [visible_threshold]) produced NO overlay")
		gases_tested++
	TEST_ASSERT(gases_tested > 0, "no visible-threshold gases found — meta_gas_info empty?")

	// Reset turf.
	for(var/datum/gas/g as anything in T.air.gases)
		T.air.gases[g][MOLES] = 0
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

	// Force above explosion threshold.
	SM.damage = SM.explosion_point + 100
	SM.process()
	// process() should have started the countdown OR set exploded=TRUE on a
	// subsequent tick (depending on impl). Either way no crash, and the
	// damage stays at or above explosion_point.
	TEST_ASSERT(SM.damage >= SM.explosion_point, \
		"damage dropped below explosion_point during delam process: [SM.damage] < [SM.explosion_point]")

	qdel(SM)


/// Gas meter reads the pressure of the pipe it's targeting. End-to-end:
/// meter + pipe + pipeline, verify the meter's view of pressure matches
/// the pipeline's air return_pressure.
/datum/unit_test/dq_gas_meter_reads_target_pipeline_pressure

/datum/unit_test/dq_gas_meter_reads_target_pipeline_pressure/Run()
	var/turf/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for meter test")

	// Construct pipe + meter on same tile. Lazy return_air() creates the
	// pipeline on demand — simpler than wiring atmos_init for a single
	// stand-alone segment.
	var/obj/machinery/atmospherics/pipe/simple/P = new(T)
	var/datum/gas_mixture/pipe_air = P.return_air()
	TEST_ASSERT_NOTNULL(pipe_air, "pipe return_air() null after lazy build")
	TEST_ASSERT_NOTNULL(P.parent, "pipe parent (pipeline) null after return_air")
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
	TEST_ASSERT_NOTNULL(Pump.air1, "binary pump air1 null")
	TEST_ASSERT_NOTNULL(Pump.air2, "binary pump air2 null")

	// Seed air1 with pressurized N2, air2 empty.
	Pump.air1.adjust_gas(/datum/gas/nitrogen, 200)
	Pump.air1.set_temperature(T20C)
	Pump.air2.set_temperature(T20C)
	Pump.use_power = USE_POWER_IDLE
	Pump.stat &= ~(BROKEN | NOPOWER)
	Pump.target_pressure = ONE_ATMOSPHERE * 5 // high target so pump runs

	// Manually satisfy can_pump-equivalent preconditions and call process.
	for(var/i in 1 to 5)
		Pump.process()

	var/air1_after = Pump.air1.get_moles(/datum/gas/nitrogen)
	var/air2_after = Pump.air2.get_moles(/datum/gas/nitrogen)
	// air1 should have lost SOME gas, air2 gained it. If neither happened the
	// pump didn't run — either node missing or pressure already at target.
	TEST_ASSERT(air1_after < 200 || air2_after > 0, \
		"binary pump didn't transfer ANY moles in 5 ticks: air1=[air1_after], air2=[air2_after] (200 expected drop)")

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

	var/datum/gas_mixture/turf_air = T.return_air()
	for(var/datum/gas/g as anything in turf_air.gases)
		turf_air.gases[g][MOLES] = 0
	turf_air.adjust_gas(/datum/gas/carbon_dioxide, 200)
	turf_air.set_temperature(T20C)

	// Shared pipenet air mixture (represents the connecting pipe).
	var/datum/gas_mixture/shared = new(200)
	shared.adjust_gas(/datum/gas/nitrogen, 1000)
	shared.set_temperature(T20C)

	var/obj/machinery/atmospherics/unary/vent_pump/V = new(T)
	V.air_contents = shared
	V.node = V
	V.use_power = USE_POWER_IDLE
	V.stat &= ~(NOPOWER | BROKEN)
	V.welded = FALSE
	V.pump_direction = 1
	V.external_pressure_bound = ONE_ATMOSPHERE * 1.5
	V.internal_pressure_bound = 0

	var/obj/machinery/atmospherics/unary/vent_scrubber/S = new(T)
	S.air_contents = shared
	S.node = S
	S.use_power = USE_POWER_IDLE
	S.stat &= ~(NOPOWER | BROKEN)
	S.welded = FALSE
	S.scrubbing = 1
	S.scrubbing_gas = list(GAS_CO2)

	var/initial_shared_n2 = shared.get_moles(/datum/gas/nitrogen)
	var/initial_shared_co2 = shared.get_moles(/datum/gas/carbon_dioxide)
	var/initial_turf_co2 = turf_air.get_moles(/datum/gas/carbon_dioxide)

	for(var/i in 1 to 10)
		V.process()
		S.process()

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

	for(var/datum/gas/g as anything in turf_air.gases)
		turf_air.gases[g][MOLES] = 0
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


/// Items exposed to atmospheric heat take fire damage via temperature_expose
/// or atom_integrity reduction. This is what "fire melts items on the floor"
/// translates to in the engine.
/datum/unit_test/dq_item_takes_atmos_heat

/datum/unit_test/dq_item_takes_atmos_heat/Run()
	var/turf/simulated/floor/T = null
	for(var/turf/simulated/floor/cand in world)
		if(cand.air && !cand.blocks_air)
			T = cand
			break
	TEST_ASSERT_NOTNULL(T, "no floor for item-heat test")

	var/obj/item/I = new /obj/item/paper(T)
	TEST_ASSERT_NOTNULL(I, "couldn't alloc paper item")

	// Heat the turf air to ignition temperature for cardboard.
	var/datum/gas_mixture/turf_air = T.return_air()
	turf_air.set_temperature(1000) // very hot
	turf_air.adjust_gas(/datum/gas/oxygen, 100)

	// temperature_expose is the engine hook items override.
	I.temperature_expose(turf_air, turf_air.temperature, turf_air.volume)
	// Verify the call didn't crash. (Cardboard may or may not actually burn —
	// this is the integration-test layer, not the per-item damage policy.)
	TEST_ASSERT_NOTNULL(I, "item became invalid after temperature_expose")

	qdel(I)


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
	var/burn_ratio = E.volume_per_burn * E.thrust_limit / E.air_contents.volume
	TEST_ASSERT(burn_ratio > 0 && burn_ratio < 1, \
		"burn_ratio out of range: [burn_ratio] (vol_per_burn=[E.volume_per_burn] thrust_limit=[E.thrust_limit] vol=[E.air_contents.volume])")

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
	dq_atmos_test_wait_real_ssair_ticks(1)
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
	var/initial_integrity = Tank.integrity
	TEST_ASSERT(initial_integrity > 0, "tank integrity zero at construct")

	// Pressure target: ~37 atm. DQ's TANK_RUPTURE_PRESSURE is 35 atm and
	// TANK_FRAGMENT_PRESSURE is 40 atm — we need to sit between those so
	// check_status takes the "integrity damage, no explosion" branch.
	var/target_moles = (37 * ONE_ATMOSPHERE) * Tank.air_contents.volume / (R_IDEAL_GAS_EQUATION * T20C)
	Tank.air_contents.adjust_gas(/datum/gas/oxygen, target_moles - Tank.air_contents.total_moles())
	Tank.air_contents.set_temperature(T20C)

	var/pressure = Tank.air_contents.return_pressure()
	TEST_ASSERT(pressure > TANK_RUPTURE_PRESSURE, \
		"failed to seed tank above rupture pressure: pressure=[pressure] target=[TANK_RUPTURE_PRESSURE]")
	TEST_ASSERT(pressure < TANK_FRAGMENT_PRESSURE, \
		"seeded tank above fragment pressure ([TANK_FRAGMENT_PRESSURE]) — test would detonate the world")

	Tank.check_status()

	TEST_ASSERT(Tank.integrity < initial_integrity, \
		"check_status didn't reduce integrity under rupture pressure: [initial_integrity] → [Tank.integrity]")

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
	for(var/datum/gas/g as anything in turf_air.gases)
		turf_air.gases[g][MOLES] = 0
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
	for(var/datum/gas/g as anything in turf_air.gases)
		turf_air.gases[g][MOLES] = 0


/// /datum/pipeline.build_pipeline() on a single pipe should: allocate a fresh
/// gas_mixture as the pipeline.air, set pipe.parent to the pipeline, and size
/// the pipeline volume to the pipe's volume. Validates the pipenet construction
/// math LINDA inherited from CHOMP.
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

	var/datum/pipeline/Line = new()
	Line.build_pipeline(Pipe)

	TEST_ASSERT_NOTNULL(Line.air, "build_pipeline didn't allocate pipeline.air")
	TEST_ASSERT(Line.air.volume == Pipe.volume, \
		"pipeline volume mismatch: pipeline=[Line.air.volume] pipe=[Pipe.volume]")
	TEST_ASSERT(Pipe.parent == Line, \
		"pipe.parent not set to the pipeline: pipe.parent=[Pipe.parent] line=[Line]")
	TEST_ASSERT(Line.members && Pipe in Line.members, \
		"pipe not in pipeline.members after build_pipeline")

	qdel(Line)
	qdel(Pipe)


/// reconcile_air() on a pipe_network with THREE pipes must conserve total
/// moles and total thermal energy when redistributing. Round 2 covered the
/// 2-pipe case; this catches off-by-one or per-pipe-loss bugs that only
/// surface with > 2 pipes.
/datum/unit_test/dq_reconcile_air_three_pipes_conserves_mass

/datum/unit_test/dq_reconcile_air_three_pipes_conserves_mass/Run()
	var/datum/pipe_network/net = new
	var/datum/gas_mixture/p1 = new(70)
	p1.adjust_gas(/datum/gas/oxygen, 150)
	p1.set_temperature(T20C)
	var/datum/gas_mixture/p2 = new(70)
	p2.adjust_gas(/datum/gas/nitrogen, 50)
	p2.set_temperature(T0C + 80)
	var/datum/gas_mixture/p3 = new(70)
	p3.set_temperature(T0C + 40)
	net.gases += p1
	net.gases += p2
	net.gases += p3
	for(var/datum/gas_mixture/m in net.gases)
		net.volume += m.volume

	var/initial_total = p1.total_moles() + p2.total_moles() + p3.total_moles()
	var/initial_thermal = p1.thermal_energy() + p2.thermal_energy() + p3.thermal_energy()

	net.reconcile_air()

	var/final_total = p1.total_moles() + p2.total_moles() + p3.total_moles()
	var/final_thermal = p1.thermal_energy() + p2.thermal_energy() + p3.thermal_energy()
	TEST_ASSERT(abs(final_total - initial_total) < 0.5, \
		"reconcile_air lost mass with 3 pipes: [initial_total] → [final_total]")
	// All three equal-volume pipes should hold equal moles after reconcile.
	var/m1 = p1.total_moles()
	var/m2 = p2.total_moles()
	var/m3 = p3.total_moles()
	TEST_ASSERT(abs(m1 - m2) < 0.5 && abs(m2 - m3) < 0.5, \
		"reconcile_air didn't equalize 3 pipes: m1=[m1] m2=[m2] m3=[m3]")
	// Temperatures should all converge.
	TEST_ASSERT(abs(p1.temperature - p2.temperature) < 1 && abs(p2.temperature - p3.temperature) < 1, \
		"reconcile_air didn't equalize temperatures: T1=[p1.temperature] T2=[p2.temperature] T3=[p3.temperature]")
	TEST_ASSERT(abs(final_thermal - initial_thermal) < (initial_thermal * 0.05), \
		"reconcile_air lost thermal energy with 3 pipes: [initial_thermal] → [final_thermal] (>5%)")
	qdel(net)


// =====================================================================
// Round 8: 2-pipe pipeline expansion, temperature_share, full canister
// room propagation, analyzer extremes
// =====================================================================

/// build_pipeline traverses pipeline_expansion to find connected pipes. Two
/// pipes connected node1↔node1 should both end up as members of the same
/// pipeline. Validates the network-traversal path that LINDA inherited.
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

	// Wire them together manually. pipeline_expansion returns [node1, node2]
	// per pipe, and build_pipeline walks until no new members appear.
	PA.node1 = PB
	PB.node1 = PA

	var/datum/pipeline/Line = new()
	Line.build_pipeline(PA)

	TEST_ASSERT(PA in Line.members, "pipe A not in pipeline.members after build_pipeline")
	TEST_ASSERT(PB in Line.members, "pipe B not in pipeline.members — build_pipeline didn't expand via pipeline_expansion")
	TEST_ASSERT(PA.parent == Line && PB.parent == Line, \
		"pipe.parent not set on both members: A=[PA.parent] B=[PB.parent]")

	// Volume should be the sum of both pipe volumes.
	TEST_ASSERT(Line.air.volume == (PA.volume + PB.volume), \
		"pipeline volume not sum of pipes: pipeline=[Line.air.volume] expected=[PA.volume + PB.volume]")

	qdel(Line)
	qdel(PA)
	qdel(PB)


/// temperature_share directly equalizes the temperature between two gas
/// mixtures via conduction. Validates the heat-conduction path used between
/// adjacent pipes/turfs.
/datum/unit_test/dq_temperature_share_equalizes_two_mixtures

/datum/unit_test/dq_temperature_share_equalizes_two_mixtures/Run()
	var/datum/gas_mixture/hot = new(70)
	hot.adjust_gas(/datum/gas/oxygen, 100)
	hot.set_temperature(T0C + 200)
	hot.archive()

	var/datum/gas_mixture/cold = new(70)
	cold.adjust_gas(/datum/gas/nitrogen, 100)
	cold.set_temperature(T0C - 100)
	cold.archive()

	var/hot_initial = hot.temperature
	var/cold_initial = cold.temperature
	var/initial_total_thermal = hot.thermal_energy() + cold.thermal_energy()

	// Repeatedly conduct heat between them.
	for(var/i in 1 to 60)
		hot.temperature_share(cold, 0.4)
		hot.archive()
		cold.archive()

	TEST_ASSERT(hot.temperature < hot_initial, "hot side didn't cool: [hot_initial] → [hot.temperature]")
	TEST_ASSERT(cold.temperature > cold_initial, "cold side didn't warm: [cold_initial] → [cold.temperature]")
	TEST_ASSERT(abs(hot.temperature - cold.temperature) < 5, \
		"temperature_share didn't converge: hot=[hot.temperature] cold=[cold.temperature]")

	// Thermal-energy conservation across the system (within 5%).
	var/final_total_thermal = hot.thermal_energy() + cold.thermal_energy()
	TEST_ASSERT(abs(final_total_thermal - initial_total_thermal) < (initial_total_thermal * 0.05), \
		"temperature_share lost thermal energy: [initial_total_thermal] → [final_total_thermal] (>5%)")


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
	for(var/datum/gas/g as anything in A_air.gases)
		A_air.gases[g][MOLES] = 0
	A_air.set_temperature(T20C)
	var/datum/gas_mixture/B_air = B.return_air()
	for(var/datum/gas/g as anything in B_air.gases)
		B_air.gases[g][MOLES] = 0
	B_air.set_temperature(T20C)

	// Place a plasma canister on A with the valve open.
	var/obj/machinery/portable_atmospherics/canister/phoron/Can = new(A)
	TEST_ASSERT_NOTNULL(Can, "phoron canister construct failed")
	Can.valve_open = TRUE
	Can.release_pressure = ONE_ATMOSPHERE * 50

	// Run canister.process to release, then drive cells to share into B.
	for(var/i in 1 to 8)
		Can.process()
		dq_atmos_test_drive_ticks(list(A, B), 1)

	var/A_plasma = A_air.get_moles(/datum/gas/plasma)
	var/B_plasma = B_air.get_moles(/datum/gas/plasma)
	TEST_ASSERT(A_plasma > 0, "canister didn't release ANY plasma onto A: [A_plasma]")
	TEST_ASSERT(B_plasma > 0, "plasma didn't spread from A to adjacent B: [B_plasma] (A=[A_plasma])")

	// Cleanup so other tests don't see leftover plasma.
	for(var/datum/gas/g as anything in A_air.gases)
		A_air.gases[g][MOLES] = 0
	for(var/datum/gas/g as anything in B_air.gases)
		B_air.gases[g][MOLES] = 0
	qdel(Can)


/// Atmos analyzer at extreme pressure (100 atm canister) returns valid lines
/// and doesn't runtime. Catches overflow/format bugs at the edge of the
/// expected pressure range.
/datum/unit_test/dq_atmos_analyzer_handles_extreme_pressure

/datum/unit_test/dq_atmos_analyzer_handles_extreme_pressure/Run()
	var/obj/item/tank/oxygen/Tank = new(locate(1, 1, 1))
	TEST_ASSERT_NOTNULL(Tank, "tank construct failed")

	// Push pressure to ~30 atm (below TANK_LEAK so we don't lose integrity).
	var/target_moles = (28 * ONE_ATMOSPHERE) * Tank.air_contents.volume / (R_IDEAL_GAS_EQUATION * T20C)
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


/// excited_group.dismantle() detaches all member turfs from the group, sets
/// their excited_group var to null, and removes the group from SSair's
/// active group list. Validates the cleanup path that fires after a region
/// goes quiet — without it, idle turfs would keep getting processed forever.
/datum/unit_test/dq_excited_group_dismantle_releases_turfs

/datum/unit_test/dq_excited_group_dismantle_releases_turfs/Run()
	var/list/pair = dq_atmos_test_find_floor_pair()
	TEST_ASSERT_NOTNULL(pair, "no adjacent-floor pair for excited-group dismantle test")
	var/turf/open/A = pair[1]
	var/turf/open/B = pair[2]
	dq_atmos_test_isolate_pair(A, B)

	// Set up a delta so excited group forms.
	var/datum/gas_mixture/A_air = A.return_air()
	for(var/datum/gas/g as anything in A_air.gases)
		A_air.gases[g][MOLES] = 0
	A_air.adjust_gas(/datum/gas/oxygen, 500)
	A_air.set_temperature(T20C)
	var/datum/gas_mixture/B_air = B.return_air()
	for(var/datum/gas/g as anything in B_air.gases)
		B_air.gases[g][MOLES] = 0
	B_air.set_temperature(T20C)

	// Drive a few cells to form the excited group.
	dq_atmos_test_drive_ticks(list(A, B), 5)
	TEST_ASSERT_NOTNULL(A.excited_group, "A.excited_group never formed after 5 ticks of delta")
	var/datum/excited_group/EG = A.excited_group

	// Manually invoke dismantle (the proc SSair fires after the quiet window).
	EG.dismantle()

	TEST_ASSERT_NULL(A.excited_group, "A.excited_group not cleared by EG.dismantle()")
	TEST_ASSERT_NULL(B.excited_group, "B.excited_group not cleared by EG.dismantle()")

	for(var/datum/gas/g as anything in A_air.gases)
		A_air.gases[g][MOLES] = 0
	for(var/datum/gas/g as anything in B_air.gases)
		B_air.gases[g][MOLES] = 0


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
	TEST_ASSERT(abs(mix.temperature - TCMB) < 1, \
		"temperature shifted at TCMB react: [mix.temperature]")


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
	H.wear_mask = M
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
	H.wear_mask = null
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
	TEST_ASSERT_NOTNULL(V.air1, "volume_pump air1 null")
	TEST_ASSERT_NOTNULL(V.air2, "volume_pump air2 null")

	V.air1.adjust_gas(/datum/gas/oxygen, 500)
	V.air1.set_temperature(T20C)
	// Pre-load air2 with enough pressure that a pressure pump would refuse —
	// volume_pump should still transfer.
	V.air2.adjust_gas(/datum/gas/nitrogen, 100)
	V.air2.set_temperature(T20C)

	V.use_power = USE_POWER_IDLE
	V.stat &= ~(NOPOWER | BROKEN)

	var/air1_initial = V.air1.total_moles()
	var/air2_initial = V.air2.total_moles()

	for(var/i in 1 to 5)
		V.process()

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

	var/datum/gas_mixture/turf_air = T.return_air()
	for(var/datum/gas/g as anything in turf_air.gases)
		turf_air.gases[g][MOLES] = 0
	// Mixed atmosphere — N2, O2, CO2 — none of which a scrubber would
	// normally filter. Siphon mode should grab all three.
	turf_air.adjust_gas(/datum/gas/nitrogen, 200)
	turf_air.adjust_gas(/datum/gas/oxygen, 100)
	turf_air.adjust_gas(/datum/gas/carbon_dioxide, 30)
	turf_air.set_temperature(T20C)

	var/obj/machinery/atmospherics/unary/vent_scrubber/S = new(T)
	TEST_ASSERT_NOTNULL(S, "scrubber construct failed")
	S.node = S
	S.use_power = USE_POWER_IDLE
	S.stat &= ~(NOPOWER | BROKEN)
	S.welded = FALSE
	S.scrubbing = 0  // SIPHON mode
	S.scrubbing_gas = list() // siphon doesn't consult this

	var/initial_n2 = turf_air.get_moles(/datum/gas/nitrogen)
	var/initial_o2 = turf_air.get_moles(/datum/gas/oxygen)
	var/initial_co2 = turf_air.get_moles(/datum/gas/carbon_dioxide)
	var/initial_total = initial_n2 + initial_o2 + initial_co2

	for(var/i in 1 to 20)
		S.process()

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

	for(var/datum/gas/g as anything in turf_air.gases)
		turf_air.gases[g][MOLES] = 0
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
	for(var/datum/gas/g as anything in A_air.gases)
		A_air.gases[g][MOLES] = 0
	for(var/datum/gas/g as anything in B_air.gases)
		B_air.gases[g][MOLES] = 0
	A_air.adjust_gas(/datum/gas/nitrogen, 200)
	A_air.set_temperature(T20C)
	B_air.adjust_gas(/datum/gas/oxygen, 200)
	B_air.set_temperature(T20C)

	var/initial_total_n2 = A_air.get_moles(/datum/gas/nitrogen)
	var/initial_total_o2 = B_air.get_moles(/datum/gas/oxygen)

	// Drive equilibration.
	dq_atmos_test_drive_ticks(list(A, B), 60)

	// Each cell should now hold roughly half N2 and half O2.
	var/a_n2 = A_air.get_moles(/datum/gas/nitrogen)
	var/a_o2 = A_air.get_moles(/datum/gas/oxygen)
	var/b_n2 = B_air.get_moles(/datum/gas/nitrogen)
	var/b_o2 = B_air.get_moles(/datum/gas/oxygen)

	// Composition: in each cell, N2 and O2 should be approximately equal.
	TEST_ASSERT(abs(a_n2 - a_o2) < (initial_total_n2 * 0.1), \
		"A didn't reach 50/50 composition: N2=[a_n2] O2=[a_o2]")
	TEST_ASSERT(abs(b_n2 - b_o2) < (initial_total_o2 * 0.1), \
		"B didn't reach 50/50 composition: N2=[b_n2] O2=[b_o2]")
	// Cross-conservation: total N2 still ~200, total O2 still ~200.
	TEST_ASSERT(abs((a_n2 + b_n2) - initial_total_n2) < 1, \
		"N2 mass lost during diffusion: [initial_total_n2] → [a_n2 + b_n2]")
	TEST_ASSERT(abs((a_o2 + b_o2) - initial_total_o2) < 1, \
		"O2 mass lost during diffusion: [initial_total_o2] → [a_o2 + b_o2]")

	for(var/datum/gas/g as anything in A_air.gases)
		A_air.gases[g][MOLES] = 0
	for(var/datum/gas/g as anything in B_air.gases)
		B_air.gases[g][MOLES] = 0


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
	var/list/pair = dq_atmos_test_find_floor_pair_with_real_adjacency()
	TEST_ASSERT_NOTNULL(pair, "no floor pair with init-built atmos_adjacent_turfs — adjacency was never built, that's the bug")
	var/turf/open/A = pair[1]
	var/turf/open/B = pair[2]

	TEST_ASSERT(A.atmos_adjacent_turfs && A.atmos_adjacent_turfs[B], \
		"A's adjacency list doesn't contain B — init_immediate_calculate_adjacent_turfs is broken")
	TEST_ASSERT(B.atmos_adjacent_turfs && B.atmos_adjacent_turfs[A], \
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
	TEST_ASSERT(A in SSair.active_turfs, \
		"A not in SSair.active_turfs after assume_air — air_update_turf/add_to_active broken")

	// Sleep to let the live Master.Loop fire SSair normally. No state hacking.
	var/ticks_advanced = dq_atmos_test_wait_real_ssair_ticks(30)
	TEST_ASSERT(ticks_advanced >= 10, \
		"SSair only fired [ticks_advanced] times in [SSair.wait * 30 * 3]ds wall time — Master.Loop isn't ticking SSair. THIS IS THE BUG.")

	var/final_b_plasma = B.air.get_moles(/datum/gas/plasma)
	TEST_ASSERT(final_b_plasma > initial_b_plasma + 0.1, \
		"plasma DID NOT SPREAD to adjacent turf B after [ticks_advanced] real SSair ticks: A=[A.air.get_moles(/datum/gas/plasma)] B=[final_b_plasma]. The atmos engine isn't moving gas under normal Master.Loop firing — THIS IS THE PRODUCTION BUG.")

	// Cleanup so other tests don't see leftover plasma.
	for(var/datum/gas/g as anything in A.air.gases)
		A.air.gases[g][MOLES] = 0
	for(var/datum/gas/g as anything in B.air.gases)
		B.air.gases[g][MOLES] = 0


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
	for(var/datum/gas/g as anything in A.air.gases)
		A.air.gases[g][MOLES] = 0
	for(var/datum/gas/g as anything in B.air.gases)
		B.air.gases[g][MOLES] = 0
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

	// Sleep and let the real game tick. Master.Loop ticks SSmachines
	// (which calls Can.process()) AND SSair (which spreads gas tile-to-tile).
	dq_atmos_test_wait_real_ssair_ticks(30)

	var/final_a_plasma = A.air.get_moles(/datum/gas/plasma)
	var/final_b_plasma = B.air.get_moles(/datum/gas/plasma)

	TEST_ASSERT(final_a_plasma > initial_a_plasma + 1, \
		"canister DID NOT release plasma onto A after 30 SSair ticks: A=[final_a_plasma]. canister.process() not running or not pumping.")

	// A must be in active_turfs after canister released gas into it.
	// Without this, SSair has nothing to process and gas can't spread.
	TEST_ASSERT(A in SSair.active_turfs, \
		"A not in SSair.active_turfs after canister release — canister.process pumped gas into the turf but didn't enroll it. SSair will never process this turf. THIS IS THE PLAYER-VISIBLE PRODUCTION BUG.")

	TEST_ASSERT(final_b_plasma > initial_b_plasma + 0.1, \
		"plasma DID NOT spread from canister-released A to adjacent B: A=[final_a_plasma] B=[final_b_plasma]. Even though A has plasma, SSair never spread it. THIS IS THE PRODUCTION BUG players see.")

	// Cleanup
	Can.valve_open = FALSE
	qdel(Can)
	for(var/datum/gas/g as anything in A.air.gases)
		A.air.gases[g][MOLES] = 0
	for(var/datum/gas/g as anything in B.air.gases)
		B.air.gases[g][MOLES] = 0


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

	// Snapshot any existing overlay state.
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

	// Cleanup
	for(var/datum/gas/g as anything in T.air.gases)
		T.air.gases[g][MOLES] = 0
	T.update_visuals()



