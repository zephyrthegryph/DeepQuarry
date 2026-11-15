// The body look of a real saved character (a taur with wings, a backpack, a lost arm and a prosthetic arm), spawned through the preferences the way the game does.
// The fixture holds only the appearance of the character (code/tests/unit_tests/data/profile_saves/taur_wings_character.json).

/// A human built from the fixture character by preferences copy_to, settled the way a spawn is (deferred redraws and bakes run out).
/datum/unit_test/proc/dq_real_character()
	var/list/overrides = json_decode(file2text("code/tests/unit_tests/data/profile_saves/taur_wings_character.json"))
	var/datum/preferences/dq_test_stub/P = dq_palette_test_prefs(overrides)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	P.copy_to(H)
	H.equip_to_slot_or_del(new /obj/item/storage/backpack(H), SLOT_ID_BACK)
	H.set_dir(SOUTH)
	refresh_flush()
	dq_hb_settle()
	fdel(P.path)
	return H

/// The opaque pixels of `thing` seen facing `d`.
/datum/unit_test/proc/dq_real_pixels(thing, d)
	return dq_br_opaque(getFlatIcon(thing, d, no_anim = TRUE))

/datum/unit_test/dq_body_render_real_character

/datum/unit_test/dq_body_render_real_character/Run()
	test_driver_begin()
	var/mob/living/carbon/human/H = dq_real_character()
	TEST_ASSERT(istype(H.tail_style, /datum/sprite_accessory/tail/taur), "the character is a taur")
	TEST_ASSERT(H.body_taur_cuts(), "whose lower half cuts the legs")
	TEST_ASSERT_NOTNULL(H.wing_style, "with wings")
	TEST_ASSERT_NOTNULL(H.limb_tagged(BP_L_ARM), "and the arm the save kept")
	TEST_ASSERT_NULL(H.limb_tagged(BP_R_ARM), "and no arm where the save amputated one")
	TEST_ASSERT_NULL(H.limb_tagged(BP_R_HAND), "nor the hand of that arm")
	var/obj/item/organ/external/arm = H.limb_tagged(BP_L_ARM)
	TEST_ASSERT(arm.is_robotic(), "the arm that is left is a prosthetic")

	// One body image of overlays, whatever is worn: no composed icon stands in for it.
	var/list/body = H.body_look(new /datum/look)
	var/image/body_image = body[2]
	TEST_ASSERT(length(body_image.overlays) >= 5, "the body is made of the limbs as overlays")
	var/list/lines = dq_br_describe(body_image)
	var/saw_arm = FALSE
	for(var/line in lines)
		TEST_ASSERT(!findtext(line, "r_arm") && !findtext(line, "r_hand"), "a limb that is gone still draws: [line]")
		if(findtext(line, "/l_arm"))
			saw_arm = TRUE
	TEST_ASSERT(saw_arm, "the prosthetic arm is a part of the body")

	// Layers: the backpack is over the wings, the wings over the suit, the tail over the body.
	var/list/layers = H.look_layers()
	var/image/pack = layers[BACK_LAYER]
	var/image/wings = layers[WING_LAYER]
	var/image/tail = layers[TAIL_UPPER_LAYER]
	TEST_ASSERT(pack && wings && tail, "the backpack, the wings and the taur are each a layer")
	TEST_ASSERT(pack.layer > wings.layer, "the backpack is drawn over the wings")
	TEST_ASSERT(tail.layer > body_image.layer, "the taur is drawn over the body")
	TEST_ASSERT(wings.layer > tail.layer, "the wings are over the taur")

	var/list/bad = list()
	for(var/d in list(SOUTH, NORTH, EAST, WEST))
		H.set_dir(d)
		H.animate_tail_stop()
		refresh_flush()
		var/list/whole = dq_real_pixels(H, d)
		TEST_ASSERT(length(whole) > 100, "[dir2text(d)]: the character draws")
		// The torso's own pixels are all in the body: a missing arm leaves no cut in it.
		var/obj/item/organ/external/torso = H.limb_tagged(BP_TORSO)
		var/image/torso_image = image(icon = 'icons/mob/human.dmi', icon_state = "blank")
		look_composed_image(torso_image, torso.layered_parts(FALSE))
		var/list/body_pixels = dq_real_pixels(body_image, d)
		var/torso_lost = 0
		for(var/key in dq_real_pixels(torso_image, d))
			if(!(key in body_pixels))
				torso_lost++
		if(torso_lost)
			bad += "[dir2text(d)] torso lost [torso_lost] to the body"
		// The prosthetic arm is in the body wherever its sprite has pixels.
		var/image/arm_image = image(icon = 'icons/mob/human.dmi', icon_state = "blank")
		look_composed_image(arm_image, arm.layered_parts(FALSE))
		var/arm_pixels = length(dq_real_pixels(arm_image, d))
		var/arm_in_body = 0
		for(var/key in dq_real_pixels(arm_image, d))
			if(key in body_pixels)
				arm_in_body++
		if(arm_in_body != arm_pixels)
			bad += "[dir2text(d)] the arm has [arm_pixels] pixels, the body shows [arm_in_body]"
	TEST_ASSERT(!length(bad), "the real character: [jointext(bad, "; ")]")
	test_driver_end()

/// The examine portrait of the real character (the iconforge translation of the layered body) is the picture getFlatIcon makes, facing south and north.
/datum/unit_test/dq_body_render_real_portrait

/datum/unit_test/dq_body_render_real_portrait/Run()
	test_driver_begin()
	var/mob/living/carbon/human/H = dq_real_character()
	for(var/d in list(SOUTH, NORTH))
		H.set_dir(d)
		H.animate_tail_stop()
		refresh_flush()
		draw_now(H)
		var/datum/portrait/P = portrait_request(H, d)
		for(var/i in 1 to 60)
			if(P?.picture)
				break
			test_time(0.25 SECONDS)
			P = portrait_request(H, d)
		TEST_ASSERT(P, "[dir2text(d)]: the portrait landed")
		if(!P)
			continue
		var/list/report = list()
		var/mismatches = dq_test_portrait_mismatches(getFlatIcon(H, d), P.picture, report)
		TEST_ASSERT_EQUAL(mismatches, 0, "[dir2text(d)]: the portrait differs from getFlatIcon ([json_encode(report)])")
	test_driver_end()

/// A husk, a see-through body and a dead limb are drawn as layers and keep what the composed body gave them: the husk is toned, the slime fades as one picture, the dead limb is dark.
/datum/unit_test/dq_body_render_forms_as_layers

/datum/unit_test/dq_body_render_forms_as_layers/Run()
	test_driver_begin()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.set_species(SPECIES_HUMAN)
	refresh_flush()
	var/image/plain = H.build_layered_body_look('icons/mob/human.dmi', FALSE, FALSE)[2]
	var/image/husk = H.build_layered_body_look('icons/mob/human.dmi', FALSE, FALSE, TRUE)[2]
	TEST_ASSERT(husk.appearance_flags & KEEP_TOGETHER, "a husk is one toned picture")
	TEST_ASSERT(length(husk.overlays) >= 1, "a husk has its limbs")
	var/image/glass = H.build_layered_body_look('icons/mob/human.dmi', FALSE, FALSE, FALSE, TRUE)[2]
	TEST_ASSERT_EQUAL(glass.alpha, 180, "a body that is see-through as a whole fades as one")
	TEST_ASSERT(glass.appearance_flags & KEEP_TOGETHER, "and is rendered before it fades")
	TEST_ASSERT_EQUAL(plain.alpha, 255, "a plain body does not fade")
	// A see-through arm on an otherwise solid body fades by itself; a dead one is toned; a normal one is neither.
	var/obj/item/organ/external/arm = H.limb_tagged(BP_L_ARM)
	TEST_ASSERT_EQUAL(arm.layered_alpha(FALSE, FALSE), 255, "a solid arm is opaque")
	arm.set_transparent(TRUE)
	TEST_ASSERT_EQUAL(arm.layered_alpha(FALSE, FALSE), 180, "a see-through arm fades")
	TEST_ASSERT_EQUAL(arm.layered_alpha(FALSE, TRUE), 255, "unless the whole body fades already")
	TEST_ASSERT(islist(arm.layered_base_color(FALSE)), "and its sprite is greyed by a matrix")
	arm.set_transparent(FALSE)
	arm.set_status(arm.status | ORGAN_DEAD)
	TEST_ASSERT(islist(arm.layered_base_color(FALSE)), "a dead arm is toned by a matrix")
	arm.set_status(arm.status & ~ORGAN_DEAD)
	var/list/identity = human_matrix_identity()
	var/list/twice = human_matrix_then(identity, human_tint_matrix("#808080"))
	TEST_ASSERT(abs(twice[1] - 128 / 255) < 0.001 && abs(twice[6] - 128 / 255) < 0.001 && abs(twice[11] - 128 / 255) < 0.001, "a multiply tint is a diagonal matrix")
	test_driver_end()
