
/// Process asset cache client topic calls for `"asset_cache_confirm_arrival=[INT]"`
/client/proc/asset_cache_confirm_arrival(job_id)
	return session?.confirm_asset_arrival(job_id)


/// Process asset cache client topic calls for `"asset_cache_preload_data=[HTML+JSON_STRING]"`
/client/proc/asset_cache_preload_data(data)
	var/json = data
	var/list/preloaded_assets = json_decode(json)

	for (var/preloaded_asset in preloaded_assets)
		if (copytext(preloaded_asset, findlasttext(preloaded_asset, ".")+1) in list("js", "jsm", "htm", "html"))
			preloaded_assets -= preloaded_asset
			continue
	sent_assets |= preloaded_assets


/// Updates the client side stored json file used to keep track of what assets the client has between restarts/reconnects.
/// A json update is queued (om_after_realtime), so a burst of sends writes the file once.
/client/var/tmp/asset_json_update_queued = FALSE

/client/proc/asset_cache_update_json()
	asset_json_update_queued = FALSE
	if (ELAPSED_SINCE(src, connection_time, CLOCK_WORLD) < 10 SECONDS) //don't override the existing data file on a new connection
		return

	src << browse(json_encode(sent_assets), "file=asset_data.json&display=0")
