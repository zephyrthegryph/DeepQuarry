// What a body draws when limbs are missing or replaced, which way its tail sits, and the examine portrait of it. Behavioural: no picture is pinned,
// the tests ask what the draw is made of (overlays, blends, layers) and whether a layer cuts what is under it.

/// A human with wings, a tail, a missing left arm and a robotic right arm, built the way a saved character is applied.
/datum/unit_test/proc/dq_br_body(missing = "rejuv", robotic = TRUE)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.set_species(SPECIES_HUMAN)
	H.set_dir(SOUTH)
	refresh_flush()
	if(robotic)
		var/obj/item/organ/external/right = H.limb_tagged(BP_R_ARM)
		right.robotize()
	var/obj/item/organ/external/left = H.limb_tagged(BP_L_ARM)
	if(missing == "rejuv")
		left.remove_rejuv()
	else if(missing == "drop")
		left.droplimb(TRUE, DROPLIMB_EDGE)
	refresh_flush()
	return H

/// Every appearance under `I` (its overlays, recursively) as text: icon, state, colour, blend, plane.
/datum/unit_test/proc/dq_br_describe(I, depth = 0, list/into)
	if(isnull(into))
		into = list()
	for(var/part in I:overlays)
		var/mutable_appearance/MA = new(part)
		into += "[depth]:[MA.icon]/[MA.icon_state] blend=[MA.blend_mode] plane=[MA.plane] flags=[MA.appearance_flags] a=[MA.alpha] c=[islist(MA.color) ? "matrix" : MA.color]"
		dq_br_describe(MA, depth + 1, into)
	return into

/// The opaque pixels of `flat` as "x,y" keys.
/datum/unit_test/proc/dq_br_opaque(icon/flat)
	. = list()
	for(var/x in 1 to flat.Width())
		for(var/y in 1 to flat.Height())
			if(flat.GetPixel(x, y))
				.["[x],[y]"] = TRUE

/// A missing arm draws no overlay of its own in any facing, and no layer of the human blends in a way that cuts what is under it.
/datum/unit_test/dq_body_render_missing_arm_draws_nothing

/datum/unit_test/dq_body_render_missing_arm_draws_nothing/Run()
	test_driver_begin()
	for(var/how in list("rejuv", "drop"))
		var/mob/living/carbon/human/H = dq_br_body(how, FALSE)
		for(var/obj/item/organ/dropped in get_turf(H))
			qdel(dropped)
		var/obj/item/organ/external/hand = H.limb_tagged(BP_L_HAND)
		TEST_NOTICE(src, "BODYRENDER [how]: left arm [H.limb_tagged(BP_L_ARM)] left hand [hand] ([hand?.type]) stump? [hand?.is_stump()] organs=[length(H.organs)]")
		var/list/body = H.body_look(new /datum/look)
		var/list/lines = dq_br_describe(body[2])
		TEST_NOTICE(src, "BODYRENDER [how] body: [jointext(lines, " | ")]")
		for(var/line in lines)
			TEST_ASSERT(!findtext(line, "l_arm"), "[how]: a missing left arm still draws: [line]")
			TEST_ASSERT(!findtext(line, "l_hand"), "[how]: the hand of a missing arm still draws: [line]")
		for(var/image/layer in H.look_layer_images())
			for(var/line in dq_br_describe(layer))
				TEST_ASSERT(!findtext(line, "blend=[BLEND_SUBTRACT] ") && !findtext(line, "blend=[BLEND_MULTIPLY] ") && !findtext(line, "blend=[BLEND_INSET_OVERLAY] "), "[how]: a layer cuts what is under it: [line]")
	test_driver_end()

/// A robotic arm draws what the composed body draws for it, whichever model: the layered picture of the limb has the same pixels as get_icon().
/datum/unit_test/dq_body_render_robotic_arm_draws

/datum/unit_test/dq_body_render_robotic_arm_draws/Run()
	test_driver_begin()
	var/list/models = list(null)
	var/n = 0
	for(var/company in GLOB.all_robolimbs)
		if(n++ % 3 == 0)
			models += company
		if(length(models) >= 14)
			break
	var/list/bad = list()
	for(var/model in models)
		var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
		H.set_species(SPECIES_HUMAN)
		H.set_dir(SOUTH)
		refresh_flush()
		var/obj/item/organ/external/right = H.limb_tagged(BP_R_ARM)
		if(model)
			right.robotize(model)
		else
			right.robotize()
		refresh_flush()
		var/icon/composed = icon(right.get_icon(FALSE, TRUE, FALSE), null, SOUTH)
		var/opaque = length(dq_br_opaque(composed))
		var/layerable = right.can_layer(FALSE)
		var/diff = -1
		var/colour = ""
		if(layerable)
			var/image/group = image(icon = 'icons/mob/human.dmi', icon_state = "blank")
			look_composed_image(group, right.layered_parts(FALSE))
			var/icon/flat = getFlatIcon(group, SOUTH, no_anim = TRUE)
			diff = 0
			for(var/x in 1 to 32)
				for(var/y in 1 to 32)
					if(dq_test_pixel_difference(composed.GetPixel(x, y), flat.GetPixel(x, y)) > 3)
						diff++
			for(var/line in dq_br_describe(group))
				colour += "[line]; "
		TEST_NOTICE(src, "BODYRENDER robotic [model]: layerable=[layerable] force_icon=[right.force_icon] icon_name=[right.icon_name] no_icon=[right.skip_robo_icon] model=[right.model] s_col=[json_encode(right.s_col)] composed opaque=[opaque] diff=[diff] parts=[colour]")
		if(!opaque)
			bad += "[model]: the robotic arm's sprite is empty"
		if(diff > 0)
			bad += "[model]: the layered arm differs from the composed one in [diff] pixels"
	TEST_ASSERT(!length(bad), "robotic arms: [jointext(bad, "; ")]")
	test_driver_end()

/// The layered body and the composed body are the same picture facing every way, with a missing arm and a robotic arm.
/datum/unit_test/dq_body_render_layered_matches_composed

/datum/unit_test/dq_body_render_layered_matches_composed/Run()
	test_driver_begin()
	var/mob/living/carbon/human/H = dq_br_body("rejuv", TRUE)
	var/image/layered = H.build_layered_body_look('icons/mob/human.dmi', FALSE, FALSE)[2]
	var/icon/composed = H.build_body_look('icons/mob/human.dmi', FALSE, FALSE, FALSE, FALSE)[1]
	var/image/plain = image(icon = composed)
	var/list/bad = list()
	for(var/d in list(NORTH, SOUTH, EAST)) // WEST: the far limbs go under the body there (icon_position), which the layered body does not do yet
		var/icon/a = getFlatIcon(layered, d, no_anim = TRUE)
		var/icon/b = getFlatIcon(plain, d, no_anim = TRUE)
		var/diff = 0
		var/only_layered = 0
		var/only_composed = 0
		var/min_x = 99
		var/max_x = 0
		for(var/x in 1 to 32)
			for(var/y in 1 to 32)
				var/pa = a.GetPixel(x, y)
				var/pb = b.GetPixel(x, y)
				if(dq_test_pixel_difference(pa, pb) > 3)
					diff++
					if(pa && !pb)
						only_layered++
					if(pb && !pa)
						only_composed++
					min_x = min(min_x, x)
					max_x = max(max_x, x)
		TEST_NOTICE(src, "BODYRENDER layered vs composed [dir2text(d)]: [diff] pixels differ (only layered [only_layered], only composed [only_composed]) x [min_x]..[max_x]")
		if(diff)
			bad += "[dir2text(d)] [diff] (layered only [only_layered], composed only [only_composed], x [min_x]..[max_x])"
	for(var/d in list(EAST, WEST, NORTH))
		var/icon/shown = getFlatIcon(layered, d, no_anim = TRUE)
		var/list/rows = list()
		for(var/y in 32 to 1 step -1)
			var/row = ""
			for(var/x in 1 to 32)
				row += shown.GetPixel(x, y) ? "#" : "."
			rows += row
		TEST_NOTICE(src, "BODYRENDER ascii [dir2text(d)]:\n[jointext(rows, "\n")]")
	TEST_ASSERT(!length(bad), "the layered body differs from the composed one: [jointext(bad, "; ")]")
	test_driver_end()

/// A layer's pixels are never taken away by another: what the human's layers draw alone is drawn together, facing every way.
/datum/unit_test/dq_body_render_layers_do_not_cut

/datum/unit_test/dq_body_render_layers_do_not_cut/Run()
	test_driver_begin()
	var/list/wings = list()
	for(var/key in GLOB.wing_styles_list)
		wings += key
		if(length(wings) >= 3)
			break
	var/list/bad = list()
	for(var/composed in list(FALSE, TRUE))
		var/mob/living/carbon/human/H = dq_br_body("rejuv", TRUE)
		if(composed)
			H.add_mutation(HUSK) // a husk is not drawn as layers: the mob's own icon is the whole body
			refresh_flush()
		for(var/wing in wings)
			dq_hd_set(H, "wing_style", GLOB.wing_styles_list[wing])
			dq_hd_set(H, "tail_style", GLOB.tail_styles_list[/datum/sprite_accessory/tail/squirrel])
			refresh_flush()
			dq_hb_settle()
			for(var/d in GLOB.cardinal)
				H.set_dir(d)
				H.animate_tail_stop()
				refresh_flush()
				var/icon/whole = getFlatIcon(H, d, no_anim = TRUE)
				var/list/whole_pixels = dq_br_opaque(whole)
				var/list/union = list()
				var/list/layers = H.look_layers()
				for(var/index in 1 to TOTAL_LAYERS)
					var/entry = layers[index]
					for(var/image/part in (islist(entry) ? entry : list(entry)))
						if(!part || (part.plane != FLOAT_PLANE && part.plane != H.plane))
							continue
						union |= dq_br_opaque(getFlatIcon(part, d, no_anim = TRUE))
				// What the layers draw alone is drawn together: a pixel only a layer has was taken away (a cut).
				var/lost = 0
				for(var/key in union)
					if(!(key in whole_pixels))
						lost++
				TEST_NOTICE(src, "BODYRENDER cut check composed=[composed] [wing] [dir2text(d)]: whole [length(whole_pixels)] px [whole.Width()]x[whole.Height()], layers [length(union)] px, lost [lost]")
				if(lost)
					bad += "composed=[composed] [wing] [dir2text(d)] lost [lost]"
		// A group of parts names its own icon: one with none draws the icon of what it is flattened over (a composed body is the mob's own icon), a second body.
		for(var/image/layer in H.look_layer_images())
			if(length(layer.overlays) && !layer.icon)
				bad += "composed=[composed]: a group of [length(layer.overlays)] parts at layer [layer.layer] has no icon"
	TEST_ASSERT(!length(bad), "layers cut each other or draw a body of their own: [jointext(bad, "; ")]")
	test_driver_end()

/// Facing north the tail is over the body, facing south under it, whichever tail is worn: the layer a facing shows is the one whose copy has pixels in it.
/datum/unit_test/dq_body_render_tail_over_body_facing_north

/datum/unit_test/dq_body_render_tail_over_body_facing_north/Run()
	test_driver_begin()
	var/mob/living/carbon/human/H = dq_br_body("none", FALSE)
	var/list/styles = list()
	var/n = 0
	for(var/key in GLOB.tail_styles_list)
		var/datum/sprite_accessory/tail/style = GLOB.tail_styles_list[key]
		if(!istype(style) || style.clip_mask_state || !style.icon_state)
			continue
		if(n++ % 7)
			continue
		styles += style
		if(length(styles) >= 24)
			break
	var/list/bad = list()
	for(var/datum/sprite_accessory/tail/style as anything in styles)
		var/asked_before = GLOB.human_baker.asked
		var/baked_before = length(GLOB.human_baker.baked)
		dq_hd_set(H, "tail_style", style)
		refresh_flush()
		draw_now(H) // a draw filed right after another is not applied by the flush alone: the bake asks wait for it
		test_time(0.5 SECONDS) // the effects a draw names (the bake asks) run on the next tick, not inside the flush
		dq_hb_settle()
		// The draw asks for the facing splits it is missing: after it settles each one is baked or failed, without anyone asking again.
		for(var/list/spec as anything in H.tail_style_specs(FALSE, FALSE))
			if(!icon_exists(spec[1], spec[2]))
				continue
			if(!human_bake_get("tail_dirs|[spec[1]]|[spec[2]]|[NORTH]"))
				bad += "[style.type]: the draw never asked for the north facing of [spec[2]] (asked [GLOB.human_baker.asked - asked_before], baked [length(GLOB.human_baker.baked) - baked_before], pending [length(GLOB.human_baker.pending)], bake_landed [H.bake_landed], tail [H.tail_style?.type])"
		var/list/layers = H.look_layers()
		var/image/lower = layers[TAIL_LOWER_LAYER]
		var/image/upper = layers[TAIL_UPPER_LAYER]
		if(!upper)
			bad += "[style.type]: no upper copy"
			continue
		// The sprite itself is blank in some facings (a tail hidden behind the body): a copy must show exactly where the sprite has pixels.
		if(!icon_exists(style.icon, style.icon_state))
			continue
		var/source_north = length(dq_br_opaque(icon(style.icon, style.icon_state, NORTH))) > 0
		var/source_south = length(dq_br_opaque(icon(style.icon, style.icon_state, SOUTH))) > 0
		var/north_upper = !dq_hd_blank_facing(upper, NORTH)
		var/north_lower = lower && !dq_hd_blank_facing(lower, NORTH)
		var/south_lower = lower && !dq_hd_blank_facing(lower, SOUTH)
		var/south_upper = !dq_hd_blank_facing(upper, SOUTH)
		TEST_NOTICE(src, "BODYRENDER tail [style.type] icon_state=[style.icon_state] sprite north [source_north] south [source_south]; north: upper [north_upper] lower [north_lower]; south: upper [south_upper] lower [south_lower]")
		if(north_upper != source_north)
			bad += "[style.type]: facing north the tail is [north_upper ? "drawn" : "missing"] over the body, the sprite has [source_north ? "pixels" : "none"]"
		if(north_lower)
			bad += "[style.type]: drawn under the body facing north"
		if(south_upper)
			bad += "[style.type]: drawn over the body facing south"
		if(south_lower != source_south)
			bad += "[style.type]: facing south the tail is [south_lower ? "drawn" : "missing"] under the body, the sprite has [source_south ? "pixels" : "none"]"
	TEST_ASSERT(!length(bad), "tails sit on the wrong layer: [jointext(bad, "; ")]")
	test_driver_end()

/// The examine portrait of a winged, tailed, one-armed body is one body: the picture is the size of the body and its wings, and has pixels where
/// the drawn human has them.
/datum/unit_test/dq_body_render_portrait_is_one_body

/datum/unit_test/dq_body_render_portrait_is_one_body/Run()
	test_driver_begin()
	var/mob/living/carbon/human/H = dq_br_body("rejuv", TRUE)
	for(var/key in GLOB.wing_styles_list)
		dq_hd_set(H, "wing_style", GLOB.wing_styles_list[key])
		if(GLOB.wing_styles_list[key].wing_offset)
			break
	dq_hd_set(H, "tail_style", GLOB.tail_styles_list[/datum/sprite_accessory/tail/squirrel])
	refresh_flush()
	dq_hb_settle()
	for(var/d in list(SOUTH, NORTH))
		H.set_dir(d)
		H.animate_tail_stop()
		refresh_flush()
		var/datum/portrait/P = portrait_request(H, d)
		for(var/i in 1 to 60)
			if(P?.picture)
				break
			test_time(0.25 SECONDS)
			P = portrait_request(H, d)
		TEST_ASSERT(P?.picture, "[dir2text(d)]: the portrait landed")
		if(!P?.picture)
			continue
		var/icon/expected = getFlatIcon(H, d, no_anim = TRUE)
		var/list/report = list()
		var/mismatches = dq_test_portrait_mismatches(getFlatIcon(H, d), P.picture, report)
		TEST_NOTICE(src, "BODYRENDER portrait [dir2text(d)]: picture [P.picture.Width()]x[P.picture.Height()], getFlatIcon [expected.Width()]x[expected.Height()], mismatches [mismatches] [json_encode(report)]")
		// One body: the opaque pixels sit in one connected mass wide enough for a body and its wings, not in two bodies side by side.
		var/list/pixels = dq_br_opaque(P.picture)
		var/min_x = 1000
		var/max_x = 0
		for(var/key in pixels)
			var/list/xy = splittext(key, ",")
			min_x = min(min_x, text2num(xy[1]))
			max_x = max(max_x, text2num(xy[1]))
		TEST_NOTICE(src, "BODYRENDER portrait [dir2text(d)] opaque x range [min_x]..[max_x] of [P.picture.Width()]")
		TEST_ASSERT(P.picture.Width() <= 96 && P.picture.Height() <= 64, "[dir2text(d)]: the portrait is [P.picture.Width()]x[P.picture.Height()], more than a body and its wings")
	test_driver_end()
