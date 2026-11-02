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

/// Examining an emptied ballistic gun's firepower doesn't index an empty magazine (contents[1] ran out of bounds).
/datum/unit_test/dq_health_bughunt/empty_gun_firepower

/datum/unit_test/dq_health_bughunt/empty_gun_firepower/Run()
	var/obj/item/gun/projectile/G = allocate(/obj/item/gun/projectile, test_floor())
	var/list/casings = list()
	for(var/obj/item/ammo_casing/C in G.contents)
		casings += C
	if(G.ammo_magazine)
		for(var/obj/item/ammo_casing/C in G.ammo_magazine.contents)
			casings += C
	for(var/obj/item/ammo_casing/C in casings)
		C.forceMove(test_floor())
		own(C)
	if(!G.chambered)
		TEST_ASSERT_NULL(G.first_loaded_casing(), "an emptied gun has no casing to read")
	TEST_ASSERT(istext(G.describe_firepower()), "the firepower line is still written")
	TEST_ASSERT(istext(G.describe_proj_penetration()), "the penetration line is still written")
