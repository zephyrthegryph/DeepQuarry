/**
 * Turf edges (code/game/turfs/turf_edges.dm): a turf's draw reads its own tracked state and the masks the adjacency index keeps, never a
 * neighbour. Each test changes a neighbour and checks that the mask and the look of the turf beside it follow, through the index, with no hand
 * redraw. Two tiles of a row east of the test floor are used and put back.
 */

/// The two tiles (east of the test floor) a test works on, and what they were. A tile that is changed is a new object: the tests hold where
/// it is and read it again.
/datum/unit_test/dq_turf_edges
	var/list/first_at
	var/list/second_at
	var/first_type
	var/second_type

/datum/unit_test/dq_turf_edges/proc/take_tiles()
	var/turf/T = test_floor()
	var/turf/first = get_step(T, EAST)
	var/turf/second = get_step(first, EAST)
	TEST_ASSERT(istype(first, /turf/simulated) && istype(second, /turf/simulated), "the test map has two simulated tiles east of the test floor")
	first_at = list(first.x, first.y, first.z)
	second_at = list(second.x, second.y, second.z)
	first_type = first.type
	second_type = second.type

/datum/unit_test/dq_turf_edges/proc/first_tile()
	RETURN_TYPE(/turf)
	return locate(first_at[1], first_at[2], first_at[3])

/datum/unit_test/dq_turf_edges/proc/second_tile()
	RETURN_TYPE(/turf)
	return locate(second_at[1], second_at[2], second_at[3])

/// Makes the first tile a turf of `type` and settles the draws; returns it.
/datum/unit_test/dq_turf_edges/proc/make_first(type)
	RETURN_TYPE(/turf)
	var/turf/made = first_tile().ChangeTurf(type)
	appearance_flush()
	return made

/datum/unit_test/dq_turf_edges/proc/make_second(type)
	RETURN_TYPE(/turf)
	var/turf/made = second_tile().ChangeTurf(type)
	appearance_flush()
	return made

/datum/unit_test/dq_turf_edges/proc/put_tiles_back()
	make_first(first_type)
	make_second(second_type)

/// How many overlays of the turf show `state`.
/datum/unit_test/dq_turf_edges/proc/overlays_showing(turf/T, state)
	var/count = 0
	for(var/image/overlay_image in T.overlays)
		if(overlay_image.icon_state == state)
			count++
	return count

// ---- a floor: its edges follow a neighbour's flooring ----

/datum/unit_test/dq_turf_edges/flooring_change_redraws_neighbour/Run()
	take_tiles()
	var/turf/simulated/floor/A = make_first(/turf/simulated/floor/grass)
	var/turf/simulated/floor/B = make_second(/turf/simulated/floor/grass)
	TEST_ASSERT(!(A.edge_mask & EAST), "grass beside grass has no border on that side: [A.edge_mask]")
	var/overlays_before = length(A.overlays)
	var/key_before = A.rx?.look_key

	B.install_flooring(get_flooring_data(/datum/decl/flooring/tiling))
	appearance_flush()
	TEST_ASSERT(A.edge_mask & EAST, "grass beside another flooring has a border on that side: [A.edge_mask]")
	TEST_ASSERT(length(A.overlays) > overlays_before, "the edge overlay is drawn on the grass ([length(A.overlays)] vs [overlays_before])")
	TEST_ASSERT(A.rx?.look_key != key_before, "the grass redrew with no update_icon() call")

	B.install_flooring(get_flooring_data(/datum/decl/flooring/grass))
	appearance_flush()
	TEST_ASSERT(!(A.edge_mask & EAST), "and the border goes when the neighbour is grass again: [A.edge_mask]")
	TEST_ASSERT_EQUAL(length(A.overlays), overlays_before, "with its overlay")
	put_tiles_back()

// ---- walls: building one or removing one updates the mask and the look beside it ----

/datum/unit_test/dq_turf_edges/wall_updates_neighbours/Run()
	take_tiles()
	// A wall beside a wall joins it.
	var/turf/simulated/wall/W = make_first(/turf/simulated/wall)
	var/connections_alone = W.get_wall_connections()
	var/key_alone = W.rx?.look_key
	make_second(/turf/simulated/wall)
	TEST_ASSERT(W.smooth_mask & EAST, "a wall built beside a wall is in its mask: [W.smooth_mask]")
	TEST_ASSERT(W.get_wall_connections() != connections_alone, "the wall's connections follow")
	TEST_ASSERT(W.rx?.look_key != key_alone, "the wall redrew with no update_icon() call")
	make_second(/turf/simulated/floor/plating)
	TEST_ASSERT(!(W.smooth_mask & EAST), "removing the wall takes it out of the mask again: [W.smooth_mask]")
	TEST_ASSERT_EQUAL(W.get_wall_connections(), connections_alone, "and the connections go back")

	// A floor beside a wall has a border toward it (grass does not smooth with walls).
	var/turf/simulated/floor/F = make_first(/turf/simulated/floor/grass)
	make_second(/turf/simulated/wall)
	TEST_ASSERT(F.edge_mask & EAST, "a floor beside a built wall has a border on that side: [F.edge_mask]")
	var/overlays_with_wall = length(F.overlays)
	make_second(/turf/simulated/floor/grass)
	TEST_ASSERT(!(F.edge_mask & EAST), "and none once the wall is removed: [F.edge_mask]")
	TEST_ASSERT(length(F.overlays) < overlays_with_wall, "with the edge it drew")

	// A rock wall shows a lip toward an open tile and loses it when the tile becomes rock.
	var/turf/simulated/wall/solidrock/R = make_first(/turf/simulated/wall/solidrock)
	make_second(/turf/simulated/floor/plating)
	TEST_ASSERT(R.open_mask & EAST, "a rock wall beside an open tile has that side open: [R.open_mask]")
	var/rock_key = R.rx?.look_key
	make_second(/turf/simulated/wall/solidrock)
	TEST_ASSERT(!(R.open_mask & EAST), "and closed beside rock: [R.open_mask]")
	TEST_ASSERT(R.rx?.look_key != rock_key, "the rock redrew with no hand redraw")
	put_tiles_back()

// ---- water: the edges that spill onto it follow its neighbours ----

/datum/unit_test/dq_turf_edges/water_follows_neighbours/Run()
	take_tiles()
	// Shallow water (edge priority -1) spills its edge onto deep water (-2) beside it.
	var/turf/simulated/floor/water/deep/D = make_first(/turf/simulated/floor/water/deep)
	make_second(/turf/simulated/floor/plating)
	TEST_ASSERT(!length(D.edge_spill), "deep water beside plating has no edge spilling onto it")
	var/key_before = D.rx?.look_key

	make_second(/turf/simulated/floor/water)
	TEST_ASSERT(length(D.edge_spill), "deep water beside shallow water takes its edge")
	TEST_ASSERT(D.rx?.look_key != key_before, "the deep water redrew with no update_icon() call")

	make_second(/turf/simulated/floor/plating)
	TEST_ASSERT(!length(D.edge_spill), "and loses it when the shallow water is gone")

	// The water sprite is drawn once, however often the tile redraws.
	TEST_ASSERT_EQUAL(overlays_showing(D, D.water_state), 1, "the water sprite is on the tile once")
	var/shown_state = D.water_state
	D.set_water_state("water_deep")
	appearance_flush()
	D.set_water_state(shown_state)
	appearance_flush()
	TEST_ASSERT_EQUAL(overlays_showing(D, D.water_state), 1, "and still once after the state changed and came back")
	put_tiles_back()

// ---- ChangeTurf: the mask of the new turf and of its neighbours is right when it is done ----

/datum/unit_test/dq_turf_edges/mask_after_change_turf/Run()
	take_tiles()
	var/turf/simulated/floor/A = make_first(/turf/simulated/floor/grass)
	var/turf/simulated/floor/B = make_second(/turf/simulated/floor/grass)
	TEST_ASSERT(!(A.edge_mask & EAST) && !(B.edge_mask & WEST), "two grass tiles are joined: [A.edge_mask] [B.edge_mask]")

	// Replaced by a member of the index (a wall) and by a turf that is not one (space).
	make_second(/turf/simulated/wall)
	TEST_ASSERT(A.edge_mask & EAST, "grass beside a wall put where the grass was has a border: [A.edge_mask]")
	make_second(/turf/space)
	TEST_ASSERT(A.edge_mask & EAST, "grass beside space has a border: [A.edge_mask]")
	B = make_second(/turf/simulated/floor/grass)
	TEST_ASSERT(!(A.edge_mask & EAST), "and none once there is grass again: [A.edge_mask]")
	TEST_ASSERT(!(B.edge_mask & WEST), "the new grass is joined to the old: [B.edge_mask]")

	// The tile that was changed reads its neighbours: a floor made beside a wall knows it at once.
	var/turf/simulated/wall/W = make_first(/turf/simulated/wall)
	var/turf/simulated/floor/N = make_second(/turf/simulated/floor/grass)
	TEST_ASSERT(N.edge_mask & WEST, "a floor made beside a wall has a border toward it: [N.edge_mask]")
	TEST_ASSERT(!(W.smooth_mask & EAST), "and the wall does not join a floor")
	put_tiles_back()
