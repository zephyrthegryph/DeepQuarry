// Clothing colour channels (code/content/gear/clothing_channels.dm).

#define DQ_CC_TEST_TYPE /obj/item/clothing/under/color/black

/datum/unit_test/dq_clothing_unrecoloured_is_unchanged

/datum/unit_test/dq_clothing_unrecoloured_is_unchanged/Run()
	var/obj/item/clothing/under/plain = new DQ_CC_TEST_TYPE(run_loc_floor_bottom_left)
	var/original_icon = plain.icon
	var/datum/gear_tweak/channels/tweak = new
	tweak.tweak_item(plain, null)
	tweak.tweak_item(plain, list("", "", ""))
	tweak.tweak_item(plain, list())
	TEST_ASSERT_EQUAL(plain.icon, original_icon, "an empty choice changed the item icon")
	TEST_ASSERT(!(!isnull(STATE_PEEK(plain, item_misc, clothing_channel_colors))), "an empty choice left colours on the item")
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
			if(istype(LAZYACCESS(G.gear_tweaks, i), /datum/gear_tweak/channels))
				chosen = G
				tweak_idx = i
		if(chosen)
			break
	TEST_ASSERT_NOTNULL(chosen, "no gear with channels and a channels tweak")
	editor.handle_action(p, "set_loadout_key", list("key" = "_default"), null)
	TEST_ASSERT_EQUAL(editor.handle_action(p, "set_body_slot", list("body_slot" = chosen.slot, "gear" = chosen.display_name), null), PREF_UPDATE_ACCEPTED, "could not add the gear")
	var/result = editor.handle_action(p, "set_channels", list("gear" = chosen.display_name, "tweak" = tweak_idx, "value" = list("#AABBCC", "primary", "not a colour", "#000000")), null)
	TEST_ASSERT_EQUAL(result, PREF_UPDATE_ACCEPTED, "set_channels refused channels")
	var/list/gear_list = p.read_preference(/datum/preference/gear_list)
	// What a save does to it.
	var/list/saved = json_decode(json_encode(gear_list))
	var/list/meta = saved["_default"][chosen.display_name]["[tweak_idx]"]
	TEST_ASSERT_EQUAL(jointext(meta, ","), "#aabbcc,primary,", "the colours did not survive a save")
	// A linked channel follows the palette when the item spawns; the saved form keeps the link.
	var/list/resolved = clothing_channel_resolve_links(chosen, saved["_default"][chosen.display_name], p)
	TEST_ASSERT_EQUAL(resolved["[tweak_idx]"][2], p.read_preference(/datum/preference/color/human/color_slot/primary), "a linked channel did not resolve")
	TEST_ASSERT_EQUAL(meta[2], "primary", "resolving wrote into the saved metadata")
	// Old shapes the window can no longer send are refused.
	TEST_ASSERT(editor.handle_action(p, "set_recolor", list("gear" = chosen.display_name, "tweak" = tweak_idx, "value" = list("mode" = "tint", "value" = "#ff0000")), null) != PREF_UPDATE_ACCEPTED, "the removed tint action still answers")
	qdel(p, TRUE) // preferences are kept unless forced (LIFECYCLE_KEEP_UNLESS_FORCED)

/// A gear entry whose type has channels and that once had the colour tweak (colour tweak and recolor tweak both on it).
/proc/dq_cc_legacy_gear()
	for(var/name in GLOB.gear_datums)
		var/datum/gear/G = GLOB.gear_datums[name]
		var/list/bases = clothing_channel_bases(G.path)
		if(G.legacy_colour_index && G.channels_tweak_index() && length(bases) && length(bases[1]) && G.legacy_colour_index > G.channels_tweak_index())
			return G

/datum/unit_test/dq_clothing_migrates_old_colours

/datum/unit_test/dq_clothing_migrates_old_colours/Run()
	var/datum/gear/G = dq_cc_legacy_gear()
	TEST_ASSERT_NOTNULL(G, "no clothing gear that had the colour tweak")
	var/ci = "[G.channels_tweak_index()]"
	var/li = G.legacy_colour_index
	var/list/bases = clothing_channel_bases(G.path)
	var/first = bases[1]

	// The removed colour tweak: a tint of every channel, and the tweaks saved after it move down one.
	var/list/meta = list("1" = "Fancy name", "[li]" = "#ff0000", "[li + 1]" = "after the colour")
	clothing_channel_migrate_meta(G, meta)
	TEST_ASSERT_EQUAL(meta[ci][1], clothing_channel_tint(first, "#ff0000"), "the colour tweak did not become a channel tint")
	TEST_ASSERT_EQUAL(meta["[li]"], "after the colour", "the tweak after the colour did not move down")
	TEST_ASSERT_NULL(meta["[li + 1]"], "the moved tweak stayed at its old index")
	TEST_ASSERT_EQUAL(meta["1"], "Fancy name", "a tweak before the colour moved")
	var/list/again = meta.Copy()
	clothing_channel_migrate_meta(G, again)
	TEST_ASSERT_EQUAL(json_encode(again), json_encode(meta), "migrating twice changed the result")

	// The recolor tweak's modes.
	meta = list("[ci]" = list("mode" = "tint", "value" = "#00ff00"))
	clothing_channel_migrate_meta(G, meta)
	TEST_ASSERT_EQUAL(meta[ci][1], clothing_channel_tint(first, "#00ff00"), "tint did not migrate")
	var/list/swaps = list()
	swaps[uppertext(first)] = "#123456"
	meta = list("[ci]" = list("mode" = "palette", "value" = swaps))
	clothing_channel_migrate_meta(G, meta)
	TEST_ASSERT_EQUAL(meta[ci][1], "#123456", "a palette swap of a channel base did not migrate")
	// A matrix that swaps red and blue.
	meta = list("[ci]" = list("mode" = "matrix", "value" = list(0,0,1, 0,1,0, 1,0,0, 0,0,0)))
	clothing_channel_migrate_meta(G, meta)
	var/list/rgb = rgb2num(first)
	var/swapped = lowertext(rgb(rgb[3], rgb[2], rgb[1]))
	if(swapped != first)
		TEST_ASSERT_EQUAL(meta[ci][1], swapped, "a matrix did not migrate")
	meta = list("[ci]" = list("mode" = "channels", "value" = list("#abcdef", "primary")))
	clothing_channel_migrate_meta(G, meta)
	TEST_ASSERT_EQUAL(jointext(meta[ci], ","), "#abcdef,primary", "channel colours did not survive")
	meta = list("[ci]" = list("mode" = "off"))
	clothing_channel_migrate_meta(G, meta)
	TEST_ASSERT_NULL(meta[ci], "off left something behind")

	// Through the load path: the sanitizer migrates a saved loadout.
	var/datum/preference/gear_list/pref = GLOB.preference_entries[/datum/preference/gear_list]
	var/list/entry = list()
	entry[G.display_name] = list("[li]" = "#0000ff")
	var/list/saved = list("_default" = entry)
	var/list/clean = pref.sanitize(saved, null)
	TEST_ASSERT_EQUAL(clean["_default"][G.display_name][ci][1], clothing_channel_tint(first, "#0000ff"), "loading did not migrate the colour")

/datum/unit_test/dq_clothing_channels_only

/datum/unit_test/dq_clothing_channels_only/Run()
	// No clothing entry offers a plain colour: channels are the only recolour.
	for(var/name in GLOB.gear_datums)
		var/datum/gear/G = GLOB.gear_datums[name]
		if(!ispath(G.path, /obj/item/clothing) && !length(clothing_channel_bases(G.path)))
			continue
		for(var/datum/gear_tweak/gt as anything in G.gear_tweaks)
			TEST_ASSERT(!istype(gt, /datum/gear_tweak/color), "[G.display_name] ([G.path]) still has the plain colour tweak")
	TEST_ASSERT(!ispath(text2path("/datum/gear_tweak/recolor")), "the multi-mode recolor tweak still exists")
	TEST_ASSERT(!ispath(text2path("/datum/gear_tweak/matrix_recolor")), "the matrix recolor tweak still exists")

	// A coloured item gives up its own colour for its channels, on the item and on the worn sprite, and can be reset.
	var/obj/item/clothing/under/suit = new DQ_CC_TEST_TYPE(run_loc_floor_bottom_left)
	var/original_icon = suit.icon
	suit.set_color("#ff0000")
	TEST_ASSERT(suit.apply_clothing_channels(list("#336699")), "the test type has no channels")
	TEST_ASSERT_NULL(suit.color, "the item kept its plain colour")
	var/first_icon = suit.icon
	var/image/worn = suit.make_worn_icon(slot_name = slot_w_uniform_str, default_icon = INV_W_UNIFORM_DEF_ICON)
	TEST_ASSERT(isnull(worn.color) || worn.color == "#ffffff", "the worn sprite is still tinted")
	TEST_ASSERT(worn.icon != INV_W_UNIFORM_DEF_ICON, "the worn sprite was not recoloured")
	// Recolouring again starts from the original art, so the same choice gives the same sheet.
	suit.apply_clothing_channels(list("#996633"))
	suit.apply_clothing_channels(list("#336699"))
	TEST_ASSERT_EQUAL(suit.icon, first_icon, "recolouring again built on the recoloured copy")
	suit.apply_clothing_channels(list())
	TEST_ASSERT_EQUAL(suit.icon, original_icon, "clearing the colours did not restore the art")
	TEST_ASSERT(!(!isnull(STATE_PEEK(suit, item_misc, clothing_channel_colors))), "clearing left colours on the item")
	qdel(suit)

#undef DQ_CC_TEST_TYPE

/// In game, clothing is recoloured through its channels too: the Recolour op asks which channel, then its colour.
/datum/unit_test/dq_eg2/clothing_recolour_uses_channels
/datum/unit_test/dq_eg2/clothing_recolour_uses_channels/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/clothing/under/shiny/catsuit/poly/suit = allocate(/obj/item/clothing/under/shiny/catsuit/poly, run_loc_floor_bottom_left)
	var/obj/item/clothing/under/shiny/catsuit/plain = allocate(/obj/item/clothing/under/shiny/catsuit, run_loc_floor_bottom_left)
	TEST_ASSERT(/obj/item/clothing/proc/recolour_channels in suit.verbs, "a recolourable suit has no Recolour verb")
	TEST_ASSERT(!(/obj/item/clothing/proc/recolour_channels in plain.verbs), "an ordinary suit has the Recolour verb")
	TEST_ASSERT(!hascall(suit, "change_color"), "the plain colour verb still exists")
	H.put_in_active_hand(suit)
	test_menu(H, suit, "recolour_channels")
	TEST_ASSERT_NOTNULL(SSrequests.open_for(H), "recolouring asks nothing")
	test_answer(H, "Primary")
	test_answer(H, "#336699")
	TEST_ASSERT_EQUAL(suit.current_channel_colours()[1], "#336699", "the colour did not go on the first channel")
	TEST_ASSERT_NULL(suit.color, "the suit was tinted instead")
	TEST_ASSERT(suit.icon != initial(suit.icon), "the suit's sprite was not recoloured")
	// Its own base colour puts the channel back as drawn.
	test_menu(H, suit, "recolour_channels")
	test_answer(H, "Primary")
	test_answer(H, clothing_channel_bases(suit.type)[1])
	TEST_ASSERT(!(!isnull(STATE_PEEK(suit, item_misc, clothing_channel_colors))), "the base colour left a recolour behind")
	TEST_ASSERT_EQUAL(suit.icon, initial(suit.icon), "the sprite did not go back")
