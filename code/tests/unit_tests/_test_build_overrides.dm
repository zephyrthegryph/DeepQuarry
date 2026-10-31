// Test-build behaviour as appended overrides (engine/test-guards-out). Each definition here replaces or wraps a game proc only in
// a test build, so the game files carry no UNIT_TESTS branch for it. This file is the LAST include of deepquarry.dme: an override must
// be compiled after the definition it overrides (the later definition of a type's proc is the one that runs, and its ..() calls the
// earlier). Keep it last.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/universal_icon/New(icon/icon_file, icon_state="", dir=null, frame=null, datum/icon_transformer/transform=null, color=null)
	// This check is kinda slow and shouldn't fail unless a developer makes a mistake. So it'll get caught in unit tests.
	if(!isicon(icon_file) || !isfile(icon_file) || "[icon_file]" == "/icon" || !length("[icon_file]"))
		// bad! use 'icons/path_to_dmi.dmi' format only
		CRASH("FATAL: universal_icon was provided icon_file: [icon_file] - icons provided to batched spritesheets MUST be DMI files, they cannot be /image, /icon, or other runtime generated icons.")
	return ..()

/datum/icon_transformer/blend_color(color, blend_mode)
	if(!istext(color))
		CRASH("Invalid color provided to blend_color: [color]")
	if(!isnum(blend_mode))
		CRASH("Invalid blend_mode provided to blend_color: [blend_mode]")
	return ..()

/datum/icon_transformer/blend_icon(datum/universal_icon/icon_object, blend_mode, x=1, y=1)
	// icon_object's type is checked later in to_list
	if(!isnum(blend_mode))
		CRASH("Invalid blend_mode provided to blend_icon: [blend_mode]")
	if(!isnum(x))
		CRASH("Invalid x offset provided to blend_icon: [x]")
	if(!isnum(y))
		CRASH("Invalid y offset provided to blend_icon: [y]")
	return ..()

/datum/icon_transformer/scale(width, height)
	if(!isnum(width) || !isnum(height))
		CRASH("Invalid arguments provided to scale: [width],[height]")
	return ..()

/datum/icon_transformer/crop(x1, y1, x2, y2)
	if(!isnum(x1) || !isnum(y1) || !isnum(x2) || !isnum(y2))
		CRASH("Invalid arguments provided to crop: [x1],[y1],[x2],[y2]")
	return ..()

/datum/icon_transformer/flip(dir)
	if(!isnum(dir))
		CRASH("Invalid arguments provided to flip: [dir]")
	return ..()

/datum/icon_transformer/rotate(angle)
	if(!isnum(angle))
		CRASH("Invalid arguments provided to rotate: [angle]")
	return ..()

/datum/icon_transformer/shift(dir, offset, wrap=FALSE)
	if(!isnum(dir) || !isnum(offset) || (wrap != FALSE && wrap != TRUE))
		CRASH("Invalid arguments provided to shift: [dir],[offset],[wrap]")
	return ..()

/datum/icon_transformer/swap_color(src_color, dst_color)
	if(!istext(src_color) || !istext(dst_color))
		CRASH("Invalid arguments provided to swap_color: [src_color],[dst_color]")
	return ..()

/datum/icon_transformer/draw_box(color, x1, y1, x2=x1, y2=y1)
	if(!istext(color) || !isnum(x1) || !isnum(y1) || !isnum(x2) || !isnum(y2))
		CRASH("Invalid arguments provided to draw_box: [color],[x1],[y1],[x2],[y2]")
	return ..()

/datum/system/holomaps/initialize()
	if(unit_test_boot_skips(BOOT_NEED_HOLOMAPS))
		unit_test_boot_skipped(BOOT_NEED_HOLOMAPS, "HoloMiniMaps (no minimap is generated)")
		return
	return ..()

/datum/system/early_assets/initialize()
	if(unit_test_boot_skips(BOOT_NEED_EARLY_ASSETS))
		unit_test_boot_skipped(BOOT_NEED_EARLY_ASSETS, "Early Assets (get_asset_datum() builds each on first use)")
		return
	return ..()

/datum/system/assets/initialize()
	// Focused unit-test runs skip generating every asset and spritesheet at boot
	// (about 2.3 s on the test map). Anything that needs one still gets it:
	// get_asset_datum() builds an asset on first use, which is what the
	// spritesheets and asset tests call. The full suite still loads everything.
	if(unit_test_is_focused_run())
		transport.start(cache)
		return
	return ..()

/datum/system/radio/initialize()
	if(!initialized && unit_test_boot_skips(BOOT_NEED_RADIO))
		initialized = TRUE
		unit_test_boot_skipped(BOOT_NEED_RADIO, "Radio (GLOB.autospeaker stays null)")
		return
	return ..()

/mob/show_message(msg, type, alt, alt_type)
	test_chat_note(src, msg) // a test mob has no client: the driver keeps what it would have been shown
	return ..()

/world/Error(exception/E, datum/e_src)
	// Capture before error suppression and cache initialization. The fixed bound
	// keeps a failing test from retaining unbounded exception descriptions.
	if(GLOB.unit_test_runtime_capture)
		if(LAZYLEN(GLOB.unit_test_runtime_events) < 256)
			LAZYADD(GLOB.unit_test_runtime_events, list(list("name" = E?.name, "file" = E?.file, "line" = E?.line, "description" = E?.desc)))
		else
			GLOB.unit_test_runtime_events_truncated = TRUE
	// Preserve even very-early runtimes that occur before the normal error cache
	// is initialized; CI treats any runtime as fatal and needs an actionable file.
	var/runtime_log_directory = GLOB?.log_directory || "data/logs/ci"
	text2file("[time_stamp()] [E?.file]:[E?.line] [E?.name]\n[E?.desc]\n", "[runtime_log_directory]/runtime-errors.log")
	return ..()

/datum/system/dbcore/Connect()
	// A test world has no database: never attempt a connect, whatever the config says (sql_enabled is normally off there, so this is mostly a logged guarantee).
	if(!last_error)
		last_error = "skipped: unit-test world"
		log_sql("Connect() skipped: unit-test world, no database is used.")
	return FALSE

/datum/system/input/input_room(datum/input_event/E)
	// A test world boots through ticks that run far past 100%: only room_override decides there (as shedding is off in tests).
	return TRUE

/world/RunUnattendedFunctions()
	HandleTestRun()
	return ..()

/world/proc/HandleTestRun()
	//trigger things to run the whole process
	Kernel.sleep_offline_after_initializations = FALSE
	SSticker.request_immediate_start(TRUE)
	CONFIG_SET(number/round_end_countdown, 0)
	var/after_start
	dq_test_shard_init()
	after_start = GLOBAL_PROC_REF(start_unit_tests)
	var/start_delay = 10 SECONDS
	// The full suite keeps upstream's 10 s round-start settle so CI and local
	// full runs see the same world. Focused runs are for iteration and start
	// after 2 s; a test that only passes after the longer settle should wait
	// for what it needs itself (see doc/testing.md).
	if(unit_test_is_focused_run())
		start_delay = 1 SECONDS
		// --boot (only dq_boot_gate): the gate reads what the boot logged, so there is nothing to settle.
		if(unit_test_is_boot_only_run())
			start_delay = 0
		log_world("Unit tests: round-start settle [start_delay / (1 SECONDS)] s ([unit_test_is_boot_only_run() ? "boot-only" : "focused"] run).")
	SSticker.OnRoundstart(null, after_start, delay = start_delay)

/world/proc/FinishTestRun()
	var/list/fail_reasons
	if(GLOB)
		if(GLOB.total_runtimes != 0)
			fail_reasons = list("Total runtimes: [GLOB.total_runtimes]")
		if(GLOB.failed_any_test)
			LAZYADD(fail_reasons, "Unit Tests failed!")
		if(GLOB.boot_unclean)
			LAZYADD(fail_reasons, GLOB.boot_unclean)
		if(!GLOB.log_directory)
			LAZYADD(fail_reasons, "Missing GLOB.log_directory!")
	else
		fail_reasons = list("Missing GLOB!")
	log_world("Finishing the test run: writing the result markers ([fail_reasons ? "failed" : "clean"]).")
	if(!fail_reasons)
		text2file("Success!", "[GLOB.log_directory]/clean_run.lk")
	else
		log_world("Test run failed!\n[fail_reasons.Join("\n")]")
	// The marker the build's watchdog waits for (tools/build/lib/byond.ts, watchdogCleanFile): written for a failed run too, so a
	// daemon that lingers after the world is done is killed within seconds, while a world still writing its logs on a busy machine
	// is given time to finish before it is declared unclean.
	if(GLOB && GLOB.log_directory)
		text2file(fail_reasons ? "Failed" : "Finished", "[GLOB.log_directory]/finished_run.lk")
		log_world("Result markers written (finished_run.lk).")
	// Shut down once Reboot() has returned (the MC is already down, so this is a world tick
	// callback, not a timer): deleting the world from inside Reboot() leaves byond in a bad way.
	world_next_tick(GLOBAL_PROC_REF(world_finish_test_shutdown))

/proc/world_finish_test_shutdown()
	log_world("Test world: shutting down the world.")
	spent(world) //shut it down

/datum/kernel_latency/New()
	..()
	enabled = FALSE // the harness drives input itself: no latency sampling in a test world

// System procs only tests call (here, not code/tests: system_boundary B3 exempts code/modules/unit_tests).
// from code/ATMOSPHERICS/rust_pipenets.dm
/// Test hook: steps every pipe device now, as a frame does once a period, and delivers their reports.
/datum/system/air/proc/rust_step_pipe_devices()
	if(!rust_pipe_device_count)
		return
	vg_frame_force_devices()
	native_system().drain()

// from code/datums/native/entities.dm
/**
 * The drift audit: every bound atom's declared inputs against what Rust stores, in one call. The
 * test sandbox teardown and the binding fuzz test run it after every step (a repaired divergence
 * is a runtime that fails the test that caused it). Returns every finding (empty: no divergence).
 * Test builds only: production never sweeps.
 */
/datum/system/native/proc/reconcile_all()
	. = list()
	for(var/atom/movable/mover as anything in bound.Copy())
		if(QDELETED(mover) || !mover.vg_entity)
			continue
		var/list/mismatches = mover.vg_reconcile()
		if(length(mismatches))
			. += "[mover.type] [REF(mover)]: [jointext(mismatches, "; ")]"

/// Global convenience: `vg_reconcile_all()` (called from the test sandbox teardown and the fuzz test).
/proc/vg_reconcile_all()
	return SSvg.reconcile_all()

#endif
