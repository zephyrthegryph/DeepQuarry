/datum/asset/simple/tgui
	keep_local_name = TRUE
	var/is_tgui_shell = TRUE
	assets = list(
		"tgui.bundle.js" = file("tgui/public/tgui.bundle.js"),
		"tgui.bundle.css" = file("tgui/public/tgui.bundle.css"),
	)

/// Runtime TGUI shell for one immutable live-reload generation. Asset names are
/// generation-specific so registering a new shell never replaces an older one.
/datum/asset/simple/tgui_live_generation
	keep_local_name = TRUE
	var/is_tgui_shell = TRUE
	var/asset_directory
	var/generation_id

/datum/asset/simple/tgui_live_generation/New(directory, id)
	. = ..()
	asset_directory = directory
	generation_id = id
	assets = list(
		"tgui-[generation_id].bundle.js" = file("[asset_directory]/tgui.bundle.js"),
		"tgui-[generation_id].bundle.css" = file("[asset_directory]/tgui.bundle.css"),
	)
	register()

/datum/asset/simple/tgui_live_generation/register()
	if(!asset_directory)
		return
	return ..()

// Code-split interface chunks. The tgui main bundle no longer contains every
// interface — each interface is emitted by rspack as its own self-contained
// `*.chunk.js` (+ optional `*.chunk.css`) and loaded on demand. These are registered
// here with keep_local_name so browse_rsc serves them under the exact filenames the
// webpack runtime requests (publicPath is '' — see rspack.config.ts), and shipped per
// interface by tgui datum/proc/send_assets() using tgui-chunk-manifest.json.
//
// The asset list is built dynamically from the build output dir because chunk
// filenames are content-derived and change every build; flist() enumerates whatever
// the current build produced. Registered at boot via get_asset_datum() in SStgui.
/datum/asset/simple/namespaced/tgui_chunks
	keep_local_name = TRUE
	cross_round_cachable = TRUE
	var/asset_directory = "tgui/public"
	var/list/allowed_assets

/datum/asset/simple/namespaced/tgui_chunks/register()
	for(var/filename in flist("[asset_directory]/"))
		// match `*.chunk.js` (9 chars) and `*.chunk.css` (10 chars)
		if((allowed_assets && allowed_assets[filename]) || (!allowed_assets && (copytext(filename, -9) == ".chunk.js" || copytext(filename, -10) == ".chunk.css")))
			assets[filename] = file("[asset_directory]/[filename]")
	return ..()

/datum/asset/simple/namespaced/tgui_chunks/proc/reload_from_directory(directory, list/filenames)
	unregister()
	assets = list()
	asset_directory = directory
	allowed_assets = filenames
	register()

/datum/asset/simple/namespaced/tgui_chunks/proc/get_public_base_url()
	if(!length(assets))
		return null
	var/filename
	for(var/name in assets)
		filename = name
		break
	var/url = SSassets.transport.get_asset_url(filename, assets[filename])
	if(!url)
		return null
	return copytext(url, 1, length(url) - length(url_encode(filename)) + 1)

/// Chunk namespace pinned to one live TGUI generation. Numeric rspack chunk
/// names may repeat between builds; the namespaced asset hash keeps the complete
/// generations distinct and leaves old URLs valid for already-open windows.
/datum/asset/simple/namespaced/tgui_live_generation_chunks
	keep_local_name = TRUE
	cross_round_cachable = TRUE
	var/asset_directory
	var/list/allowed_assets

/datum/asset/simple/namespaced/tgui_live_generation_chunks/New(directory, list/filenames)
	. = ..()
	asset_directory = directory
	allowed_assets = filenames
	register()

/datum/asset/simple/namespaced/tgui_live_generation_chunks/register()
	if(!asset_directory)
		return
	for(var/filename in allowed_assets)
		assets[filename] = file("[asset_directory]/[filename]")
	return ..()

/datum/asset/simple/namespaced/tgui_live_generation_chunks/proc/get_public_base_url()
	if(!length(assets))
		return null
	var/filename
	for(var/name in assets)
		filename = name
		break
	var/url = SSassets.transport.get_asset_url(filename, assets[filename])
	if(!url)
		return null
	return copytext(url, 1, length(url) - length(url_encode(filename)) + 1)

/datum/asset/simple/namespaced/tgui_live_generation_chunks/proc/get_assets(list/filenames)
	var/list/result = list()
	for(var/filename in filenames)
		if(assets[filename])
			result[filename] = assets[filename]
	return result

/datum/asset/simple/tgui_panel
	keep_local_name = TRUE
	assets = list(
		"tgui-panel.bundle.js" = file("tgui/public/tgui-panel.bundle.js"),
		"tgui-panel.bundle.css" = file("tgui/public/tgui-panel.bundle.css"),
	)

// Let TGUI use all of our custom fonts
/datum/asset/simple/namespaced/tgui_extra_fonts
	assets = list(
		"Grand9K_Pixel.ttf" = file("interface/fonts/Grand9K_Pixel.ttf"),
		"Pixellari.ttf" = file("interface/fonts/Pixellari.ttf"),
		"TinyUnicode.ttf" = file("interface/fonts/TinyUnicode.ttf"),
		"VCR_OSD_Mono.ttf" = file("interface/fonts/VCR_OSD_Mono.ttf"),
	)

	parents = list(
		"fonts.css" = file("interface/fonts/fonts.css"),
	)
