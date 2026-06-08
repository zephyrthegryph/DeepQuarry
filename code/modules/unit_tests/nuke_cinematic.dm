// Some defines for tracking if the correct cinematic / animation is playing.
#define PLAYING_CORRECT_ANIMATION 2
#define PLAYING_INCORRECT_NUKE_ANIMATION 1
#define NOT_PLAYING_ANIMATION 0

/**
 * Tests the nuke-detonation cinematic path that this fork actually implements.
 *
 * On this codebase, /obj/machinery/nuclearbomb/explode() is the Baystation-style
 * detonation. It is NOT directly testable: it sleeps for 20 seconds, depends on a
 * live SSticker game mode, and on the "unhandled ending" branch calls
 * world.Reboot() — which would tear down the unit-test run. So instead of driving
 * explode() end-to-end, this test exercises the piece explode() relies on and that
 * IS fully implemented: play_cinematic(/datum/cinematic/nuke/self_destruct).
 *
 * That covers the parts that genuinely work:
 *   - the cinematic datum is constructed,
 *   - start_cinematic() broadcasts COMSIG_GLOB_PLAY_CINEMATIC with that datum,
 *   - the broadcast carries the correct /datum/cinematic/nuke/self_destruct type
 *     (the same type the self-destruct branch of explode() plays).
 *
 * It deliberately does NOT depend on the cinematic's show_to / GET_CLIENT path,
 * which is marked NOT IMPLEMENTED in code/datums/cinematics/_cinematic.dm — we pass
 * an empty watcher list so no client rendering is attempted.
 */
/datum/unit_test/nuke_cinematic
	/// Used to track via signal if the correct cinematic / animation is playing.
	var/cinematic_playing = NOT_PLAYING_ANIMATION
	/// Tracks what typepath of cinematic is being played.
	var/cinematic_playing_type

/datum/unit_test/nuke_cinematic/Run()
	// Pause round-end checks defensively so nothing downstream tries to end the
	// round while we drive the cinematic.
	var/old_paused = SSticker.roundend_check_paused
	SSticker.roundend_check_paused = TRUE

	RegisterSignal(SSdcs, COMSIG_GLOB_PLAY_CINEMATIC, PROC_REF(check_cinematic))

	// Drive the exact production entry point the nuke self-destruct uses. Empty
	// watcher list => no client show_to path is exercised (that path is NOT
	// IMPLEMENTED). The COMSIG_GLOB_PLAY_CINEMATIC broadcast fires synchronously
	// inside start_cinematic before any sleeps, so check_cinematic runs before
	// play_cinematic() returns.
	var/datum/cinematic/nuke/self_destruct/playing = play_cinematic(/datum/cinematic/nuke/self_destruct, list())

	UnregisterSignal(SSdcs, COMSIG_GLOB_PLAY_CINEMATIC)
	SSticker.roundend_check_paused = old_paused

	TEST_ASSERT_NOTNULL(playing, "play_cinematic() did not return a cinematic datum.")
	TEST_ASSERT(istype(playing, /datum/cinematic/nuke/self_destruct), \
		"play_cinematic() returned the wrong cinematic type. (Got: [playing?.type])")

	switch(cinematic_playing)
		if(NOT_PLAYING_ANIMATION)
			TEST_FAIL("COMSIG_GLOB_PLAY_CINEMATIC was never broadcast when a nuke cinematic was started.")

		if(PLAYING_INCORRECT_NUKE_ANIMATION)
			TEST_FAIL("An incorrect cinematic was broadcast. (Expected: /datum/cinematic/nuke/self_destruct, Got: [cinematic_playing_type])")

	// Let the cinematic tear itself down via its own scheduled cleanup
	// (start_cinematic queues clean_up_cinematic after cleanup_time). We don't
	// qdel it manually: that pending timer holds a reference to the datum and
	// would fire clean_up_cinematic on an already-deleted cinematic.

/// Used to track whenever a cinematic starts playing, so we can check if it's the right one.
/datum/unit_test/nuke_cinematic/proc/check_cinematic(datum/source, datum/cinematic/playing)
	SIGNAL_HANDLER

	cinematic_playing_type = playing.type
	if(istype(playing, /datum/cinematic/nuke/self_destruct))
		cinematic_playing = PLAYING_CORRECT_ANIMATION

	else if(istype(playing, /datum/cinematic/nuke))
		cinematic_playing = PLAYING_INCORRECT_NUKE_ANIMATION

#undef PLAYING_CORRECT_ANIMATION
#undef PLAYING_INCORRECT_NUKE_ANIMATION
#undef NOT_PLAYING_ANIMATION
