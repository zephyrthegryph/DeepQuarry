// What opening a window costs the server: the first payload (ui_data and static data, built and JSON-encoded) for the PDA, a vendor and the
// APC, the way /datum/tgui/open() builds it. WINDOW_OPEN_COST lines are the measurement.

/datum/unit_test/dq_window_open_cost
/datum/unit_test/dq_window_open_cost/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/pda/pda = allocate(/obj/item/pda, test_floor())
	var/obj/machinery/vending/coffee/vendor = allocate(/obj/machinery/vending/coffee, get_step(test_floor(), EAST))
	var/obj/machinery/power/apc/apc = locate() in world
	measure(H, pda, "PDA")
	measure(H, vendor, "vendor")
	if(apc)
		measure(H, apc, "APC")
	else
		TEST_NOTICE(src, "WINDOW_OPEN_COST APC: none on the map")

/datum/unit_test/dq_window_open_cost/proc/measure(mob/user, datum/holder, label)
	var/n = 10
	var/list/data
	var/list/static_data
	var/started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		data = list()
		present_tgui_data(holder, user, data)
	var/data_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		static_data = holder.tgui_static_data(user)
	var/static_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	started = TICK_USAGE_REAL
	var/text
	for(var/i in 1 to n)
		text = json_encode(list("data" = data, "static_data" = static_data))
	var/json_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	TEST_NOTICE(src, "WINDOW_OPEN_COST [label]: ui_data [round(data_ms, 0.01)] ms ([length(json_encode(data))] bytes), static [round(static_ms, 0.01)] ms ([length(json_encode(static_data))] bytes), json [round(json_ms, 0.01)] ms, first payload [length(text)] bytes")

/// What a client downloads to see a vendor's products the first time: the sheet of every vendor's stock (before) against the vendor's own
/// product pictures (after: one small asset each, built once for the world).
/datum/unit_test/dq_window_open_vendor_pictures
/datum/unit_test/dq_window_open_vendor_pictures/Run()
	var/obj/machinery/vending/coffee/vendor = allocate(/obj/machinery/vending/coffee, test_floor())
	var/sheet_bytes = 0
	var/datum/asset/spritesheet_batched/vending/sheet = get_asset_datum(/datum/asset/spritesheet_batched/vending)
	for(var/size_id in sheet.sizes)
		sheet_bytes += length(file("[SPRITESHEET_DIR][sheet.name]_[size_id].png"))
	sheet_bytes += length(file("[SPRITESHEET_DIR]spritesheet_[sheet.name].css"))
	var/picture_bytes = 0
	var/products = 0
	var/started = TICK_USAGE_REAL
	for(var/datum/stored_item/vending_product/P as anything in vendor.product_records)
		if(!ispath(P.item_path, /atom))
			continue
		products++
		var/key = CACHED_KEY(vending_product_asset, "[P.item_path]", P.item_path)
		TEST_ASSERT(SSassets.cached_asset(key), "[P.item_path]'s picture is a registered asset")
		var/list/spec = vending_product_icon_spec(P.item_path)
		var/icon/picture = (spec && spec[4]) ? icon(spec[1], spec[2], SOUTH, 1) : icon('icons/turf/floors.dmi', "", SOUTH, 1)
		picture_bytes += round(length(icon2base64(picture)) * 3 / 4)
	var/first_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	TEST_ASSERT(products > 0, "the vendor has products")
	TEST_NOTICE(src, "WINDOW_OPEN_COST vendor pictures: before, the whole sheet [sheet_bytes] bytes on a client's first vendor; after, [products] pictures [picture_bytes] bytes (built in [round(first_ms, 0.1)] ms, the first time for the world)")

/// What a fresh client is sent on join, asset by asset (the stat panel, the chat panel and its fonts and emoji sheet, the tgui shell the pooled
/// windows load), and what it is no longer sent: the abilities sheet waits for an ability that draws from it. JOIN_ASSET_COST lines.
/datum/unit_test/dq_join_asset_cost
/datum/unit_test/dq_join_asset_cost/Run()
	var/total = 0
	var/files = 0
	for(var/asset_type in list(/datum/asset/simple/tgui_statpanel, /datum/asset/simple/tgui_panel, /datum/asset/simple/namespaced/fontawesome, /datum/asset/simple/namespaced/tgfont, /datum/asset/simple/tgui, /datum/asset/spritesheet_batched/chat))
		var/list/sizes = dq_asset_bytes(get_asset_datum(asset_type))
		total += sizes[1]
		files += sizes[2]
		TEST_NOTICE(src, "JOIN_ASSET_COST [asset_type]: [sizes[2]] files, [sizes[1]] bytes")
	TEST_NOTICE(src, "JOIN_ASSET_COST total on join: [files] files, [total] bytes")
	var/list/ability = dq_asset_bytes(get_asset_datum(/datum/asset/spritesheet_batched/ability_icons))
	TEST_NOTICE(src, "JOIN_ASSET_COST abilities sheet (was on join, now with the first ability that draws from it): [ability[2]] files, [ability[1]] bytes")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT(!ability_sheet_wanted(H), "a plain human has no ability that draws from the sheet, so it is not sent the sheet")

/// list(bytes, files) of an asset datum: a simple asset's files, or a sheet's pictures and stylesheet.
/datum/unit_test/dq_join_asset_cost/proc/dq_asset_bytes(datum/asset/A)
	var/bytes = 0
	var/files = 0
	if(istype(A, /datum/asset/simple))
		var/datum/asset/simple/S = A
		for(var/name in S.assets)
			var/datum/asset_cache_item/item = S.assets[name]
			files++
			bytes += istype(item) ? length(item.resource) : 0
	else if(istype(A, /datum/asset/spritesheet_batched))
		var/datum/asset/spritesheet_batched/B = A
		for(var/size_id in B.sizes)
			files++
			bytes += length(file("[SPRITESHEET_DIR][B.name]_[size_id].png"))
		files++
		bytes += length(file("[SPRITESHEET_DIR]spritesheet_[B.name].css"))
	return list(bytes, files)
