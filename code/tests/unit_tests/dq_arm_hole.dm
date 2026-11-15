// The playtest fixture (a taur with wings, a lost right arm and a prosthetic left arm): what the client receives has no layer that erases the pixels
// of another, so the floor never shows through where the lost arm was. The empty space beside the torso is the gap of the wing sprite, which the arm fills when worn.

/// Every appearance under `I` (overlays and underlays, recursively) as one line each: the properties a client composes with.
/datum/unit_test/proc/dq_hole_dump(I, depth, list/into)
	for(var/kind in list("overlays", "underlays"))
		var/list/children = kind == "overlays" ? I:overlays : I:underlays
		for(var/part in children)
			var/mutable_appearance/MA = new(part)
			var/list/filter_names = list()
			for(var/filter in MA.filters)
				filter_names += "[filter:type]"
			into += "[depth]|[kind]|[MA.icon]|[MA.icon_state]|layer=[MA.layer]|plane=[MA.plane]|blend=[MA.blend_mode]|flags=[MA.appearance_flags]|alpha=[MA.alpha]|color=[islist(MA.color) ? "matrix" : MA.color]|filters=[jointext(filter_names, ",")]|px=[MA.pixel_x],[MA.pixel_y]|pw=[MA.pixel_w],[MA.pixel_z]|transform=[MA.transform ? "[MA.transform.a],[MA.transform.b],[MA.transform.c],[MA.transform.d],[MA.transform.e],[MA.transform.f]" : "none"]"
			dq_hole_dump(MA, depth + 1, into)

/// Whether any appearance under `I` erases pixels of the ones drawn before it: a subtracting, multiplying or inset blend, or a filter on an appearance that holds
/// others (an alpha mask on a leaf clips only that leaf, as the taur's clip mask clips a backpack). Returns the offending lines.
/datum/unit_test/proc/dq_hole_erasers(I, list/into)
	for(var/kind in list("overlays", "underlays"))
		var/list/children = kind == "overlays" ? I:overlays : I:underlays
		for(var/part in children)
			var/mutable_appearance/MA = new(part)
			if(MA.blend_mode == BLEND_SUBTRACT || MA.blend_mode == BLEND_MULTIPLY || MA.blend_mode == BLEND_INSET_OVERLAY)
				into += "blend [MA.blend_mode] on [MA.icon]/[MA.icon_state]"
			if(length(MA.filters) && (length(MA.overlays) || length(MA.underlays)))
				into += "a filter on the group [MA.icon]/[MA.icon_state]"
			dq_hole_erasers(MA, into)
	return into

/datum/unit_test/dq_arm_hole_dump

/datum/unit_test/dq_arm_hole_dump/Run()
	test_driver_begin()
	var/mob/living/carbon/human/H = dq_real_character("playtest_arm_character")
	TEST_ASSERT_NULL(H.limb_tagged(BP_R_ARM), "the right arm is amputated")
	var/list/bad = list()
	for(var/d in list(SOUTH, NORTH, EAST, WEST))
		H.set_dir(d)
		H.animate_tail_stop()
		refresh_flush()
		draw_now(H)
		var/list/lines = list()
		var/list/filter_names = list()
		for(var/filter in H.filters)
			filter_names += "[filter:type]"
		lines += "ROOT|[H.icon]|[H.icon_state]|flags=[H.appearance_flags]|blend=[H.blend_mode]|alpha=[H.alpha]|filters=[jointext(filter_names, ",")]|dir=[H.dir]"
		dq_hole_dump(H, 1, lines)
		for(var/line in lines)
			TEST_NOTICE(src, "HOLEDUMP [dir2text(d)] [line]")
		if(length(H.filters))
			bad += "[dir2text(d)]: the human itself carries a filter"
		for(var/found in dq_hole_erasers(H, list()))
			bad += "[dir2text(d)]: [found]"
		// The wing's pixels that nothing above it covers are all in the composed picture (the missing arm leaves the wing and body behind it showing).
		var/list/layers = H.look_layers()
		var/image/wings = layers[WING_LAYER]
		var/icon/wing_flat = getFlatIcon(wings, d, no_anim = TRUE)
		var/icon/whole = getFlatIcon(H, d, no_anim = TRUE)
		var/list/covers = list()
		for(var/index in 1 to TOTAL_LAYERS)
			var/entry = layers[index]
			for(var/image/over in (islist(entry) ? entry : list(entry)))
				if(over && over != wings && over.layer >= wings.layer && (over.plane == FLOAT_PLANE || over.plane == H.plane))
					covers |= dq_real_pixels(over, d)
		var/lost = 0
		for(var/x in 1 to wing_flat.Width())
			for(var/y in 1 to wing_flat.Height())
				var/colour = wing_flat.GetPixel(x, y)
				if(colour && !("[x],[y]" in covers) && !whole.GetPixel(x, y))
					lost++
		if(lost)
			bad += "[dir2text(d)]: [lost] wing pixels are not drawn"
	TEST_ASSERT(!length(bad), "an erasing layer in the playtest character: [jointext(bad, "; ")]")
	test_driver_end()
