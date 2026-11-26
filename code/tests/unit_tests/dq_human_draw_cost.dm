// What drawing a human costs on the main thread (code/content/mob/living/carbon/human/human_look.dm). The look cache counts its builds, the /icon
// operations they made and the time they took (/datum/human_look_stats). A plain body, its hair, eyes and clothes are tinted overlays the client
// layers: no /icon operation. A second body that looks like the first builds nothing, and a change to one part builds only that part.

/// Draws a freshly made, fully dressed human of `species` and returns list(builds, icon ops, ms, the human) the draw cost.
/datum/unit_test/proc/dq_hdc_draw_dressed(species = SPECIES_HUMAN)
	var/builds = GLOB.human_look_builds
	var/ops = GLOB.human_look_icon_ops
	var/ms = GLOB.human_look_build_ms
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.set_species(species)
	H.set_tail_anim_state("[H.species.get_tail(H)]_idle0") // an animated tail idles on a loop picked per mob; two bodies that look alike share one
	dq_profile_dress(H, -40)
	dq_hd_dress(H)
	refresh_flush()
	return list(GLOB.human_look_builds - builds, GLOB.human_look_icon_ops - ops, GLOB.human_look_build_ms - ms, H)

/// A plain human is drawn with no /icon operation, cold or warm.
/datum/unit_test/dq_human_draw_plain_body_makes_no_icon_operations

/datum/unit_test/dq_human_draw_plain_body_makes_no_icon_operations/Run()
	var/list/cold = dq_hdc_draw_dressed()
	TEST_NOTICE(src, "HUMAN_DRAW_COST cold human: [cold[1]] builds, [cold[2]] icon operations, [round(cold[3], 0.1)] ms")
	TEST_ASSERT_EQUAL(cold[2], 0, "a plain human was drawn with /icon operations: [human_look_stats_line()]")

/// A second body that looks like the first draws from the cache alone: no build, no /icon operation.
/datum/unit_test/dq_human_draw_warm_builds_nothing

/datum/unit_test/dq_human_draw_warm_builds_nothing/Run()
	for(var/species in list(SPECIES_HUMAN, SPECIES_TAJARAN, SPECIES_UNATHI))
		dq_hdc_draw_dressed(species)
		var/list/warm = dq_hdc_draw_dressed(species)
		TEST_ASSERT_EQUAL(warm[1], 0, "a warm [species] draw built a look icon: [human_look_stats_line()]")
		TEST_ASSERT_EQUAL(warm[2], 0, "a warm [species] draw made /icon operations: [human_look_stats_line()]")

/// Changing one part redraws that part only: a new hair colour builds the hair, not the body, the eyes, the tail or the clothes.
/datum/unit_test/dq_human_draw_one_part_change_builds_only_that_part

/datum/unit_test/dq_human_draw_one_part_change_builds_only_that_part/Run()
	var/list/first = dq_hdc_draw_dressed()
	var/mob/living/carbon/human/H = first[4]
	var/builds = GLOB.human_look_builds
	var/ops = GLOB.human_look_icon_ops
	H.looks.set_hair_color(rgb(12, 200, 99))
	refresh_flush()
	TEST_ASSERT(GLOB.human_look_builds - builds <= 1, "a hair colour change built [GLOB.human_look_builds - builds] look icons: [human_look_stats_line()]")
	TEST_ASSERT_EQUAL(GLOB.human_look_icon_ops, ops, "a hair colour change made /icon operations: [human_look_stats_line()]")
	for(var/entry in GLOB.human_look_recent.Copy(max(1, length(GLOB.human_look_recent) - (GLOB.human_look_builds - builds) + 1)))
		TEST_ASSERT(findtext(entry, "build_hair_look") == 1, "a hair colour change built something other than the hair: [entry]")
	// A cost that does not grow with the number of draws: a hundred redraws of an unchanged body build nothing.
	builds = GLOB.human_look_builds
	for(var/i in 1 to 100)
		H.set_dir(i % 2 ? NORTH : SOUTH)
		refresh_flush()
	TEST_ASSERT_EQUAL(GLOB.human_look_builds, builds, "turning round built look icons: [human_look_stats_line()]")
