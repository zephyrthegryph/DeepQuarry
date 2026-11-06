/// A turned overlay image renders in the dir it was given: the shuttle corners' lighting "diagonals" overlay in a diagonal dir is a white half-tile
/// and in a cardinal dir a pink X (the guide drawing), which the players saw in the transparent part of the corner walls.
/datum/unit_test/dq_overlay_dir_renders

/// A holder with no sprite of its own, facing south.
/obj/effect/dq_dir_probe
	icon = null
	icon_state = null
	dir = SOUTH

/datum/unit_test/dq_overlay_dir_renders/proc/flat_counts(atom/A)
	var/icon/F = getFlatIcon(A)
	var/pink = 0
	for(var/x in 1 to 32)
		for(var/y in 1 to 32)
			if(F.GetPixel(x, y) == "#ff0099")
				pink++
	return pink

/datum/unit_test/dq_overlay_dir_renders/Run()
	var/obj/effect/dq_dir_probe/probe = allocate(/obj/effect/dq_dir_probe)
	for(var/diag in list(NORTHEAST, NORTHWEST, SOUTHEAST, SOUTHWEST))
		probe.cut_overlays()
		probe.overlays += look_overlay_image(LIGHTING_ICON, "diagonals", layer = 10, dir = diag)
		TEST_ASSERT_EQUAL(flat_counts(probe), 0, "the diagonals overlay turned to [diag] shows the pink X guide: its dir was dropped")
	probe.cut_overlays()

/// The same from an atom (`of`): the dir is built into the image, not assigned after it.
/datum/unit_test/dq_overlay_dir_renders_of

/datum/unit_test/dq_overlay_dir_renders_of/Run()
	var/obj/effect/dq_dir_probe/probe = allocate(/obj/effect/dq_dir_probe)
	var/obj/effect/dq_dir_probe/source = allocate(/obj/effect/dq_dir_probe)
	source.set_icon(LIGHTING_ICON)
	source.set_icon_state("diagonals")
	for(var/diag in list(NORTHEAST, NORTHWEST, SOUTHEAST, SOUTHWEST))
		probe.cut_overlays()
		probe.overlays += look_overlay_image(of = source, layer = 10, dir = diag)
		var/icon/flat = getFlatIcon(probe)
		var/pink = 0
		for(var/x in 1 to 32)
			for(var/y in 1 to 32)
				if(flat.GetPixel(x, y) == "#ff0099")
					pink++
		TEST_ASSERT_EQUAL(pink, 0, "an overlay built from an atom and turned to [diag] shows the pink X guide: its dir was dropped")
	probe.cut_overlays()

