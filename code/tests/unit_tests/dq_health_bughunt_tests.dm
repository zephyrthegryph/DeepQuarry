// Live bugs found from dm-health baseline rows (tools/dm-health/baseline.json).

/datum/unit_test/dq_health_bughunt
	abstract_type = /datum/unit_test/dq_health_bughunt

/// RGBMatrixTransform reads every input channel before writing, uses BYOND's matrix order, and leaves
/// the caller's lists alone (it overwrote red before computing green from it and used the transpose).
/datum/unit_test/dq_health_bughunt/rgb_matrix_transform

/datum/unit_test/dq_health_bughunt/rgb_matrix_transform/Run()
	var/list/identity = list(1,0,0, 0,1,0, 0,0,1)
	TEST_ASSERT_EQUAL(lowertext(RGBMatrixTransform("#336699", identity)), "#336699", "the identity matrix keeps the colour")
	TEST_ASSERT_EQUAL(length(identity), 9, "the caller's matrix is not padded")
	// Swap red and blue: output red takes input blue (br = 1), output blue takes input red (rb = 1).
	var/list/swap = list(0,0,1, 0,1,0, 1,0,0)
	TEST_ASSERT_EQUAL(lowertext(RGBMatrixTransform("#ff0000", swap)), "#0000ff", "red moves to blue")
	TEST_ASSERT_EQUAL(lowertext(RGBMatrixTransform("#0000ff", swap)), "#ff0000", "blue moves to red, read before red is written")
	// Red feeds green only (rg = 1): pure red turns pure green.
	var/list/red_to_green = list(0,1,0, 0,0,0, 0,0,0)
	TEST_ASSERT_EQUAL(lowertext(RGBMatrixTransform("#ff0000", red_to_green)), "#00ff00", "rg routes input red to output green")
	var/list/input = list(10, 20, 30)
	RGBMatrixTransform(input, list(2,0,0, 0,2,0, 0,0,2))
	TEST_ASSERT_EQUAL(input[1], 10, "an input list is not overwritten")
	TEST_ASSERT_EQUAL(lowertext(RGBMatrixTransform("#ffffff", list(2,0,0, 0,2,0, 0,0,2, 0,0,0))), "#ffffff", "outputs clamp to 255")

/// A human shocked with stun = 0 is not stunned: the human override dropped `stun` when it called up.
/datum/unit_test/dq_health_bughunt/human_shock_honours_stun

/datum/unit_test/dq_health_bughunt/human_shock_honours_stun/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.electrocute_act(23, null, 1, BP_TORSO, 0)
	for(var/obj/effect/effect/sparks/S in range(3, get_turf(H)))
		own(S)
	TEST_ASSERT(!H.has_status(STAT_WEAKENED) && !H.has_status(STAT_STUNNED), "stun = 0 leaves the human standing")
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, test_floor())
	other.electrocute_act(23, null, 1, BP_TORSO)
	for(var/obj/effect/effect/sparks/S in range(3, get_turf(other)))
		own(S)
	TEST_ASSERT(other.has_status(STAT_WEAKENED), "the default still knocks a human down")

/// A lightning bolt shocks a human's torso by zone tag (it passed the organ object as the zone) and leaves them standing.
/datum/unit_test/dq_health_bughunt/lightning_shock_zone
	var/list/zones = list()

/datum/unit_test/dq_health_bughunt/lightning_shock_zone/proc/on_injured(datum/act/notice/A)
	var/datum/notice/living_injured/event = A
	zones += event.zone

/datum/unit_test/dq_health_bughunt/lightning_shock_zone/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/projectile/beam/lightning/bolt = allocate(/obj/item/projectile/beam/lightning, test_floor())
	bolt.power = 20
	observe(H, /datum/notice/living_injured, src, then(PROC_REF(on_injured)))
	bolt.attack_mob(H, 1)
	unobserve(H, /datum/notice/living_injured, src)
	for(var/obj/effect/effect/sparks/S in range(3, get_turf(H)))
		own(S)
	TEST_ASSERT(length(zones), "the bolt injured the human")
	for(var/zone in zones)
		TEST_ASSERT(isnull(zone) || istext(zone), "a shock zone is a tag, not [zone] ([isdatum(zone) ? "a datum" : "other"])")
	TEST_ASSERT(BP_TORSO in zones, "the bolt hits the torso: [jointext(zones, ", ")]")
	TEST_ASSERT(!H.has_status(STAT_WEAKENED), "a lightning bolt does not stun")

/// Examining a magazine gun whose magazine is in but empty and whose chamber is empty: the firepower lines read no
/// projectile instead of indexing the empty magazine (contents[1] ran out of bounds).
/datum/unit_test/dq_health_bughunt/empty_gun_firepower

/datum/unit_test/dq_health_bughunt/empty_gun_firepower/Run()
	var/obj/item/gun/projectile/colt/G = allocate(/obj/item/gun/projectile/colt, test_floor())
	TEST_ASSERT(G.ammo_magazine, "the colt starts with a magazine in")
	var/obj/item/ammo_magazine/M = G.ammo_magazine
	while(length(M.stored_ammo))
		var/obj/item/ammo_casing/C = M.stored_ammo[1]
		own_remove(M, nameof(M.stored_ammo), C)
	while(length(G.loaded))
		var/obj/item/ammo_casing/C = G.loaded[1]
		own_remove(G, nameof(G.loaded), C)
	if(G.chambered)
		rel_set(G, nameof(G.chambered), null)
	TEST_ASSERT_EQUAL(length(M.stored_ammo), 0, "the magazine is empty")
	TEST_ASSERT_EQUAL(length(M.contents), 0, "no casing is left in the magazine's contents")
	TEST_ASSERT_NULL(G.chambered, "nothing is chambered")
	TEST_ASSERT_NULL(G.first_loaded_casing(), "an empty gun has no casing to read")
	TEST_ASSERT_EQUAL(G.describe_firepower(), "no", "the firepower line says no")
	TEST_ASSERT_EQUAL(G.describe_proj_penetration(), "no", "the penetration line says no")

/// A camp-list save cut short by a crash is discarded at boot instead of throwing out of the Job system's init.
/datum/unit_test/dq_health_bughunt/job_camp_list_truncated

/datum/unit_test/dq_health_bughunt/job_camp_list_truncated/Run()
	var/list/before = SSjob.restricted_keys
	var/path = SSjob.savepath
	TEST_ASSERT(!fexists(path), "no camp list is waiting in the test world")
	text2file(copytext(json_encode(list("ckey" = list(1, 2))), 1, 10), path) // cut short mid-write
	var/list/saved_capture = GLOB.dq_caught_capture
	GLOB.dq_caught_capture = list()
	SSjob.load_camp_lists()
	var/list/capture = GLOB.dq_caught_capture
	GLOB.dq_caught_capture = saved_capture
	TEST_ASSERT_EQUAL(length(capture), 1, "the bad file is reported once")
	TEST_ASSERT(!fexists(path), "the bad file is removed")
	TEST_ASSERT(SSjob.restricted_keys == before, "a bad file leaves the list alone")
	text2file(json_encode(list("somebody" = 1)), path)
	SSjob.load_camp_lists()
	TEST_ASSERT(SSjob.restricted_keys["somebody"] == 1, "a good file still loads")
	SSjob.restricted_keys = before

/// A teppi's carried-over data keeps its nutrition under the key the reader uses (a codemod renamed the key to "nutrition_of(src)").
/datum/unit_test/dq_health_bughunt/teppi_data_keeps_nutrition

/datum/unit_test/dq_health_bughunt/teppi_data_keeps_nutrition/Run()
	var/mob/living/simple_mob/vore/alienanimals/teppi/T = allocate(/mob/living/simple_mob/vore/alienanimals/teppi, test_floor())
	T.set_nutrition(321)
	var/list/data = T.store_teppi_data(T)
	TEST_ASSERT_EQUAL(data["nutrition"], 321, "the stored nutrition is read back by its key")

/// The melee line of an item's mechanics examine says "sharp", not the code that decides it.
/datum/unit_test/dq_health_bughunt/sharp_examine_text

/datum/unit_test/dq_health_bughunt/sharp_examine_text/Run()
	var/obj/item/material/knife/K = allocate(/obj/item/material/knife, test_floor())
	var/result = K.get_mechanics_info()
	var/text = islist(result) ? jointext(result, " ") : "[result]"
	TEST_ASSERT(!findtext(text, "combat_of"), "examine text leaks code: [text]")
	TEST_ASSERT(findtext(text, "sharp damage"), "a knife's melee line says sharp: [text]")

/// Program windows theme themselves from the header's PC_device_theme (the header sent only device_theme to the main menu).
/datum/unit_test/dq_health_bughunt/ntos_header_theme

/datum/unit_test/dq_health_bughunt/ntos_header_theme/Run()
	var/obj/item/modular_computer/tablet/T = allocate(/obj/item/modular_computer/tablet, test_floor())
	var/list/header = T.get_header_data()
	TEST_ASSERT_EQUAL(header["PC_device_theme"], T.device_theme, "the header carries the device theme")
