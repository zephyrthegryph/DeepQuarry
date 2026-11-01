// Clothing colour channels (code/content/gear/clothing_channels.dm).

#define DQ_CC_TEST_TYPE /obj/item/clothing/under/color/black

/datum/unit_test/dq_clothing_unrecoloured_is_unchanged

/datum/unit_test/dq_clothing_unrecoloured_is_unchanged/Run()
	var/obj/item/clothing/under/plain = new DQ_CC_TEST_TYPE(run_loc_floor_bottom_left)
	var/original_icon = plain.icon
	var/datum/gear_tweak/recolor/tweak = new
	tweak.tweak_item(plain, list("mode" = "off"))
	tweak.tweak_item(plain, list("mode" = "channels", "value" = list("", "", "")))
	tweak.tweak_item(plain, list("mode" = "channels", "value" = list()))
	TEST_ASSERT_EQUAL(plain.icon, original_icon, "an empty choice changed the item icon")
	TEST_ASSERT(!sparse_has(plain, clothing_channel_colors), "an empty choice left colours on the item")
	var/image/worn = plain.make_worn_icon(slot_name = slot_w_uniform_str, default_icon = INV_W_UNIFORM_DEF_ICON)
	TEST_ASSERT_EQUAL(worn.icon_state, plain.get_worn_icon_state(slot_w_uniform_str), "an unrecoloured item changed its worn state")
	// The base colour of every channel is exactly the original art: no swaps at all.
	var/list/found = clothing_channels_of(DQ_CC_TEST_TYPE)
	var/list/bases = clothing_channel_bases(DQ_CC_TEST_TYPE)
	TEST_ASSERT_EQUAL(length(build_clothing_channel_swaps(found[2], jointext(bases, "|"))), 0, "choosing the base colours produced swaps")
	qdel(plain)

/datum/unit_test/dq_clothing_mapping_no_double_swap

/datum/unit_test/dq_clothing_mapping_no_double_swap/Run()
	// A chain (red -> blue -> green) and a cycle (white <-> black), on real pixels.
	var/icon/canvas = icon('icons/effects/effects.dmi', "nothing")
	canvas.Scale(4, 1)
	canvas.DrawBox("#ff0000", 1, 1)
	canvas.DrawBox("#0000ff", 2, 1)
	canvas.DrawBox("#ffffff", 3, 1)
	canvas.DrawBox("#000000", 4, 1)
	var/list/swaps = clothing_channel_order_swaps(list("#ff0000" = "#0000ff", "#0000ff" = "#00ff00", "#ffffff" = "#000000", "#000000" = "#ffffff"))
	for(var/i = 1; i < length(swaps); i += 2)
		canvas.SwapColor(swaps[i], swaps[i + 1])
	TEST_ASSERT_EQUAL(canvas.GetPixel(1, 1), "#0000ff", "red was swapped twice")
	TEST_ASSERT_EQUAL(canvas.GetPixel(2, 1), "#00ff00", "blue did not reach green")
	TEST_ASSERT_EQUAL(canvas.GetPixel(3, 1), "#000000", "a cycle double swapped white")
	TEST_ASSERT_EQUAL(canvas.GetPixel(4, 1), "#ffffff", "a cycle double swapped black")

/datum/unit_test/dq_clothing_cache_hit

/datum/unit_test/dq_clothing_cache_hit/Run()
	var/list/colors = list("#123456", "#654321", "#abcdef")
	var/obj/item/clothing/under/first = new DQ_CC_TEST_TYPE(run_loc_floor_bottom_left)
	var/obj/item/clothing/under/second = new DQ_CC_TEST_TYPE(run_loc_floor_bottom_left)
	var/original_icon = first.icon
	TEST_ASSERT(first.apply_clothing_channels(colors), "the test type has no channels")
	var/builds_before = _sc_clothing_channel_item_sheets.builds
	TEST_ASSERT(second.apply_clothing_channels(colors), "the second item was refused")
	TEST_ASSERT_EQUAL(_sc_clothing_channel_item_sheets.builds, builds_before, "an identical outfit rebuilt the item sheet")
	TEST_ASSERT(first.icon == second.icon && first.icon != original_icon, "identical outfits do not share one recoloured sheet")
	var/image/worn_first = first.make_worn_icon(slot_name = slot_w_uniform_str, default_icon = INV_W_UNIFORM_DEF_ICON)
	var/worn_builds = _sc_clothing_channel_icons.builds
	var/image/worn_second = second.make_worn_icon(slot_name = slot_w_uniform_str, default_icon = INV_W_UNIFORM_DEF_ICON)
	TEST_ASSERT_EQUAL(_sc_clothing_channel_icons.builds, worn_builds, "an identical outfit rebuilt the worn sprite")
	TEST_ASSERT(!worn_first.icon_state && worn_first.icon == worn_second.icon, "identical outfits do not share one worn sprite")
	// The item state keeps its name, and the base art really changed.
	TEST_ASSERT(first.icon_state in icon_states(first.icon), "the item sheet lost the item's state")
	qdel(first)
	qdel(second)

/datum/unit_test/dq_clothing_override_beats_generated

/datum/unit_test/dq_clothing_override_beats_generated/Run()
	var/list/data = clothing_channel_data_load()
	var/key = "[DQ_CC_TEST_TYPE]"
	TEST_ASSERT(length(clothing_channels_of(DQ_CC_TEST_TYPE)), "the test type has no generated channels")
	var/list/keep = data["overrides"][key]

	data["overrides"][key] = list("channels" = list("112233445566"))
	var/list/found = clothing_channels_of(DQ_CC_TEST_TYPE)
	TEST_ASSERT_EQUAL(found[2][1], "112233445566", "override channels did not win")
	TEST_ASSERT_EQUAL(found[1], "o[key]", "an override shares the generated cache key")

	data["overrides"][key] = list("channels" = list("112233445566", "778899"), "move" = list("445566" = 2, "112233" = 0))
	found = clothing_channels_of(DQ_CC_TEST_TYPE)
	TEST_ASSERT_EQUAL(found[2][1], "", "a locked colour stayed in its channel")
	TEST_ASSERT_EQUAL(found[2][2], "778899445566", "a moved colour did not reach its channel")

	data["overrides"][key] = list("disabled" = TRUE)
	TEST_ASSERT_NULL(clothing_channels_of(DQ_CC_TEST_TYPE), "a disabled type still has channels")

	data["overrides"] -= key
	if(keep)
		data["overrides"][key] = keep

/datum/unit_test/dq_clothing_colors_roundtrip

/datum/unit_test/dq_clothing_colors_roundtrip/Run()
	var/datum/preference_editor/loadout/editor = GLOB.preference_editors_by_key["loadout"]
	var/datum/preferences/dq_loadout_test_stub/p = new()
	var/datum/gear/chosen
	var/tweak_idx
	for(var/name in GLOB.gear_datums)
		var/datum/gear/G = GLOB.gear_datums[name]
		if(!G.slot || G.slot == SLOT_ID_TIE || !G.is_pickable_by(p) || !length(clothing_channel_bases(G.path)))
			continue
		for(var/i in 1 to length(G.gear_tweaks))
			if(istype(LAZYACCESS(G.gear_tweaks, i), /datum/gear_tweak/recolor))
				chosen = G
				tweak_idx = i
		if(chosen)
			break
	TEST_ASSERT_NOTNULL(chosen, "no gear with channels and a recolor tweak")
	editor.handle_action(p, "set_loadout_key", list("key" = "_default"), null)
	TEST_ASSERT_EQUAL(editor.handle_action(p, "set_body_slot", list("body_slot" = chosen.slot, "gear" = chosen.display_name), null), PREF_UPDATE_ACCEPTED, "could not add the gear")
	var/result = editor.handle_action(p, "set_recolor", list("gear" = chosen.display_name, "tweak" = tweak_idx, "value" = list("mode" = "channels", "value" = list("#AABBCC", "primary", "not a colour", "#000000"))), null)
	TEST_ASSERT_EQUAL(result, PREF_UPDATE_ACCEPTED, "set_recolor refused channels")
	var/list/gear_list = p.read_preference(/datum/preference/gear_list)
	// What a save does to it.
	var/list/saved = json_decode(json_encode(gear_list))
	var/list/meta = saved["_default"][chosen.display_name]["[tweak_idx]"]
	TEST_ASSERT_EQUAL(meta["mode"], "channels", "the mode did not survive a save")
	TEST_ASSERT_EQUAL(jointext(meta["value"], ","), "#aabbcc,primary,", "the colours did not survive a save")
	// A linked channel follows the palette when the item spawns; the saved form keeps the link.
	var/list/resolved = clothing_channel_resolve_links(saved["_default"][chosen.display_name], p)
	TEST_ASSERT_EQUAL(resolved["[tweak_idx]"]["value"][2], p.read_preference(/datum/preference/color/human/color_slot/primary), "a linked channel did not resolve")
	TEST_ASSERT_EQUAL(meta["value"][2], "primary", "resolving wrote into the saved metadata")
	qdel(p, TRUE) // preferences are kept unless forced (LIFECYCLE_KEEP_UNLESS_FORCED)

#undef DQ_CC_TEST_TYPE
