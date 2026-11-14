// The human's look (code/modules/mob/living/carbon/human/human_look.dm), drawn by draw(look). A body is dressed, its look settles,
// and the rows are the flat picture of every facing (md5) plus the layers off the base plane (emissive blockers, glowing eyes),
// which a flat picture does not show.

/// Sets `var_name` of H to `value` the way the game does (its setter when it has one).
/datum/unit_test/proc/dq_hd_set(mob/living/carbon/human/H, var_name, value)
	if(hascall(H, "set_[var_name]"))
		call(H, "set_[var_name]")(value)
	else
		H.vars[var_name] = value

/// The rows of H: one md5 of the picture's pixels per facing (not of its PNG, whose palette is not part of the look) and the off-plane
/// layers. The draw runs by itself after every turn: nothing here asks for it.
/datum/unit_test/proc/dq_hd_rows(mob/living/carbon/human/H)
	. = list()
	var/start_dir = H.dir
	for(var/d in list(SOUTH, NORTH, EAST, WEST))
		H.set_dir(d)
		H.animate_tail_stop() // a species tail idles on a random loop; the rows hold the still one
		refresh_flush()
		var/icon/flat = getFlatIcon(H, d)
		var/list/pixels = list("[flat.Width()]x[flat.Height()]")
		for(var/x in 1 to flat.Width())
			for(var/y in 1 to flat.Height())
				pixels += "[flat.GetPixel(x, y)]"
		. += "[dir2text(d)]=[md5(jointext(pixels, ","))]"
	H.set_dir(start_dir)
	refresh_flush()
	var/list/planes = list()
	for(var/layer in H.overlays)
		var/mutable_appearance/MA = new(layer)
		if(MA.plane == FLOAT_PLANE || MA.plane == H.plane || MA.icon == LIGHTING_ICON)
			continue
		planes["plane [MA.plane]"] += 1
	var/list/plane_rows = list()
	for(var/row in planes)
		plane_rows += "[row] x[planes[row]]"
	sortTim(plane_rows, GLOBAL_PROC_REF(cmp_text_asc))
	. += plane_rows

/// A full outfit, one item in every drawn slot.
/datum/unit_test/proc/dq_hd_dress(mob/living/carbon/human/H)
	var/list/outfit = list(
		SLOT_ID_UNIFORM = /obj/item/clothing/under/color/grey,
		SLOT_ID_SHOES = /obj/item/clothing/shoes/black,
		SLOT_ID_GLOVES = /obj/item/clothing/gloves/black,
		SLOT_ID_EYES = /obj/item/clothing/glasses/meson,
		SLOT_ID_MASK = /obj/item/clothing/mask/breath,
		SLOT_ID_HEAD = /obj/item/clothing/head/hardhat,
		SLOT_ID_BACK = /obj/item/storage/backpack,
		SLOT_ID_BELT = /obj/item/storage/belt/utility,
		SLOT_ID_ID = /obj/item/card/id,
		SLOT_ID_EAR_L = /obj/item/radio/headset,
		SLOT_ID_SUIT = /obj/item/clothing/suit/storage/hazardvest,
		SLOT_ID_HAND_R = /obj/item/tool/wrench,
		SLOT_ID_HAND_L = /obj/item/tool/crowbar,
	)
	for(var/slot in outfit)
		var/path = outfit[slot]
		H.equip_to_slot_or_del(new path(H), slot)

/datum/unit_test/proc/dq_hd_body(list/got, name, species = SPECIES_HUMAN)
	log_test("human draw: making [name]")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.set_species(species)
	H.set_dir(SOUTH)
	refresh_flush()
	return H

/// A draw is deterministic: two identical bodies, built the same way, give the same rows, and a dressed body does not look like a bare one.
/datum/unit_test/dq_human_draw_deterministic

/datum/unit_test/dq_human_draw_deterministic/Run()
	var/list/first = dq_hd_dressed_rows()
	var/list/second = dq_hd_dressed_rows()
	TEST_ASSERT_EQUAL(jointext(first, " "), jointext(second, " "), "two identically built bodies drew differently")
	var/mob/living/carbon/human/bare = dq_hd_body(list(), "bare")
	TEST_ASSERT(jointext(dq_hd_rows(bare), " ") != jointext(first, " "), "the draw sees clothes")

/// The rows of a new human in a profile look and a full outfit, with the RNG seeded the same each time.
/datum/unit_test/proc/dq_hd_dressed_rows()
	rand_seed(dq_test_seed_for("dq_human_draw_deterministic"))
	var/mob/living/carbon/human/H = dq_hd_body(list(), "dressed")
	dq_profile_dress(H, -40)
	dq_hd_dress(H)
	return dq_hd_rows(H)

/// The flat picture of H facing south: what a redraw changes.
/datum/unit_test/proc/dq_hd_picture(mob/living/carbon/human/H)
	refresh_flush()
	return md5(icon2base64(getFlatIcon(H, SOUTH)))

/// A tail is drawn under the uniform from the south and over it from the north, with no redraw when the human turns.
/datum/unit_test/dq_human_draw_tail_layers_against_uniform

/datum/unit_test/dq_human_draw_tail_layers_against_uniform/Run()
	test_driver_begin()
	var/mob/living/carbon/human/H = dq_hd_body(list(), "tail")
	dq_hd_set(H, "tail_style", GLOB.tail_styles_list[/datum/sprite_accessory/tail/squirrel])
	H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
	H.set_dir(SOUTH)
	refresh_flush()
	dq_hb_settle() // each copy's facing split is baked off the main thread (human_bake.dm)
	// The tail is on both layers, each copy drawn only in its own facings: BYOND shows the frame for the dir, so a turn redraws nothing.
	var/list/layers = H.look_layers()
	var/image/lower = layers[TAIL_LOWER_LAYER]
	var/image/upper = layers[TAIL_UPPER_LAYER]
	TEST_ASSERT(lower && upper, "the tail is drawn on the lower and the upper layer")
	TEST_ASSERT(TAIL_LOWER_LAYER < UNIFORM_LAYER, "the lower tail layer sits under the uniform")
	TEST_ASSERT(TAIL_UPPER_LAYER > UNIFORM_LAYER, "the upper tail layer sits over the uniform")
	TEST_ASSERT(dq_hd_blank_facing(lower, NORTH), "the lower copy shows nothing facing north")
	TEST_ASSERT(!dq_hd_blank_facing(lower, SOUTH), "the lower copy shows the tail facing south")
	TEST_ASSERT(dq_hd_blank_facing(upper, SOUTH), "the upper copy shows nothing facing south")
	TEST_ASSERT(!dq_hd_blank_facing(upper, NORTH), "the upper copy shows the tail facing north")
	var/south_key = H.rx?.look_key
	H.set_dir(NORTH)
	refresh_flush()
	TEST_ASSERT_EQUAL(H.rx?.look_key, south_key, "turning round leaves the look as it is (no redraw)")
	test_driver_end()

/// TRUE when the layer has no visible pixel facing `facing`: its own icon and every part it is made of (emissive blockers are not part of the picture).
/datum/unit_test/proc/dq_hd_blank_facing(I, facing)
	if(I.icon)
		var/icon/frame = icon(I.icon, I.icon_state, facing)
		for(var/x in 1 to frame.Width())
			for(var/y in 1 to frame.Height())
				if(frame.GetPixel(x, y))
					return FALSE
	for(var/part in I.overlays)
		var/mutable_appearance/MA = new(part)
		if(MA.plane != FLOAT_PLANE)
			continue
		if(!dq_hd_blank_facing(MA, facing))
			return FALSE
	return TRUE

/// An injury draws its overlay and healing it takes the overlay off.
/datum/unit_test/dq_human_draw_damage_overlay_follows_injury

/datum/unit_test/dq_human_draw_damage_overlay_follows_injury/Run()
	test_driver_begin()
	var/mob/living/carbon/human/H = dq_hd_body(list(), "damage")
	TEST_ASSERT(!H.look_layers()[MOB_DAM_LAYER], "an unhurt human has no damage overlay")
	var/unhurt = dq_hd_picture(H)
	H.injure(INJURY_BURN, 60, BP_TORSO, flags = INJURE_SILENT)
	refresh_flush()
	dq_hb_settle() // the wound's picture is baked off the main thread (human_bake.dm)
	TEST_ASSERT(H.look_layers()[MOB_DAM_LAYER], "a burn on the torso draws a damage overlay")
	TEST_ASSERT(dq_hd_picture(H) != unhurt, "and the drawn human shows it")
	H.fully_heal()
	TEST_ASSERT(!H.look_layers()[MOB_DAM_LAYER], "healing takes the overlay off")
	test_driver_end()

/// The layered body is off by default, and when on the body is one blank image carrying the limbs as overlays.
/datum/unit_test/dq_human_draw_layered_body

/datum/unit_test/dq_human_draw_layered_body/Run()
	var/mob/living/carbon/human/H = dq_hd_body(list(), "layered")
	var/list/body = H.body_look(new /datum/look)
	var/image/layered = body[2]
	TEST_ASSERT(length(layered.overlays) >= 5, "the limbs are overlays of the body image")
	var/list/composed = H.build_body_look('icons/mob/human.dmi', FALSE, FALSE, FALSE, FALSE)
	var/image/flat = composed[2]
	TEST_ASSERT_EQUAL(length(flat.overlays), 0, "the composed body is one icon")

/// A hulk and a skeleton are layered too: the hulk's green is one colour over the whole body, the skeleton draws the skeleton sprites.
/datum/unit_test/dq_human_draw_layered_forms

/datum/unit_test/dq_human_draw_layered_forms/Run()
	var/mob/living/carbon/human/H = dq_hd_body(list(), "forms")
	TEST_ASSERT(H.can_layer_body(FALSE, FALSE), "a plain body is layered")
	TEST_ASSERT(H.can_layer_body(FALSE, TRUE), "a skeleton is layered")
	TEST_ASSERT(!H.can_layer_body(TRUE, FALSE), "a husk is not (its tone has no client form)")
	var/list/plain = H.build_layered_body_look('icons/mob/human.dmi', FALSE, FALSE)
	var/list/hulk = H.build_layered_body_look('icons/mob/human.dmi', TRUE, FALSE)
	var/image/hulk_body = hulk[2]
	TEST_ASSERT(hulk_body.color, "a hulk's body carries the green")
	TEST_ASSERT(hulk_body.appearance_flags & KEEP_TOGETHER, "and the green covers the body as one picture")
	var/image/plain_body = plain[2]
	TEST_ASSERT(!plain_body.color, "a plain body is not tinted as a whole")
	TEST_ASSERT_EQUAL(length(hulk_body.overlays), length(plain_body.overlays), "a hulk has the same parts as a plain body")
	var/list/skeleton = H.build_layered_body_look('icons/mob/human.dmi', FALSE, TRUE)
	var/image/skeleton_body = skeleton[2]
	TEST_ASSERT(length(skeleton_body.overlays) >= 5, "a skeleton is made of its limbs")

/// The head draws its eyes and its hair as layers: no composited icon stands in for them.
/datum/unit_test/dq_human_draw_layered_face

/datum/unit_test/dq_human_draw_layered_face/Run()
	var/mob/living/carbon/human/H = dq_hd_body(list(), "face")
	H.looks.set_hair_style(dq_profile_style(H, GLOB.hair_styles_list, "Short Hair"))
	H.looks.set_hair_color(rgb(200, 40, 90))
	refresh_flush()
	var/image/hair = H.look_layers()[HAIR_LAYER]
	TEST_ASSERT(hair, "a haired human draws a hair layer")
	TEST_ASSERT(!hair.icon, "the hair layer is a group of tinted parts, not one composited icon")
	TEST_ASSERT(length(hair.overlays) >= 1, "the hair is a part of the group")
	var/list/body = H.body_look(new /datum/look)
	var/image/body_image = body[2]
	var/with_head = length(body_image.overlays)
	var/obj/item/organ/external/head/head = H.limb_tagged(BP_HEAD)
	TEST_ASSERT(length(head.layered_parts(FALSE)) >= 2, "the head is its sprite and its eyes, as parts")
	TEST_ASSERT(with_head >= 6, "the head's parts are in the body")
