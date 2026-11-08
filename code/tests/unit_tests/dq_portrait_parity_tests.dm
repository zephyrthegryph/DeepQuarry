// The shared portrait cache's pictures compared pixel by pixel with the flatteners they replace: getFlatIcon for a live, dressed human (examine,
// ID card, directory), and get_flat_icon (the library flattener) for the shapeshift panel and the gear painter.
//
// getFlatIcon(no_anim = TRUE) builds its result by Insert() into a blank /icon, which reports Width() 0 (the zero-width result): read frame 1 of
// the animated result instead, which is the same picture with its frames.

/// Mismatching pixels (a channel off by more than 3) between `expected` (read at frame 1 of its south state) and `actual`, or -1 when the sizes differ.
/proc/dq_test_portrait_mismatches(icon/expected, icon/actual, list/report)
	if(!expected || !actual)
		return -1
	if(expected.Width() != actual.Width() || expected.Height() != actual.Height())
		report?["size"] = "[expected.Width()]x[expected.Height()] vs [actual.Width()]x[actual.Height()]"
		return -1
	var/mismatches = 0
	var/worst = 0
	for(var/x in 1 to expected.Width())
		for(var/y in 1 to expected.Height())
			var/diff = dq_test_pixel_difference(expected.GetPixel(x, y, "", SOUTH, 1), actual.GetPixel(x, y))
			worst = max(worst, diff)
			if(diff > 3)
				mismatches++
	report?["worst"] = worst
	return mismatches

/// Waits (test time) for the portrait of `A` and returns it, or null.
/datum/unit_test/proc/dq_test_wait_portrait(atom/A)
	var/datum/portrait/P = portrait_request(A, SOUTH)
	for(var/i in 1 to 60)
		if(P?.picture)
			return P
		test_time(0.25 SECONDS)
		P = portrait_request(A, SOUTH)
	return P?.picture ? P : null

/// A live, dressed human's portrait matches getFlatIcon pixel for pixel.
/datum/unit_test/dq_portrait_matches_live_human

/datum/unit_test/dq_portrait_matches_live_human/Run()
	test_driver_begin()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
	H.equip_to_slot_or_del(new /obj/item/clothing/shoes/black(H), SLOT_ID_SHOES)
	H.equip_to_slot_or_del(new /obj/item/clothing/gloves/black(H), SLOT_ID_GLOVES)
	draw_now(H)
	var/datum/portrait/P = dq_test_wait_portrait(H)
	TEST_ASSERT(P, "the portrait landed")
	if(!P)
		test_driver_end()
		return
	var/icon/no_anim = getFlatIcon(H, defdir = SOUTH, no_anim = TRUE)
	TEST_NOTICE(src, "PORTRAIT_PARITY getFlatIcon(no_anim) reports [no_anim.Width()]x[no_anim.Height()] (the Insert() into a blank icon); the portrait is [P.picture.Width()]x[P.picture.Height()]")
	var/list/report = list()
	var/mismatches = dq_test_portrait_mismatches(getFlatIcon(H, defdir = SOUTH), P.picture, report)
	TEST_ASSERT_EQUAL(mismatches, 0, "the portrait differs from getFlatIcon ([json_encode(report)])")
	test_driver_end()

/// The shapeshift panel and the gear painter used get_flat_icon: what the portrait cache draws instead, compared.
/datum/unit_test/dq_portrait_matches_get_flat_icon

/datum/unit_test/dq_portrait_matches_get_flat_icon/Run()
	test_driver_begin()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
	draw_now(H)
	var/obj/item/clothing/under/color/grey/suit = allocate(/obj/item/clothing/under/color/grey, test_floor())
	suit.add_atom_colour("#3080ff", FIXED_COLOUR_PRIORITY)
	var/list/cases = list("a human (shapeshift panel)" = H, "a recoloured jumpsuit (gear painter)" = suit)
	for(var/label in cases)
		var/atom/A = cases[label]
		var/datum/portrait/P = dq_test_wait_portrait(A)
		TEST_ASSERT(P, "[label]: the portrait landed")
		if(!P)
			continue
		var/list/report = list()
		var/mismatches = dq_test_portrait_mismatches(get_flat_icon(A, SOUTH, FALSE), P.picture, report) // no_anim reports 0x0 here too
		TEST_NOTICE(src, "PORTRAIT_PARITY [label]: [mismatches] pixels differ from get_flat_icon ([json_encode(report)])")
		TEST_ASSERT_EQUAL(mismatches, 0, "[label]: the portrait differs from get_flat_icon ([json_encode(report)])")
	test_driver_end()

/// A species without a "preview" state gets its picker thumbnail from the portrait cache: nothing on the first ask, filed when it lands.
/datum/unit_test/dq_species_thumbnail_lands

/datum/unit_test/dq_species_thumbnail_lands/Run()
	var/datum/species/S = GLOB.all_species[SPECIES_HUMAN]
	TEST_ASSERT(S && !icon_exists(S.icobase, "preview"), "humans have no preview state (the slow path)")
	GLOB.dq_species_preview_cache -= S.name
	GLOB.dq_species_preview_waits -= S.name
	var/started = TICK_USAGE_REAL
	var/first = dq_species_preview_b64(S)
	var/ask_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	var/deadline = world.time + 20 SECONDS
	UNTIL(GLOB.dq_species_preview_cache[S.name] || world.time > deadline)
	TEST_ASSERT(first || GLOB.dq_species_preview_cache[S.name], "the human thumbnail was filed")
	TEST_ASSERT_NULL(GLOB.dq_species_preview_waits[S.name], "the waiter was dropped once it landed")
	TEST_NOTICE(src, "SPECIES_THUMB the slow path on the tick: [round(ask_ms, 0.01)] ms (was a synchronous getFlatIcon)")

/// Coloured vendor product pictures through iconforge: the same pixels as the BYOND Blend path, and what each costs on the tick (VENDPROD_BENCH).
/datum/unit_test/dq_vending_product_forge_matches

/datum/unit_test/dq_vending_product_forge_matches/Run()
	var/list/coloured = list()
	for(var/product in vending_catalog_product_types())
		var/list/spec = vending_product_icon_spec(product)
		if(spec?[3] && spec[4] && get_icon_dmi_path(spec[1]) && rustg_file_exists(resolve_icon_dmi_path(get_icon_dmi_path(spec[1]))))
			coloured += list(spec)
		if(length(coloured) >= 40)
			break
	TEST_ASSERT(length(coloured), "the catalog has coloured products")
	var/byond_ms = 0
	var/forge_ms = 0
	var/differing = 0
	for(var/list/spec as anything in coloured)
		fdel("[DQ_VENDPROD_DIR][md5("[resolve_icon_dmi_path(get_icon_dmi_path(spec[1]))]|[spec[2]]|[spec[3]]")].png") // a cold draw, as at first open
		var/started = TICK_USAGE_REAL
		vending_product_asset_byond(spec)
		byond_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
		started = TICK_USAGE_REAL
		var/key = vending_product_forge(spec)
		forge_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
		TEST_ASSERT(key, "[spec[1]] [spec[2]]: iconforge drew it")
		var/icon/expected = icon(spec[1], spec[2], SOUTH, 1)
		expected.Blend(spec[3], ICON_MULTIPLY)
		var/icon/actual = icon(file("[DQ_VENDPROD_DIR][md5("[resolve_icon_dmi_path(get_icon_dmi_path(spec[1]))]|[spec[2]]|[spec[3]]")].png"))
		var/list/report = list()
		var/mismatches = dq_test_portrait_mismatches(expected, actual, report)
		if(mismatches)
			differing++
			log_world("VENDPROD_BENCH [spec[1]] [spec[2]] [spec[3]]: [mismatches] pixels differ ([json_encode(report)])")
	TEST_ASSERT_EQUAL(differing, 0, "[differing] of [length(coloured)] forged pictures differ from the BYOND ones")
	TEST_NOTICE(src, "VENDPROD_BENCH [length(coloured)] coloured product pictures, cold: BYOND cut+Blend+hash [round(byond_ms, 0.01)] ms, iconforge [round(forge_ms, 0.01)] ms")

/// The background species thumbnail warm-up runs (built one at a time after init), and waits while a client is joining.
/datum/unit_test/dq_species_warmup_runs

/datum/unit_test/dq_species_warmup_runs/Run()
	var/datum/species/S = GLOB.all_species[SPECIES_HUMAN]
	GLOB.dq_species_preview_cache -= S.name
	GLOB.dq_species_preview_waits -= S.name
	set_global(nameof(GLOB.dq_species_preview_warmed), FALSE) // teardown restores it
	dq_species_preview_warm_next(list(S.name))
	var/deadline = world.time + 30 SECONDS
	UNTIL((GLOB.dq_species_preview_warmed && GLOB.dq_species_preview_cache[S.name]) || world.time > deadline)
	TEST_ASSERT(GLOB.dq_species_preview_warmed, "the warm-up finished")
	TEST_ASSERT(GLOB.dq_species_preview_cache[S.name], "and filed the human thumbnail")
	TEST_ASSERT(!dq_species_preview_someone_joining() || length(GLOB.clients), "nobody is joining a clientless test world")

/// The photo picture as the camera drew it before the portrait cache (getFlatIcon of every atom, on the tick): the reference.
/proc/dq_test_photo_reference(obj/item/camera/camera, list/turfs, turf/center)
	var/icon/res = icon('icons/effects/96x96.dmi', "")
	res.Scale(camera.size * 32, camera.size * 32)
	res.Blend("#000", ICON_OVERLAY)
	var/list/atoms = list()
	for(var/turf/the_turf in turfs)
		atoms.Add(the_turf)
		for(var/atom/A in the_turf)
			if(A.invisibility)
				continue
			if(A.plane > 0 && !(A.plane in camera.picture_planes))
				continue
			atoms.Add(A)
	var/list/sorted = sort_atoms_by_layer(atoms)
	var/center_offset = (camera.size - 1) / 2 * 32 + 1
	for(var/atom/A as anything in sorted)
		var/icon/img = getFlatIcon(A, no_anim = TRUE)
		if(!istype(img, /icon))
			continue
		if(isliving(A) && A:lying)
			img.BecomeLying()
		var/xoff = (A.x - center.x) * 32 + center_offset
		var/yoff = (A.y - center.y) * 32 + center_offset
		if(ismovable(A))
			xoff += A.pixel_x
			yoff += A.pixel_y
		res.Blend(img, blendMode2iconMode(A.blend_mode), A.pixel_x + xoff, A.pixel_y + yoff)
	for(var/turf/the_turf in turfs)
		var/xoff = (the_turf.x - center.x) * 32 + center_offset
		var/yoff = (the_turf.y - center.y) * 32 + center_offset
		res.Blend(getFlatIcon(the_turf.loc, no_anim = TRUE), blendMode2iconMode(the_turf.blend_mode), xoff, yoff)
	return res

/// A photo of a dressed human: printed at once (a black frame), then filled in place with the same picture the camera drew before.
/datum/unit_test/dq_photo_portraits_match

/datum/unit_test/dq_photo_portraits_match/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
	draw_now(H)
	var/obj/item/camera/camera = allocate(/obj/item/camera, T)
	var/list/turfs = list(T)
	var/started = TICK_USAGE_REAL
	var/icon/expected = dq_test_photo_reference(camera, turfs, T)
	var/old_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	started = TICK_USAGE_REAL
	var/obj/item/photo/photo = camera.createpicture(T, null, turfs, "", FALSE)
	var/shot_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	TEST_ASSERT(photo.img && photo.tiny, "the photo has pictures at once")
	var/deadline = world.time + 20 SECONDS
	UNTIL(!photo.rendering || world.time > deadline)
	TEST_ASSERT_NULL(photo.rendering, "the photo's picture was finished")
	var/list/report = list()
	var/mismatches = dq_test_portrait_mismatches(expected, photo.img, report)
	TEST_ASSERT_EQUAL(mismatches, 0, "the photo differs from the old camera picture ([json_encode(report)])")
	// Warm, both ways (the second shot of the same scene: the old path flattens again, the new one is served from the cache).
	started = TICK_USAGE_REAL
	dq_test_photo_reference(camera, turfs, T)
	var/old_warm_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	started = TICK_USAGE_REAL
	var/obj/item/photo/second = camera.createpicture(T, null, turfs, "", FALSE)
	var/shot_warm_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	TEST_NOTICE(src, "PHOTO_COST the shot on the tick: first before [round(old_ms, 0.01)] ms, now [round(shot_ms, 0.01)] ms; again before [round(old_warm_ms, 0.01)] ms, now [round(shot_warm_ms, 0.01)] ms")
	qdel(second)
	qdel(photo)

/// Every atom of a photo's tile and its area: the portrait matches getFlatIcon(no_anim) (PORTRAIT_TILE lines name any that differ).
/datum/unit_test/dq_portrait_tile_atoms_match

/datum/unit_test/dq_portrait_tile_atoms_match/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
	draw_now(H)
	var/list/atoms = list(T, T.loc)
	for(var/atom/A in T)
		atoms += A
	for(var/atom/A as anything in atoms)
		var/datum/portrait/P
		var/deadline = world.time + 20 SECONDS
		UNTIL((P = portrait_request(A, A.dir)) || world.time > deadline)
		var/list/report = list()
		var/icon/expected = getFlatIcon(A)
		var/mismatches = dq_test_portrait_mismatches(expected, P?.picture, report)
		log_world("PORTRAIT_TILE [A] ([A.type]) icon [A.icon] state [A.icon_state] overlays [length(A.overlays)]: [mismatches] ([json_encode(report)])")
		TEST_ASSERT_EQUAL(mismatches, 0, "[A] ([A.type]): the portrait differs from getFlatIcon ([json_encode(report)])")

/// An animated picture (holograms, food batter): every frame and its delay as getFlatIcon's animated result, overlays included.
/datum/unit_test/dq_portrait_animated_matches

/datum/unit_test/dq_portrait_animated_matches/Run()
	var/obj/effect/A = allocate(/obj/effect, test_floor())
	// The first looping animated state of the file (one that plays once or rewinds is drawn the old way).
	var/list/looping
	for(var/list/state as anything in icon_metadata('icons/obj/singularity.dmi')["states"])
		if(length(state["delay"]) > 1 && !state["loop_count"] && !state["rewind"] && state["dirs"] == 1)
			looping = state
			break
	TEST_ASSERT(looping, "the file has a looping animation")
	if(!looping)
		return
	A.set_icon('icons/obj/singularity.dmi')
	A.set_icon_state(looping["name"])
	A.add_overlay(image('icons/obj/singularity.dmi', "ptank"))
	var/datum/portrait/P
	var/deadline = world.time + 20 SECONDS
	UNTIL((P = portrait_request(A, A.dir, animated = TRUE)) || world.time > deadline)
	TEST_ASSERT(P?.picture, "the animated portrait landed")
	if(!P?.picture)
		return
	TEST_ASSERT_EQUAL(length(P.delays), length(looping["delay"]), "it has the state's frames")
	var/icon/expected = getFlatIcon(A)
	var/mismatches = 0
	for(var/frame in 1 to length(looping["delay"]))
		for(var/x in 1 to 32)
			for(var/y in 1 to 32)
				if(dq_test_pixel_difference(expected.GetPixel(x, y, "", null, frame), P.picture.GetPixel(x, y, "", null, frame)) > 3)
					mismatches++
	TEST_ASSERT_EQUAL(mismatches, 0, "every frame matches getFlatIcon's animated picture")

/// A photo copied before its picture was finished gets the finished picture too.
/datum/unit_test/dq_photo_copy_before_fill

/datum/unit_test/dq_photo_copy_before_fill/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.equip_to_slot_or_del(new /obj/item/clothing/shoes/black(H), SLOT_ID_SHOES)
	draw_now(H)
	var/obj/item/camera/camera = allocate(/obj/item/camera, T)
	var/obj/item/photo/photo = camera.createpicture(T, null, list(T), "", FALSE)
	var/obj/item/photo/copy = photo.copy()
	var/deadline = world.time + 20 SECONDS
	UNTIL(!photo.rendering || world.time > deadline)
	TEST_ASSERT_NULL(photo.rendering, "the photo's picture was finished")
	var/list/report = list()
	TEST_ASSERT_EQUAL(dq_test_portrait_mismatches(photo.img, copy.img, report), 0, "the early copy has the finished picture ([json_encode(report)])")
	qdel(copy)
	qdel(photo)

/// Dipping a snack in batter draws the batter on its (animated) picture from the portrait cache: the look lands, then cooking replaces it.
/datum/unit_test/dq_food_coating_lands

/datum/unit_test/dq_food_coating_lands/Run()
	var/turf/T = test_floor()
	var/obj/item/reagent_containers/food/snacks/meat/food = allocate(/obj/item/reagent_containers/food/snacks/meat, T)
	var/obj/item/reagent_containers/glass/beaker/beaker = allocate(/obj/item/reagent_containers/glass/beaker, T)
	beaker.reagents.add_reagent(REAGENT_ID_BATTER, 50)
	var/datum/reagent/nutriment/coating/C = beaker.reagents.get_reagent(REAGENT_ID_BATTER)
	TEST_ASSERT(C, "the beaker holds batter")
	if(!C)
		return
	TEST_ASSERT(food.apply_coating(C, null), "the snack is dipped")
	var/deadline = world.time + 20 SECONDS
	UNTIL(food.coating_look || world.time > deadline)
	TEST_ASSERT(food.coating_look && food.flat_icon, "the raw batter look landed")
	var/image/raw = food.coating_look
	food.cook()
	TEST_ASSERT(food.coating_look && food.coating_look != raw, "cooking replaced it with the cooked look")
	TEST_ASSERT_NULL(food.coating_stages, "nothing is left waiting")

/// A photo deleted before its picture is finished: the copy made from it still gets the finished picture.
/datum/unit_test/dq_photo_copy_outlives_original

/datum/unit_test/dq_photo_copy_outlives_original/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/clothing/under/color/grey/suit = new(H)
	suit.add_atom_colour(rgb(rand(0, 255), rand(0, 255), rand(0, 255)), FIXED_COLOUR_PRIORITY) // a look the cache has not drawn yet
	H.equip_to_slot_or_del(suit, SLOT_ID_UNIFORM)
	draw_now(H)
	var/obj/item/camera/camera = allocate(/obj/item/camera, T)
	var/icon/expected = dq_test_photo_reference(camera, list(T), T)
	var/obj/item/photo/photo = camera.createpicture(T, null, list(T), "", FALSE)
	TEST_ASSERT(photo.rendering, "the picture is still being drawn")
	var/obj/item/photo/copy = photo.copy()
	qdel(photo)
	var/deadline = world.time + 20 SECONDS
	UNTIL(!copy.rendering || world.time > deadline)
	TEST_ASSERT_NULL(copy.rendering, "the copy's picture was finished")
	var/list/report = list()
	TEST_ASSERT_EQUAL(dq_test_portrait_mismatches(expected, copy.img, report), 0, "the copy has the finished picture ([json_encode(report)])")
	qdel(copy)

/// An animated object for the hologram tests: the first looping animation of singularity.dmi, with an overlay.
/proc/dq_test_animated_object(turf/T)
	var/obj/effect/A = new(T)
	for(var/list/state as anything in icon_metadata('icons/obj/singularity.dmi')["states"])
		if(length(state["delay"]) > 1 && !state["loop_count"] && !state["rewind"] && state["dirs"] == 1)
			A.set_icon('icons/obj/singularity.dmi')
			A.set_icon_state(state["name"])
			break
	A.add_overlay(image('icons/obj/singularity.dmi', "ptank"))
	return A

/// Differing pixels over every frame of two animated pictures of one state (`frames` frames, `dirs` directions).
/proc/dq_test_frame_mismatches(icon/expected, icon/actual, frames, list/dirs)
	. = 0
	for(var/dir in dirs)
		for(var/frame in 1 to frames)
			for(var/x in 1 to 32)
				for(var/y in 1 to 32)
					if(dq_test_pixel_difference(expected.GetPixel(x, y, "", dir, frame), actual.GetPixel(x, y, "", dir, frame)) > 3)
						.++

/// The AI's hologram of an animated object: drawn off the tick, every direction and frame as getHologramIcon(getCompoundIcon()) drew it.
/datum/unit_test/dq_ai_hologram_animated

/datum/unit_test/dq_ai_hologram_animated/Run()
	var/turf/T = test_floor()
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, T, null, null, null, TRUE)
	var/obj/effect/A = dq_test_animated_object(T)
	own(A)
	var/icon/expected = getHologramIcon(getCompoundIcon(A))
	var/icon/before = AI.holo_icon
	AI.request_holo_compound(A)
	var/deadline = world.time + 20 SECONDS
	UNTIL(AI.holo_icon != before || world.time > deadline)
	TEST_ASSERT(AI.holo_icon != before, "the hologram landed")
	TEST_ASSERT_NULL(AI.holo_compound, "nothing is left drawing")
	TEST_ASSERT_EQUAL(dq_test_frame_mismatches(expected, AI.holo_icon, 2, list(NORTH, SOUTH, EAST, WEST)), 0, "every direction matches the old hologram")

/// The circuit projector's hologram of an animated object: blank, then (when its picture lands) every frame as the old projector drew it.
/datum/unit_test/dq_circuit_hologram_animated

/datum/unit_test/dq_circuit_hologram_animated/Run()
	var/turf/T = test_floor()
	var/obj/item/electronic_assembly/large/assembly = allocate(/obj/item/electronic_assembly/large, T)
	set_var(assembly, nameof(assembly.opened), TRUE)
	var/obj/item/integrated_circuit/output/holographic_projector/projector = new(T)
	own(projector)
	TEST_ASSERT(assembly.add_circuit(projector, null), "the projector is in the assembly")
	TEST_ASSERT(projector.assembly(), "and knows it")
	var/obj/effect/A = dq_test_animated_object(T)
	own(A)
	set_var(A, "luminosity", 1) // view() needs it lit: the test room has no lights
	projector.set_pin_data("input", 2, A) // IC_INPUT
	projector.set_pin_data("input", 3, "#40c0ff")
	var/icon/expected = getHologramIcon(getFlatIcon(A), no_color = TRUE)
	expected.ColorTone("#40c0ff")
	TEST_ASSERT(projector.create_hologram(), "the projector made a hologram")
	if(!projector.hologram)
		return
	var/deadline = world.time + 20 SECONDS
	UNTIL(projector.hologram?.icon || world.time > deadline)
	TEST_ASSERT(projector.hologram?.icon, "the hologram's picture landed")
	var/icon/actual = icon(projector.hologram.icon)
	TEST_ASSERT_EQUAL(dq_test_frame_mismatches(expected, actual, 2, list(null)), 0, "its frames match the old projector's hologram")
	projector.destroy_hologram()
