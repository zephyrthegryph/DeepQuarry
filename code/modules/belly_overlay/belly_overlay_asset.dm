// Pre-built belly overlay assets.
//
// Each (DMI, icon_state) pair was rendered offline by
// tools/build_belly_apngs/build.py into either:
//   - a single-frame PNG (still icons), or
//   - an animated WebP (multi-frame icons; libwebp_anim).
//
// Naming convention: <safe-dmi-name>__<safe-state-name>.<png|webp>
// where safe-name is the source path with all non-alnum/[-._] chars
// replaced by "_", and ".dmi" stripped.
//
// Registration is lazy: we only call SSassets.transport.register_asset()
// the first time a belly state is needed, so DD's .rsc memory doesn't
// hold all 112 files (~24 MB) forever. Per-client asset sends ship only
// the URLs for layers actually in the current preview, instead of the
// whole bundle.

// (dmi, state) cache_key -> resolved URL (null if file doesn't exist).
GLOBAL_LIST_EMPTY(dq_belly_overlay_url_by_key)
// URL -> asset_name (so we can ship just the URLs in a layer set).
GLOBAL_LIST_EMPTY(dq_belly_overlay_name_by_url)
// asset_name -> ACI (so we don't re-register a file twice).
GLOBAL_LIST_EMPTY(dq_belly_overlay_aci_by_name)

#define DQ_BELLY_OVERLAY_DIR "icons/belly_overlays/"

/// Builds the asset filename for a (dmi_path, state_name, ext) lookup.
/// Mirrors the naming convention in tools/build_belly_apngs/build.py.
/proc/dq_belly_overlay_safe_filename(dmi_path, state_name, ext)
	var/safe_dmi = replacetext(replacetext(dmi_path, ".dmi", ""), "/", "_")
	safe_dmi = replacetext(replacetext(safe_dmi, " ", "_"), ".", "_")
	var/safe_state = replacetext(replacetext(state_name, "/", "_"), " ", "_")
	safe_state = replacetext(safe_state, ".", "_")
	return "[safe_dmi]__[safe_state].[ext]"

/// Registers a single file by name into the asset transport, if it isn't
/// already. Returns the registered name on success, null if the file
/// doesn't exist.
/proc/dq_register_belly_asset(asset_name)
	if(GLOB.dq_belly_overlay_aci_by_name[asset_name])
		return asset_name
	var/path = "[DQ_BELLY_OVERLAY_DIR][asset_name]"
	if(!fexists(path))
		return null
	var/datum/asset_cache_item/ACI = SSassets.transport.register_asset(asset_name, file(path))
	if(!istype(ACI))
		log_asset("dq_register_belly_asset: failed to register [asset_name]")
		return null
	ACI.keep_local_name = TRUE
	GLOB.dq_belly_overlay_aci_by_name[asset_name] = ACI
	return asset_name

/// Returns the asset URL for a (dmi, state) pair, lazily registering the
/// file on first use. Tries .webp first (animated), then .png (still).
/// Returns null if no file exists. Result is cached.
/proc/dq_get_belly_overlay_url(icon/dmi, state)
	if(!dmi || !state)
		return null
	var/dmi_path = "[dmi]"
	var/cache_key = "[dmi_path]::[state]"
	if(cache_key in GLOB.dq_belly_overlay_url_by_key)
		return GLOB.dq_belly_overlay_url_by_key[cache_key]
	var/url = null
	for(var/ext in list("webp", "png"))
		var/asset_name = dq_belly_overlay_safe_filename(dmi_path, state, ext)
		if(!dq_register_belly_asset(asset_name))
			continue
		url = SSassets.transport.get_asset_url(asset_name, GLOB.dq_belly_overlay_aci_by_name[asset_name])
		GLOB.dq_belly_overlay_name_by_url[url] = asset_name
		break
	GLOB.dq_belly_overlay_url_by_key[cache_key] = url
	return url

/// Ship the assets backing the given URL list to the client. Only the
/// files actually referenced in the current preview are sent. The
/// transport itself dedupes per-client (sent_assets set), so repeat
/// calls with the same names are cheap.
/proc/dq_send_belly_overlay_urls(client/C, list/urls)
	if(!istype(C) || !length(urls))
		return FALSE
	var/list/names = list()
	for(var/url in urls)
		var/asset_name = GLOB.dq_belly_overlay_name_by_url[url]
		if(asset_name)
			names += asset_name
	if(!length(names))
		return FALSE
	return SSassets.transport.send_assets(C, names)
