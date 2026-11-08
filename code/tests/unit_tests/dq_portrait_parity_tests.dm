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
	TEST_NOTICE(src, "PHOTO_COST the shot on the tick: before [round(old_ms, 0.01)] ms, now [round(shot_ms, 0.01)] ms (the atoms' pictures drawn off the tick)")
	qdel(photo)
