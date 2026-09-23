/*

Usage:
Override /Run() to run your test code

Call TEST_FAIL() to fail the test (You should specify a reason)

You may use /New() and /Destroy() for setup/teardown respectively

You can use the run_loc_floor_bottom_left and run_loc_floor_top_right to get turfs for testing

*/

GLOBAL_DATUM(current_test, /datum/unit_test)
GLOBAL_VAR_INIT(failed_any_test, FALSE)
/// When unit testing, all logs sent to log_mapping are stored here and retrieved in log_mapping unit test.
GLOBAL_LIST_EMPTY(unit_test_mapping_logs)
/// Global assoc list of required mapping items, [item typepath] to [required item datum].
GLOBAL_LIST_EMPTY(required_map_items)

/// A list of every test that is currently focused.
/// Use the PERFORM_ALL_TESTS macro instead.
GLOBAL_VAR_INIT(focused_tests, focused_tests())

/// How many isolated test blocks to keep in the pool. Tests run strictly
/// sequentially (RunUnitTests() calls each test's New()/Run()/restore_atmos()/
/// Destroy() in a plain for loop before starting the next), so one block would
/// be enough in theory -- but a test's Destroy() may still be draining async
/// leftovers (a delayed callback, an expedition teardown_z wait) when the next
/// test's New() runs, so a small pool lets us round-robin instead of forcing
/// every test to block on the previous test's straggling cleanup.
#define UNIT_TEST_BLOCK_POOL_SIZE 8

/// One isolated, walled-off copy of maps/templates/unit_tests.dmm on its own
/// z-level. Checked out to exactly one running unit test at a time so tests no
/// longer share a single global floor turf (the historic source of most
/// intermittent unit-test failures: leaked hotspots, gas, and temperature from
/// one test bleeding into the next).
/datum/unit_test_block
	/// Bottom-left floor turf of this block, mirrors run_loc_floor_bottom_left.
	var/turf/bottom_left
	/// Top-right floor turf of this block, mirrors run_loc_floor_top_right.
	var/turf/top_right
	/// The z-level this block's copy of the template was loaded onto.
	var/z
	/// TRUE while a test currently owns this block.
	var/in_use = FALSE

/// The pool of isolated test blocks. Built lazily on the first test that needs
/// one, so non-test worlds never pay for it.
GLOBAL_LIST_EMPTY(unit_test_block_pool)
/// TRUE once the pool has been built (or an attempt was made to build it).
GLOBAL_VAR_INIT(unit_test_block_pool_ready, FALSE)

/// Loads UNIT_TEST_BLOCK_POOL_SIZE independent copies of the unit-test room
/// template, each on its own z-level, and records their corner turfs. Safe to
/// call more than once -- only the first call does anything.
/proc/ensure_unit_test_block_pool()
	if(GLOB.unit_test_block_pool_ready)
		return
	// Set this before load_new_z() (which yields) so a re-entrant call made
	// while we're still loading the first copy doesn't start a second build.
	GLOB.unit_test_block_pool_ready = TRUE

	for(var/i in 1 to UNIT_TEST_BLOCK_POOL_SIZE)
		var/datum/map_template/unit_tests/template = new
		var/new_z = template.load_new_z()
		if(!new_z)
			log_world("ensure_unit_test_block_pool: template failed to load copy #[i], the unit test block pool will be smaller than requested.")
			continue

		var/datum/unit_test_block/block = new
		block.z = new_z
		for(var/obj/effect/landmark/unit_test_bottom_left/L in GLOB.landmarks_list)
			if(L.z == new_z)
				block.bottom_left = get_turf(L)
				break
		for(var/obj/effect/landmark/unit_test_top_right/L in GLOB.landmarks_list)
			if(L.z == new_z)
				block.top_right = get_turf(L)
				break

		if(!block.bottom_left || !block.top_right)
			log_world("ensure_unit_test_block_pool: copy #[i] on z[new_z] is missing its corner landmarks, discarding it.")
			continue

		GLOB.unit_test_block_pool += block

	if(!length(GLOB.unit_test_block_pool))
		CRASH("ensure_unit_test_block_pool: failed to load any isolated test blocks.")

/// Checks out a free isolated test block, waiting for one to be returned if
/// every block is currently in use (should be rare -- see the pool size
/// comment above). Bounded so a genuine deadlock fails loudly instead of
/// hanging the suite forever.
/proc/acquire_unit_test_block()
	RETURN_TYPE(/datum/unit_test_block)
	ensure_unit_test_block_pool()

	var/waited = 0
	while(TRUE)
		for(var/datum/unit_test_block/block as anything in GLOB.unit_test_block_pool)
			if(!block.in_use)
				block.in_use = TRUE
				return block
		waited++
		if(waited > 600) // ~60s of real time at 1 tick/sleep(1) each
			CRASH("acquire_unit_test_block: every isolated test block is still in use after 60s -- likely a stuck async teardown.")
		sleep(1)

/// Resets a block to a clean floor (deletes everything spawned on it, restores
/// default air/temperature on every open turf, drops any walls a test put up)
/// and returns it to the pool. Waits for the world's own async teardown paths
/// so a block is never recycled mid-cleanup.
/proc/release_unit_test_block(datum/unit_test_block/block)
	if(!block)
		return

	// Mirror /datum/unit_test/restore_atmos(): don't hand this block's z back
	// out while expedition teardown (or anything else async) is still touching
	// turfs on it.
	while(SSexpedition && length(SSexpedition.teardown_z))
		sleep(1)

	for(var/turf/T in block_turfs(block))
		for(var/atom/movable/AM in T)
			if(istype(AM, /obj/effect/landmark))
				continue
			qdel(AM)

		if(istype(T, /turf/open))
			var/turf/open/OT = T
			if(OT.active_hotspot)
				qdel(OT.active_hotspot)
			if(OT.air)
				OT.air.copy_from(dq_unit_test_block_default_air())
				OT.air_update_turf(TRUE, FALSE)
			OT.set_temperature(T20C)
		else if(istype(T, /turf/simulated/wall))
			// A test isolated a pair of turfs with real walls (dq_atmos_test_isolate_pair
			// et al) and never got to restore them because it errored out early.
			T.ChangeTurf(/turf/simulated/floor/tiled/steel)

	block.in_use = FALSE

/// The default air mix a block's open turfs start with -- standard station air.
/proc/dq_unit_test_block_default_air()
	RETURN_TYPE(/datum/gas_mixture)
	var/static/datum/gas_mixture/default_air
	if(!default_air)
		default_air = new
		default_air.set_temperature(T20C)
		default_air.set_moles(/datum/gas/oxygen, MOLES_O2STANDARD)
		default_air.set_moles(/datum/gas/nitrogen, MOLES_N2STANDARD)
	return default_air.copy()

/// Every turf in a block's rectangle (inclusive), by walking its bottom-left
/// to top-right corners -- the block is always one z-level.
/proc/block_turfs(datum/unit_test_block/block)
	var/list/turfs = list()
	if(!block?.bottom_left || !block.top_right)
		return turfs
	for(var/x in block.bottom_left.x to block.top_right.x)
		for(var/y in block.bottom_left.y to block.top_right.y)
			var/turf/T = locate(x, y, block.z)
			if(T)
				turfs += T
	return turfs

/proc/focused_tests()
	var/list/focused_tests = list()
	for (var/datum/unit_test/unit_test as anything in subtypesof(/datum/unit_test))
		if (initial(unit_test.focus))
			focused_tests += unit_test

	return focused_tests.len > 0 ? focused_tests : null

/// TRUE when this unit-test world runs only TEST_FOCUS tests
/// (tools/dq_focused_test.sh). Focused runs skip boot and shutdown waits that
/// only matter for the full suite; see "Focused runs" in doc/testing.md.
/proc/unit_test_is_focused_run()
	return !!length(GLOB.focused_tests)

/datum/unit_test
	//Bit of metadata for the future maybe
	var/list/procs_tested

	/// The bottom left floor turf of the testing zone
	var/turf/run_loc_floor_bottom_left

	/// The top right floor turf of the testing zone
	var/turf/run_loc_floor_top_right
	///The priority of the test, the larger it is the later it fires
	var/priority = TEST_DEFAULT
	//internal shit
	var/focus = FALSE
	var/succeeded = TRUE
	var/list/allocated
	var/list/fail_reasons

	/// Do not instantiate if type matches this
	abstract_type = /datum/unit_test

	/// List of atoms that we don't want to ever initialize in an agnostic context, like for Create and Destroy. Stored on the base datum for usability in other relevant tests that need this data.
	var/static/list/uncreatables = null

	/// The isolated block this test checked out of the pool, released on Destroy().
	var/datum/unit_test_block/test_block

/proc/cmp_unit_test_priority(datum/unit_test/a, datum/unit_test/b)
	return initial(a.priority) - initial(b.priority)

/datum/unit_test/New()
	if (isnull(uncreatables))
		uncreatables = build_list_of_uncreatables()

	allocated = new
	test_block = acquire_unit_test_block()
	run_loc_floor_bottom_left = test_block.bottom_left
	run_loc_floor_top_right = test_block.top_right

	TEST_ASSERT(isfloorturf(run_loc_floor_bottom_left), "run_loc_floor_bottom_left was not a floor ([run_loc_floor_bottom_left])")
	TEST_ASSERT(isfloorturf(run_loc_floor_top_right), "run_loc_floor_top_right was not a floor ([run_loc_floor_top_right])")

/datum/unit_test/Destroy()
	QDEL_LIST(allocated)
	release_unit_test_block(test_block)
	test_block = null
	return ..()

/datum/unit_test/proc/Run()
	TEST_FAIL("[type]/Run() called parent or not implemented")

/datum/unit_test/proc/Fail(reason = "No reason", file = "OUTDATED_TEST", line = 1)
	succeeded = FALSE

	if(!istext(reason))
		reason = "FORMATTED: [reason != null ? reason : "NULL"]"

	LAZYADD(fail_reasons, list(list(reason, file, line)))

/// Allocates an instance of the provided type, and places it somewhere in an available loc
/// Instances allocated through this proc will be destroyed when the test is over
/datum/unit_test/proc/allocate(type, ...)
	var/list/arguments = args.Copy(2)
	if(ispath(type, /atom))
		if (!arguments.len)
			arguments = list(run_loc_floor_bottom_left)
		else if (arguments[1] == null)
			arguments[1] = run_loc_floor_bottom_left
	var/instance
	// Byond will throw an index out of bounds if arguments is empty in that arglist call. Sigh
	if(length(arguments))
		instance = new type(arglist(arguments))
	else
		instance = new type()
	allocated += instance
	return instance

/// A floor turf on the map, for tests whose subject must be in the world.
/// allocate() defaults to run_loc_floor_bottom_left, which is null when the
/// unit-test room template isn't loaded.
/datum/unit_test/proc/test_floor()
	RETURN_TYPE(/turf)
	if(run_loc_floor_bottom_left)
		return run_loc_floor_bottom_left
	for(var/turf/simulated/floor/T in world)
		return T

/// Resets the air of our testing room to its default
/datum/unit_test/proc/restore_atmos()
	// Expedition release is deliberately asynchronous in production. Do not let
	// the next test start while a teardown job is still changing thousands of
	// turfs and publishing atmosphere topology.
	while(SSexpedition && length(SSexpedition.teardown_z))
		sleep(1)
	// DQ atmos integration tests operate on mapped turfs because the inherited
	// per-test reservation is not implemented. Restore every turf they snapshot
	// after each test so later tests and shuttles never inherit vacuum, test gas,
	// or temporary sealing geometry.
	dq_atmos_test_restore_state()

/datum/unit_test/proc/test_screenshot(name, icon/icon)
	if (!istype(icon))
		TEST_FAIL("[icon] is not an icon.")
		return

	var/path_prefix = replacetext(replacetext("[type]", "/datum/unit_test/", ""), "/", "_")
	name = replacetext(name, "/", "_")

	var/filename = "code/modules/unit_tests/screenshots/[path_prefix]_[name].png"

	if (fexists(filename))
		var/data_filename = "data/screenshots/[path_prefix]_[name].png"
		fcopy(icon, data_filename)
		log_test("\t[path_prefix]_[name] was found, putting in data/screenshots")
	else
#ifdef CIBUILDING
		// We are runing in real CI, so just pretend it worked and move on
		fcopy(icon, "data/screenshots_new/[path_prefix]_[name].png")

		log_test("\t[path_prefix]_[name] was put in data/screenshots_new")
#else
		// We are probably running in a local build
		fcopy(icon, filename)
		TEST_FAIL("Screenshot for [name] did not exist. One has been created.")
#endif

/// Helper for screenshot tests to take an image of an atom from all directions and insert it into one icon
/datum/unit_test/proc/get_flat_icon_for_all_directions(atom/thing, no_anim = TRUE)
	var/icon/output = icon('icons/effects/effects.dmi', "nothing")

	for (var/direction in GLOB.cardinal)
		var/icon/partial = getFlatIcon(thing, defdir = direction, no_anim = no_anim)
		output.Insert(partial, dir = direction)

	return output

/// Logs a test message. Will use GitHub action syntax found at https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions
/datum/unit_test/proc/log_for_test(text, priority, file, line)
	var/map_name = SSmapping.current_map.name

	// Need to escape the text to properly support newlines.
	var/annotation_text = replacetext(text, "%", "%25")
	annotation_text = replacetext(annotation_text, "\n", "%0A")

	log_world("::[priority] file=[file],line=[line],title=[map_name]: [type]::[annotation_text]")

/**
 * Helper to perform a click
 *
 * * clicker: The mob that will be clicking
 * * clicked_on: The atom that will be clicked
 * * passed_params: A list of parameters to pass to the click
 */
/datum/unit_test/proc/click_wrapper(mob/living/clicker, atom/clicked_on, list/passed_params = list(LEFT_CLICK = 1, BUTTON = LEFT_CLICK))
	clicker.next_click = -1
	clicker.next_move = -1
	clicker.ClickOn(clicked_on, list2params(passed_params))

/// Tick usage while a test ran: how many MC ticks it spanned, how many overran
/// (usage above 100%) and the worst one. Recorded in data/unit_tests.json.
/proc/unit_test_tick_stats(start_index)
	var/list/usage = Master.perf_tick_usage
	if(start_index > usage.len)
		return list("samples" = 0, "overruns" = 0, "max" = 0)
	var/overruns = 0
	var/worst = 0
	for(var/i in start_index to usage.len)
		var/value = usage[i]
		worst = max(worst, value)
		if(value > 100)
			overruns++
	return list("samples" = usage.len - start_index + 1, "overruns" = overruns, "max" = worst)

/proc/RunUnitTest(datum/unit_test/test_path, list/test_results, current_index, total_tests)
	if(ispath(test_path, /datum/unit_test/focus_only))
		return

	if(initial(test_path.abstract_type) == test_path)
		return

	var/datum/unit_test/test = new test_path

	GLOB.current_test = test
	var/duration = 0
	var/tick_start_index = 0
	var/runtimes_before = GLOB.total_runtimes
	var/list/tick_stats
	// Generated-station coverage is temporarily disabled while that subsystem is
	// being redesigned. Keep the cases compiled and visible as skipped so they
	// cannot silently disappear from the suite inventory.
	var/test_path_text = "[test_path]"
	var/generated_station_test = findtext(test_path_text, "/datum/unit_test/dq_generated_station") == 1 || findtext(test_path_text, "/datum/unit_test/dq_generated_room") == 1 || (test_path in list(
		/datum/unit_test/dq_expedition_generates_site,
		/datum/unit_test/dq_debug_station_initializes_complete_runtime,
		/datum/unit_test/dq_emergency_station_fallback_is_playable,
	))
	var/skip_test = generated_station_test || (test_path in SSmapping.current_map.skipped_tests)
	var/test_output_desc = "[test_path]"
	var/message = ""

	log_world("::group::([current_index]/[total_tests]) [test_path]")
	log_test("Running [current_index]/[total_tests]: [test_path]")

	if(skip_test)
		log_world("[TEST_OUTPUT_YELLOW("SKIPPED")] Skipped run on map [SSmapping.current_map.name].")

	else
		duration = REALTIMEOFDAY
		tick_start_index = Master.perf_samples_total + 1
		test.Run()
		test.restore_atmos()

		duration = REALTIMEOFDAY - duration
		tick_stats = unit_test_tick_stats(Master.perf_index_of(tick_start_index))
		GLOB.current_test = null
		GLOB.failed_any_test |= !test.succeeded

		var/list/log_entry = list()
		var/list/fail_reasons = test.fail_reasons

		for(var/reasonID in 1 to LAZYLEN(fail_reasons))
			var/text = fail_reasons[reasonID][1]
			var/file = fail_reasons[reasonID][2]
			var/line = fail_reasons[reasonID][3]

			test.log_for_test(text, "error", file, line)

			// Normal log message
			log_entry += "\tFAILURE #[reasonID]: [text] at [file]:[line]"

		if(length(log_entry))
			message = log_entry.Join("\n")
			log_test(message)

		test_output_desc += " [duration / 10]s"
		if (test.succeeded)
			log_world("[TEST_OUTPUT_GREEN("PASS")] [test_output_desc]")

	log_world("::endgroup::")

	if (!test.succeeded && !skip_test)
		log_world("::error::[TEST_OUTPUT_RED("FAIL")] [test_output_desc]")

	var/final_status = skip_test ? UNIT_TEST_SKIPPED : (test.succeeded ? UNIT_TEST_PASSED : UNIT_TEST_FAILED)
	test_results[test_path] = list("status" = final_status, "message" = message, "name" = test_path, "duration_ds" = duration, "runtimes" = GLOB.total_runtimes - runtimes_before, "ticks" = tick_stats)

	qdel(test)

/// Builds (and returns) a list of atoms that we shouldn't initialize in generic testing, like Create and Destroy.
/// It is appreciated to add the reason why the atom shouldn't be initialized if you add it to this list.
/datum/unit_test/proc/build_list_of_uncreatables()
	RETURN_TYPE(/list)
	var/list/returnable_list = list()
	// The following are just generic, singular types.
	returnable_list = list(
		//Never meant to be created, errors out the ass for mobcode reasons
		/mob/living/carbon,
		//And another
		// NOT IMPLEMENTED: /obj/item/slimecross/recurring,
		//This should be obvious
		// NOT IMPLEMENTED: /obj/machinery/doomsday_device,
		//Yet more templates
		// NOT IMPLEMENTED: /obj/machinery/restaurant_portal,
		//Template type
		// /obj/machinery/power/turbine deleted with ZAS atmos.
		// NOT IMPLEMENTED: /obj/machinery/power/turbine,
		//Template type
		// NOT IMPLEMENTED: /obj/effect/mob_spawn,
		//Template type
		// NOT IMPLEMENTED: /obj/structure/holosign/robot_seat,
		//Singleton
		/mob/dview,
		//Template type
		// NOT IMPLEMENTED: /obj/item/bodypart,
		//This is meant to fail extremely loud every single time it occurs in any environment in any context, and it falsely alarms when this unit test iterates it. Let's not spawn it in.
		/obj/merge_conflict_marker,
		//briefcase launchpads erroring
		// NOT IMPLEMENTED: /obj/machinery/launchpad/briefcase,
		//Wings abstract path
		// NOT IMPLEMENTED: /obj/item/organ/wings,
		//Not meant to spawn without the machine wand
		// NOT IMPLEMENTED: /obj/effect/bug_moving,
		//The abstract grown item expects a seed, but doesn't have one
		// NOT IMPLEMENTED: /obj/item/food/grown,
		///Single use case holder atom requiring a user
		// NOT IMPLEMENTED: /atom/movable/looking_holder,
	)

	// Everything that follows is a typesof() check.

	//Say it with me now, type template
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/mapping_helpers)
	//This turf existing is an error in and of itself
	// NOT IMPLEMENTED: returnable_list += typesof(/turf/baseturf_skipover)
	// NOT IMPLEMENTED: returnable_list += typesof(/turf/baseturf_bottom)
	//This demands a borg, so we'll let if off easy
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/item/modular_computer/pda/silicon)
	//This one demands a computer, ditto
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/item/modular_computer/processor)
	//Very finiky, blacklisting to make things easier
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/item/poster/wanted)
	//Needs clients / mobs to observe it to exist. Also includes hallucinations.
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/client_image_holder)
	//Same to above. Needs a client / mob / hallucination to observe it to exist.
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/projectile/hallucination)
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/item/hallucinated)
	//We don't have a pod
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/pod_landingzone_effect)
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/pod_landingzone)
	//We have a baseturf limit of 10, adding more than 10 baseturf helpers will kill CI, so here's a future edge case to fix.
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/baseturf_helper)
	//No tauma to pass in
	// NOT IMPLEMENTED: returnable_list += typesof(/mob/eye/imaginary_friend)
	//No heart to give
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/structure/ethereal_crystal)
	//No linked console
	// NOT IMPLEMENTED: returnable_list += typesof(/mob/eye/camera/remote/base_construction)
	//See above
	// NOT IMPLEMENTED: returnable_list += typesof(/mob/eye/camera/remote/shuttle_docker)
	//Hangs a ref post invoke async, which we don't support. Could put a qdeleted check but it feels hacky
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/anomaly/grav/high)
	//See above
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/timestop)
	//Sparks can ignite a number of things, causing a fire to burn the floor away. Only you can prevent CI fires
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/particle_effect/sparks)
	//See above - These are one of those things.
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/decal/cleanable/fuel_pool)
	//Invoke async in init, skippppp
	// NOT IMPLEMENTED: returnable_list += typesof(/mob/living/silicon/robot/model)
	//This lad also sleeps
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/item/hilbertshotel)
	//this boi spawns turf changing stuff, and it stacks and causes pain. Let's just not
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/sliding_puzzle)
	//these can explode and cause the turf to be destroyed at unexpected moments
	returnable_list += typesof(/obj/effect/mine)
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/spawner/random/contraband/landmine)
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/item/minespawner)
	//Stacks baseturfs, can't be tested here
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/temp_visual/lava_warning)
	//Stacks baseturfs, can't be tested here
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/landmark/ctf)
	//Our system doesn't support it without warning spam from unregister calls on things that never registered
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/docking_port)
	//Asks for a shuttle that may not exist, let's leave it alone
	returnable_list += typesof(/obj/item/pinpointer/shuttle)
	//This spawns beams as a part of init, which can sleep past an async proc. This hangs a ref, and fucks us. It's only a problem here because the beam sleeps with CHECK_TICK
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/structure/alien/resin/flower_bud)
	//Needs a linked mecha
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/effect/skyfall_landingzone)
	//Expects a mob to holderize, we have nothing to give
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/item/clothing/head/mob_holder)
	//Needs cards passed into the initilazation args
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/item/toy/cards/cardhand)
	//Needs a holodeck area linked to it which is not guarenteed to exist and technically is supposed to have a 1:1 relationship with computer anyway.
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/machinery/computer/holodeck)
	//runtimes if not paired with a landmark
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/structure/transport/linear)
	// Runtimes if the associated machinery does not exist, but not the base type
	// NOT IMPLEMENTED: returnable_list += subtypesof(/obj/machinery/airlock_controller)
	// Always ought to have an associated escape menu. Any references it could possibly hold would need one regardless.
	// NOT IMPLEMENTED: returnable_list += subtypesof(/atom/movable/screen/escape_menu)
	// Can't spawn openspace above nothing, it'll get pissy at me
	// NOT IMPLEMENTED: returnable_list += typesof(/turf/open/space/openspace)
	// NOT IMPLEMENTED: returnable_list += typesof(/turf/open/openspace)
	// NOT IMPLEMENTED: returnable_list += typesof(/obj/item/robot_model) // These should never be spawned outside of a robot.

	return returnable_list

/proc/RunUnitTests()
	#ifdef BENCHMARK
	RunBenchmarks()
	return
	#endif
	CHECK_TICK
	// Mapped patrol bots run independently of tests and can enqueue expensive
	// pathfinding while the suite is deliberately saturating the tick budget.
	// Tests that exercise bots allocate their own isolated instances.
	for(var/mob/living/bot/map_bot in world)
		qdel(map_bot)

	var/list/tests_to_run = subtypesof(/datum/unit_test)
	var/list/focused_tests = list()
	for (var/_test_to_run in tests_to_run)
		var/datum/unit_test/test_to_run = _test_to_run
		if (initial(test_to_run.focus))
			focused_tests += test_to_run
	if(length(focused_tests))
		tests_to_run = focused_tests

	sortTim(tests_to_run, GLOBAL_PROC_REF(cmp_unit_test_priority))

	var/list/test_results = list()
	var/total_tests = length(tests_to_run)
	var/current_test_index = 0
	log_test("Unit-test suite starting: [total_tests] test types[LAZYLEN(focused_tests) ? " (focused run)" : ""].")

	//Hell code, we're bound to end the round somehow so let's stop if from ending while we work
	SSticker.delay_end = TRUE
	for(var/unit_path in tests_to_run)
		CHECK_TICK //We check tick first because the unit test we run last may be so expensive that checking tick will lock up this loop forever
		current_test_index++
		RunUnitTest(unit_path, test_results, current_test_index, total_tests)
	SSticker.delay_end = FALSE
	log_test("Unit-test suite finished: [total_tests] test types, failures: [GLOB.failed_any_test ? "yes" : "no"].")

	var/file_name = "data/unit_tests.json"
	fdel(file_name)
	file(file_name) << json_encode(test_results)

	SSticker.force_ending = ADMIN_FORCE_END_ROUND
	//We have to call this manually because del_text can preceed us, and SSticker doesn't fire in the post game
	SSticker.declare_completion()

/datum/map_template/unit_tests
	name = "Unit Tests Zone"
	mappath = "maps/templates/unit_tests.dmm"
