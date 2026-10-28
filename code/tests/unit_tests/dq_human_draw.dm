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
