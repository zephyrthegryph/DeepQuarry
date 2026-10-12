// The human's look (code/modules/mob/living/carbon/human/human_look.dm): pinned across the move from the hand-kept overlays_standing
// renderer to draw(look). Each standard body is dressed the same way, its look settles, and the pin is the flat picture of every facing
// (md5) plus the layers off the base plane (emissive blockers, glowing eyes), which a flat picture does not show.

/// Sets `var_name` of H to `value` the way the game does (its setter when it has one).
/datum/unit_test/proc/dq_hd_set(mob/living/carbon/human/H, var_name, value)
	if(hascall(H, "set_[var_name]"))
		call(H, "set_[var_name]")(value)
	else
		H.vars[var_name] = value

/// The pin rows of H: one md5 per facing and the off-plane layers.
/datum/unit_test/proc/dq_hd_rows(mob/living/carbon/human/H)
	. = list()
	var/start_dir = H.dir
	for(var/d in list(SOUTH, NORTH, EAST, WEST))
		H.set_dir(d)
		H.animate_tail_stop() // a species tail idles on a random loop; the pin holds the still one
		appearance_flush()
		. += "[dir2text(d)]=[md5(icon2base64(getFlatIcon(H, d)))]"
	H.set_dir(start_dir)
	appearance_flush()
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
	log_test("human look pin: making [name]")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.set_species(species)
	H.set_dir(SOUTH)
	appearance_flush()
	return H

/datum/unit_test/dq_human_look_pin

/datum/unit_test/dq_human_look_pin/Run()
	var/list/got = list()

	var/mob/living/carbon/human/H = dq_hd_body(got, "bare")
	got["bare"] = dq_hd_rows(H)

	H = dq_hd_body(got, "dressed")
	dq_profile_dress(H, -40)
	dq_hd_dress(H)
	got["dressed"] = dq_hd_rows(H)

	H = dq_hd_body(got, "cuffed")
	H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
	H.equip_to_slot_or_del(new /obj/item/handcuffs(H), SLOT_ID_HANDCUFFED)
	H.equip_to_slot_or_del(new /obj/item/handcuffs/legcuffs(H), SLOT_ID_LEGCUFFED)
	got["cuffed"] = dq_hd_rows(H)

	H = dq_hd_body(got, "tajaran", SPECIES_TAJARAN)
	dq_profile_dress(H, 0)
	H.looks.set_digitigrade(1)
	H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
	got["tajaran"] = dq_hd_rows(H)

	H = dq_hd_body(got, "styled")
	dq_profile_dress(H, 0)
	H.looks.set_tail_color(rgb(200, 90, 30))
	H.looks.set_wing_color(rgb(30, 90, 200))
	H.looks.set_ears_color(rgb(90, 200, 30))
	dq_hd_set(H, "tail_style", GLOB.tail_styles_list[/datum/sprite_accessory/tail/squirrel])
	dq_hd_set(H, "wing_style", GLOB.wing_styles_list[/datum/sprite_accessory/wing/moth])
	dq_hd_set(H, "ear_style", GLOB.ear_styles_list[/datum/sprite_accessory/ears/taj_ears])
	H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
	H.regenerate_icons()
	got["styled"] = dq_hd_rows(H)

	H = dq_hd_body(got, "taur")
	dq_hd_set(H, "tail_style", GLOB.tail_styles_list[/datum/sprite_accessory/tail/taur/wolf])
	H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
	H.equip_to_slot_or_del(new /obj/item/clothing/suit/storage/hazardvest(H), SLOT_ID_SUIT)
	H.regenerate_icons()
	got["taur"] = dq_hd_rows(H)

	H = dq_hd_body(got, "hurt")
	H.injure(INJURY_CUT, 30, BP_TORSO, flags = INJURE_SILENT)
	H.injure(INJURY_BURN, 30, BP_L_ARM, flags = INJURE_SILENT)
	got["hurt"] = dq_hd_rows(H)

	H = dq_hd_body(got, "unathi", SPECIES_UNATHI)
	dq_profile_dress(H, 0)
	H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
	got["unathi"] = dq_hd_rows(H)

	H = dq_hd_body(got, "teshari", SPECIES_TESHARI)
	dq_profile_dress(H, 0)
	H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
	got["teshari"] = dq_hd_rows(H)

	H = dq_hd_body(got, "spacesuit")
	dq_profile_dress(H, 0)
	H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
	H.equip_to_slot_or_del(new /obj/item/clothing/suit/space(H), SLOT_ID_SUIT)
	H.equip_to_slot_or_del(new /obj/item/clothing/head/helmet/space(H), SLOT_ID_HEAD)
	got["spacesuit"] = dq_hd_rows(H)

	var/list/expected = dq_hd_expected()
	var/list/moved = list()
	for(var/name in got)
		var/rows = jointext(got[name], " ")
		log_test("human look pin [name]: [rows]")
		if(rows != expected[name])
			moved += "[name]: [rows] (was [expected[name]])"
	TEST_ASSERT(!length(moved), "these bodies look different from the recorded pins:\n[jointext(moved, "\n")]")
	TEST_ASSERT(expected["bare"] != expected["dressed"], "the pin sees clothes")

/// The rows recorded on the hand-kept renderer, before the draw conversion.
/datum/unit_test/proc/dq_hd_expected()
	return list(
		"bare" = "south=4de6a60ec60d1733176e8fa2e1bf4fc0 north=a3d96946174883142b8359916d8815cf east=53441521cc3892d67e583b208bc5dacf west=9f16ae176c73745e681b0ba4fd63cf71 plane -100 x1 plane 15 x1 plane 16 x1 plane 17 x1 plane 18 x1 plane 19 x1 plane 20 x1 plane 21 x1 plane 22 x1 plane 23 x1 plane 24 x1 plane 26 x1 plane 27 x1 plane 28 x1 plane 29 x1 plane 8 x1",
		"dressed" = "south=317c345a56a4cb8f0b5ca2f797e07f59 north=00d99dbfe17d29c4c659b9903ef38c26 east=262d4a0e243831d0f4d536dbf375984f west=046af19efa58a3deb941aee7ca862127 plane -100 x1 plane 15 x1 plane 16 x1 plane 17 x1 plane 18 x1 plane 19 x1 plane 20 x1 plane 21 x1 plane 22 x1 plane 23 x1 plane 24 x1 plane 26 x1 plane 27 x1 plane 28 x1 plane 29 x1 plane 8 x1",
		"cuffed" = "south=0f5d53c26e753b96393a278bbef6e259 north=427db6c458a7edec10fdf4fdb285913b east=dee7f8e70d8d91df295e1ae5b8e35f53 west=7169d0227138a70b721e423c7cfd9409 plane -100 x1 plane 15 x1 plane 16 x1 plane 17 x1 plane 18 x1 plane 19 x1 plane 20 x1 plane 21 x1 plane 22 x1 plane 23 x1 plane 24 x1 plane 26 x1 plane 27 x1 plane 28 x1 plane 29 x1 plane 8 x1",
		"tajaran" = "south=c3ff700384721716dbefa6160da8e702 north=9a5278becb9bf7f580e3575625cad355 east=56a55ba0c0810c7ab11f4faf12b6e57d west=f4bb19795bf57d0d4dfd56187e93ed86 plane -100 x1 plane 15 x1 plane 16 x1 plane 17 x1 plane 18 x1 plane 19 x1 plane 20 x1 plane 21 x1 plane 22 x1 plane 23 x1 plane 24 x1 plane 26 x1 plane 27 x1 plane 28 x1 plane 29 x1 plane 8 x1",
		"styled" = "south=c267b8c20e37e4661f086479aeebe08a north=108acf281a4350ca0dbc9e17021df28b east=c929b6b2879ae2521464d8d6684c1cc7 west=b855108a8fd17b57b599eec9b119fdb3 plane -100 x1 plane 15 x1 plane 16 x1 plane 17 x1 plane 18 x1 plane 19 x1 plane 20 x1 plane 21 x1 plane 22 x1 plane 23 x1 plane 24 x1 plane 26 x1 plane 27 x1 plane 28 x1 plane 29 x1 plane 8 x1",
		"taur" = "south=ba84895e2844a2e226dcfdeefe5d2e89 north=59943f735817042ca0b80d1380f33776 east=713fb9717e32d8556a78143aa4067362 west=2ff59eb6595338252322be5c78d7f2b5 plane -100 x1 plane 15 x1 plane 16 x1 plane 17 x1 plane 18 x1 plane 19 x1 plane 20 x1 plane 21 x1 plane 22 x1 plane 23 x1 plane 24 x1 plane 26 x1 plane 27 x1 plane 28 x1 plane 29 x1 plane 8 x1",
		"hurt" = "south=4de6a60ec60d1733176e8fa2e1bf4fc0 north=a3d96946174883142b8359916d8815cf east=53441521cc3892d67e583b208bc5dacf west=9f16ae176c73745e681b0ba4fd63cf71 plane -100 x1 plane 15 x1 plane 16 x1 plane 17 x1 plane 18 x1 plane 19 x1 plane 20 x1 plane 21 x1 plane 22 x1 plane 23 x1 plane 24 x1 plane 26 x1 plane 27 x1 plane 28 x1 plane 29 x1 plane 8 x1",
		"unathi" = "south=9b7ad5489bae96ef628fdfcdda42c07f north=2de9f9a412f654dcd57d54e21278d80a east=6cd6c47c766b7acd11263a4065b38c75 west=bc2ee1cbfcc5bc1e050bd801e18eb6be plane -100 x1 plane 15 x1 plane 16 x1 plane 17 x1 plane 18 x1 plane 19 x1 plane 20 x1 plane 21 x1 plane 22 x1 plane 23 x1 plane 24 x1 plane 26 x1 plane 27 x1 plane 28 x1 plane 29 x1 plane 8 x1",
		"teshari" = "south=7e8c2fba53f0a20731d2f296e02ddde5 north=0fb0fb0845eb875b1916671dde6a0db3 east=6c589c6462b76f02e831de3801a5ae30 west=1153ba0ac52c9cb864c5010ed3cd87ff plane -100 x1 plane 15 x1 plane 16 x1 plane 17 x1 plane 18 x1 plane 19 x1 plane 20 x1 plane 21 x1 plane 22 x1 plane 23 x1 plane 24 x1 plane 26 x1 plane 27 x1 plane 28 x1 plane 29 x1 plane 8 x1",
		"spacesuit" = "south=e1af2848399cf854834c794b043358ba north=8691556a6520afaabf2c1aa26e54c5b3 east=b1ef516e66d545e1757c62cdb50fc025 west=a05c7c5fe74108dfa46e5625336c0331 plane -100 x1 plane 15 x1 plane 16 x1 plane 17 x1 plane 18 x1 plane 19 x1 plane 20 x1 plane 21 x1 plane 22 x1 plane 23 x1 plane 24 x1 plane 26 x1 plane 27 x1 plane 28 x1 plane 29 x1 plane 8 x1",
	)

/// The flat picture of H facing south: what a redraw changes.
/datum/unit_test/proc/dq_hd_picture(mob/living/carbon/human/H)
	appearance_flush()
	return md5(icon2base64(getFlatIcon(H, SOUTH)))

/// Putting a uniform on redraws the human with it and taking it off redraws it without, nobody calls a redraw.
/datum/unit_test/dq_human_draw_equip_unequip_redraws

/datum/unit_test/dq_human_draw_equip_unequip_redraws/Run()
	var/mob/living/carbon/human/H = dq_hd_body(list(), "equip")
	var/bare = dq_hd_picture(H)
	var/obj/item/clothing/under/color/grey/uniform = new(H)
	H.equip_to_slot_or_del(uniform, SLOT_ID_UNIFORM)
	TEST_ASSERT(H.look_layers()[UNIFORM_LAYER], "the uniform has a layer once worn")
	var/dressed = dq_hd_picture(H)
	TEST_ASSERT(dressed != bare, "wearing a uniform changes the drawn human")
	H.drop_from_inventory(uniform)
	TEST_ASSERT(!H.look_layers()[UNIFORM_LAYER], "the layer is gone once it is off")
	TEST_ASSERT_EQUAL(dq_hd_picture(H), bare, "taking it off draws the bare human again")

/// A tail is drawn under the uniform from the south and over it from the north.
/datum/unit_test/dq_human_draw_tail_layers_against_uniform

/datum/unit_test/dq_human_draw_tail_layers_against_uniform/Run()
	var/mob/living/carbon/human/H = dq_hd_body(list(), "tail")
	dq_hd_set(H, "tail_style", GLOB.tail_styles_list[/datum/sprite_accessory/tail/squirrel])
	H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
	H.set_dir(SOUTH)
	var/list/south = H.look_layers()
	TEST_ASSERT(south[TAIL_LOWER_LAYER], "facing south the tail is on the lower layer")
	TEST_ASSERT(!south[TAIL_UPPER_LAYER], "and not on the upper one")
	TEST_ASSERT(TAIL_LOWER_LAYER < UNIFORM_LAYER, "the lower tail layer sits under the uniform")
	var/south_picture = dq_hd_picture(H)
	H.set_dir(NORTH)
	var/list/north = H.look_layers()
	TEST_ASSERT(north[TAIL_UPPER_LAYER], "facing north the tail is on the upper layer")
	TEST_ASSERT(!north[TAIL_LOWER_LAYER], "and not on the lower one")
	TEST_ASSERT(TAIL_UPPER_LAYER > UNIFORM_LAYER, "the upper tail layer sits over the uniform")
	TEST_ASSERT(dq_hd_picture(H) != south_picture, "the facing changes the drawn human")

/// An injury draws its overlay and healing it takes the overlay off.
/datum/unit_test/dq_human_draw_damage_overlay_follows_injury

/datum/unit_test/dq_human_draw_damage_overlay_follows_injury/Run()
	var/mob/living/carbon/human/H = dq_hd_body(list(), "damage")
	TEST_ASSERT(!H.look_layers()[MOB_DAM_LAYER], "an unhurt human has no damage overlay")
	var/unhurt = dq_hd_picture(H)
	H.injure(INJURY_BURN, 60, BP_TORSO, flags = INJURE_SILENT)
	TEST_ASSERT(H.look_layers()[MOB_DAM_LAYER], "a burn on the torso draws a damage overlay")
	TEST_ASSERT(dq_hd_picture(H) != unhurt, "and the drawn human shows it")
	H.fully_heal()
	TEST_ASSERT(!H.look_layers()[MOB_DAM_LAYER], "healing takes the overlay off")
