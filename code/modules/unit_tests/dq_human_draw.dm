// The human's look (code/modules/mob/living/carbon/human/human_look.dm): pinned across the move from the hand-kept overlays_standing
// renderer to draw(look). Each standard body is dressed the same way, its look settles, and the pin is the flat picture of every facing
// (md5) plus the layers off the base plane (emissive blockers, glowing eyes), which a flat picture does not show.

/// Sets `var_name` of H to `value` the way the game does (its setter when it has one).
/datum/unit_test/proc/dq_hd_set(mob/living/carbon/human/H, var_name, value)
	if(hascall(H, "set_[var_name]"))
		call(H, "set_[var_name]")(value)
	else
		H.vars[var_name] = value

/// The pin rows of H: one md5 of the picture's pixels per facing (not of its PNG, whose palette is not part of the look) and the off-plane
/// layers. The draw runs by itself after every turn: nothing here asks for it.
/datum/unit_test/proc/dq_hd_rows(mob/living/carbon/human/H)
	. = list()
	var/start_dir = H.dir
	for(var/d in list(SOUTH, NORTH, EAST, WEST))
		H.set_dir(d)
		H.animate_tail_stop() // a species tail idles on a random loop; the pin holds the still one
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
	log_test("human look pin: making [name]")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.set_species(species)
	H.set_dir(SOUTH)
	refresh_flush()
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
	got["styled"] = dq_hd_rows(H)

	H = dq_hd_body(got, "taur")
	dq_hd_set(H, "tail_style", GLOB.tail_styles_list[/datum/sprite_accessory/tail/taur/wolf])
	H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
	H.equip_to_slot_or_del(new /obj/item/clothing/suit/storage/hazardvest(H), SLOT_ID_SUIT)
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

/// The rows recorded from the picture of each body (the hand-kept renderer's, fully redrawn, and draw(look) agree on every body but the
/// species with a tail and a hair style, which the old one did not redraw after the profile was applied: the new rows are those bodies as they
/// are dressed).
/datum/unit_test/proc/dq_hd_expected()
	return list(
		"bare" = "south=5620d6402c8badb5cd567976b2c80c6f north=cd6cce7fa5e6a178db2075cf751c1db6 east=a85693ac9d2a26530d2797f4c2901f0a west=b23891ebabd748ad9cabfac6f903880c plane -100 x1 plane 15 x1 plane 16 x1 plane 17 x1 plane 18 x1 plane 19 x1 plane 20 x1 plane 21 x1 plane 22 x1 plane 23 x1 plane 24 x1 plane 26 x1 plane 27 x1 plane 28 x1 plane 29 x1 plane 8 x1",
		"dressed" = "south=5764fa10049ba77aafa68a4516a7d956 north=2603ae7e4e1ada0a40c226bd3929338e east=1bedb5cd1a0ef6973975bde8048b160a west=3a5ef0f43e725bfd69b2aefc4b31b75f plane -100 x1 plane 15 x1 plane 16 x1 plane 17 x1 plane 18 x1 plane 19 x1 plane 20 x1 plane 21 x1 plane 22 x1 plane 23 x1 plane 24 x1 plane 26 x1 plane 27 x1 plane 28 x1 plane 29 x1 plane 8 x1",
		"cuffed" = "south=9c4673ffebca656e003aea294548c93f north=fde27e7bf498bd1f4e96379846bb5d58 east=8ffcb73db41f3fb8e1d377e4c1e66f6e west=8fc0038e90b81f70eea25bd2dc3c5dc3 plane -100 x1 plane 15 x1 plane 16 x1 plane 17 x1 plane 18 x1 plane 19 x1 plane 20 x1 plane 21 x1 plane 22 x1 plane 23 x1 plane 24 x1 plane 26 x1 plane 27 x1 plane 28 x1 plane 29 x1 plane 8 x1",
		"tajaran" = "south=4ef57ca2ac3a989c76caf2a51ac3bd0d north=713fe267564e3e51693affcdffa197bb east=c7aa08b32ca5ef0d8a9849f8381d77b3 west=ef47a4079613a909645d3b9602c8b105 plane -100 x1 plane 15 x1 plane 16 x1 plane 17 x1 plane 18 x1 plane 19 x1 plane 20 x1 plane 21 x1 plane 22 x1 plane 23 x1 plane 24 x1 plane 26 x1 plane 27 x1 plane 28 x1 plane 29 x1 plane 8 x1",
		"styled" = "south=077e8f6f1decd1d018746bba470b32cc north=de735c1841662c2bf3aae12ab73e01a7 east=25d807a73a678b5386e742874bf189e7 west=5b268ffa55967ea2df34cdf2dcb386a1 plane -100 x1 plane 15 x1 plane 16 x1 plane 17 x1 plane 18 x1 plane 19 x1 plane 20 x1 plane 21 x1 plane 22 x1 plane 23 x1 plane 24 x1 plane 26 x1 plane 27 x1 plane 28 x1 plane 29 x1 plane 8 x1",
		"taur" = "south=7e6e2d9807c98694ed9ea32a2a8b301b north=b967f1d829f4f449fc4454a94651e9b2 east=539fe277444074c115b064ff0c26a6a2 west=953cc83d3da29ec93b110f98f6aa7c03 plane -100 x1 plane 15 x1 plane 16 x1 plane 17 x1 plane 18 x1 plane 19 x1 plane 20 x1 plane 21 x1 plane 22 x1 plane 23 x1 plane 24 x1 plane 26 x1 plane 27 x1 plane 28 x1 plane 29 x1 plane 8 x1",
		"hurt" = "south=943e989a060d58f01935fc29cf7dbaa9 north=da8e0088020070444c9e9a37c40b562d east=9e8fe5d3fce69f4b275f4655bfc1fd6d west=fe789a76d456ddfa76327007bf291c77 plane -100 x1 plane 15 x1 plane 16 x1 plane 17 x1 plane 18 x1 plane 19 x1 plane 20 x1 plane 21 x1 plane 22 x1 plane 23 x1 plane 24 x1 plane 26 x1 plane 27 x1 plane 28 x1 plane 29 x1 plane 8 x1",
		"unathi" = "south=b3a636ad41e05fcafab0d410884e0bbc north=d8988be42c55f7b84bb0f15ab376e4b2 east=be2526c2221bde1d7f66deee4c16222f west=033507340087bc4a1b9bb4c242bf74f7 plane -100 x1 plane 15 x1 plane 16 x1 plane 17 x1 plane 18 x1 plane 19 x1 plane 20 x1 plane 21 x1 plane 22 x1 plane 23 x1 plane 24 x1 plane 26 x1 plane 27 x1 plane 28 x1 plane 29 x1 plane 8 x1",
		"teshari" = "south=03a97ed9b84f3119e55550ba342b243c north=769330f4c2465cabf12b7fe322ca1d94 east=f20ed00ed9e0d167b782d1bd27f90643 west=e2bf76866c0a8b625f53481f1d02f596 plane -100 x1 plane 15 x1 plane 16 x1 plane 17 x1 plane 18 x1 plane 19 x1 plane 20 x1 plane 21 x1 plane 22 x1 plane 23 x1 plane 24 x1 plane 26 x1 plane 27 x1 plane 28 x1 plane 29 x1 plane 8 x1",
		"spacesuit" = "south=a8ddf568bcc07e083d03721d4760e437 north=6336c54e136affff1082a0ec7a4d096d east=307a8346572ef20cdc02b6d2218da254 west=ea6edd391d3d53bbe048a064bf98bbf3 plane -100 x1 plane 15 x1 plane 16 x1 plane 17 x1 plane 18 x1 plane 19 x1 plane 20 x1 plane 21 x1 plane 22 x1 plane 23 x1 plane 24 x1 plane 26 x1 plane 27 x1 plane 28 x1 plane 29 x1 plane 8 x1",
	)

/// The flat picture of H facing south: what a redraw changes.
/datum/unit_test/proc/dq_hd_picture(mob/living/carbon/human/H)
	refresh_flush()
	return md5(icon2base64(getFlatIcon(H, SOUTH)))

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
