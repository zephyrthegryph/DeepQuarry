// Async character previews (doc/rewrite/fixes.md Q4).

/// Clientless prefs stub: skips the client/savefile New() chain.
/datum/preferences/dq_preview_test_stub

/datum/preferences/dq_preview_test_stub/New()
	return

/datum/preferences/dq_preview_test_stub/Destroy()
	value_cache = null
	return ..()

/datum/preferences/dq_preview_test_stub/update_preview_icon(south_only = FALSE)
	return

/// Queuing a render doesn't sleep, keeps the old preview until the job lands,
/// and a stale render's result is discarded.
/datum/unit_test/dq_preview_async_discards_stale

/datum/unit_test/dq_preview_async_discards_stale/Run()
	var/datum/preferences/dq_preview_test_stub/prefs = new()
	var/datum/dq_preview_flattener/flattener = new
	var/list/flat_result = flattener.flatten(image('icons/effects/effects.dmi', "nothing"), SOUTH)
	TEST_ASSERT_NULL(flattener.unsupported, "flattener rejected a plain DMI image: [flattener.unsupported]")
	TEST_ASSERT_NOTNULL(flat_result, "flattener returned nothing for a plain DMI image")

	var/start_time = world.time
	var/stale_generation = prefs.dq_queue_preview_render(list("south" = flat_result[1]), list("bg" = "stale"))
	var/fresh_generation = prefs.dq_queue_preview_render(list("south" = flat_result[1]), list("bg" = "fresh"))
	TEST_ASSERT_EQUAL(world.time, start_time, "queuing a preview render slept in the caller")
	TEST_ASSERT_NULL(prefs.character_preview_b64, "the preview changed before the async job finished")

	var/deadline = world.time + 30 SECONDS
	UNTIL(!prefs.dq_preview_jobs_in_flight || world.time > deadline)
	TEST_ASSERT_EQUAL(prefs.dq_preview_jobs_in_flight, 0, "preview jobs never finished")
	TEST_ASSERT_NOTNULL(prefs.character_preview_b64, "the fresh render was never applied")
	TEST_ASSERT_EQUAL(prefs.character_preview_b64["bg"], "fresh", "a stale render overwrote the fresh one")
	TEST_ASSERT(length(prefs.character_preview_b64["south"]), "the fresh render has no south image")
	TEST_ASSERT(!prefs.dq_apply_preview_result(stale_generation, list("bg" = "stale")), "a stale result was applied")
	TEST_ASSERT(prefs.dq_apply_preview_result(fresh_generation, list("bg" = "fresh")), "the latest result was refused")
	qdel(prefs)

/// The iconforge preview matches getFlatIcon pixel for pixel on a real mannequin,
/// including a colour-matrix overlay and an offset overlay that forces a crop.
/datum/unit_test/dq_preview_async_matches_getflaticon

/datum/unit_test/dq_preview_async_matches_getflaticon/Run()
	var/mob/living/carbon/human/dummy/mannequin/mannequin = allocate(/mob/living/carbon/human/dummy/mannequin)
	mannequin.regenerate_icons()
	mannequin.ImmediateOverlayUpdate()
	TEST_ASSERT(length(mannequin.overlays), "mannequin has no overlays to test with")
	var/mutable_appearance/matrix_overlay = new(mannequin.overlays[1])
	matrix_overlay.color = list(0.5, 0.2, 0, 0, 0.1, 0.9, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0.1, 0, 0, 0)
	matrix_overlay.pixel_x = 9
	matrix_overlay.pixel_y = -5
	matrix_overlay.layer = 100
	var/mutable_appearance/tinted_overlay = new(mannequin.overlays[1])
	tinted_overlay.color = "#80ff40"
	tinted_overlay.alpha = 128
	tinted_overlay.layer = 101
	mannequin.add_overlay(list(matrix_overlay, tinted_overlay))
	mannequin.ImmediateOverlayUpdate()

	var/datum/dq_preview_flattener/flattener = new
	for(var/dir in GLOB.cardinal)
		mannequin.set_dir(dir)
		mannequin.ImmediateOverlayUpdate()
		// getFlatIcon's no_anim result is built by Insert() into a blank /icon, which reports
		// Width() 0; the animated result is the same image with its frames, so read frame 1 of that.
		var/icon/expected = getFlatIcon(mannequin, defdir = dir)
		var/list/flat_result = flattener.flatten(mannequin, dir)
		TEST_ASSERT_NULL(flattener.unsupported, "dir [dir]: fell back to getFlatIcon: [flattener.unsupported]")
		TEST_ASSERT_NOTNULL(flat_result, "dir [dir]: flattener returned nothing")
		dq_preview_ensure_dirs()
		var/out_path = "data/dq_previews/test_[dir].png"
		var/list/headless = rustg_iconforge_generate_headless(out_path, json_encode(list("preview" = flat_result[1])), TRUE)
		TEST_ASSERT(!length(headless["error"]), "dir [dir]: iconforge error: [headless["error"]]")
		TEST_ASSERT(rustg_file_exists(out_path), "dir [dir]: iconforge wrote no file ([json_encode(headless)])")
		var/icon/actual = icon(file(out_path))
		TEST_ASSERT_EQUAL(actual.Width(), expected.Width(), "dir [dir]: width differs")
		TEST_ASSERT_EQUAL(actual.Height(), expected.Height(), "dir [dir]: height differs")
		TEST_ASSERT_EQUAL(flat_result[2], expected.Width(), "dir [dir]: tracked width differs")
		TEST_ASSERT_EQUAL(flat_result[3], expected.Height(), "dir [dir]: tracked height differs")
		var/mismatches = 0
		var/worst = 0
		for(var/x in 1 to expected.Width())
			for(var/y in 1 to expected.Height())
				var/diff = dq_test_pixel_difference(expected.GetPixel(x, y, "", SOUTH, 1), actual.GetPixel(x, y))
				worst = max(worst, diff)
				// Allow off-by-a-few rounding in alpha compositing.
				if(diff > 3)
					mismatches++
		TEST_ASSERT_EQUAL(mismatches, 0, "dir [dir]: [mismatches] pixels differ from getFlatIcon (worst channel difference [worst])")
		fdel(out_path)

/// Largest per-channel difference between two GetPixel results. Colour is ignored where both are transparent.
/proc/dq_test_pixel_difference(expected, actual)
	var/list/a = expected ? rgb2num(expected) : list(0, 0, 0, 0)
	var/list/b = actual ? rgb2num(actual) : list(0, 0, 0, 0)
	var/alpha_a = length(a) >= 4 ? a[4] : 255
	var/alpha_b = length(b) >= 4 ? b[4] : 255
	var/diff = abs(alpha_a - alpha_b)
	if(alpha_a == 0 && alpha_b == 0)
		return diff
	for(var/channel in 1 to 3)
		diff = max(diff, abs(a[channel] - b[channel]))
	return diff
