// What the examine panels show for a thing: the handle the panel keeps names the thing again, and its icon is registered as a browser asset the page can name.

/datum/unit_test/dq_examine_icon_assets

/datum/unit_test/dq_examine_icon_assets/Run()
	var/turf/floor = test_floor()
	var/list/things = list(
		allocate(/obj/item/pen, floor),
		allocate(/mob/living/carbon/human, floor),
		allocate(/obj/machinery/light, floor),
		floor,
	)
	var/list/bad = list()
	for(var/atom/thing as anything in things)
		var/token = ref_token(thing)
		if(resolve_token(token) != thing)
			bad += "[thing.type]: the panel's handle [token] resolves to [resolve_token(token)]"
		var/url = icon2html(thing, list(src), sourceonly = TRUE) // a stand-in target: no client in a test world, and sending is off there
		var/datum/asset_cache_item/item = url ? SSassets.cached_asset(url_decode(url)) : null
		if(!url)
			bad += "[thing.type]: icon2html gave no source"
		else if(!item)
			bad += "[thing.type]: [url] is not a registered asset"
		else if(!item.resource || !length(item.resource))
			bad += "[thing.type]: [url] has an empty resource"
	TEST_ASSERT(!length(bad), "examine icons: [jointext(bad, "; ")]")
