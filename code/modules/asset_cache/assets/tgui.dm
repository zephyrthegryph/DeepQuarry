/datum/asset/simple/tgui
	keep_local_name = TRUE
	assets = list(
		"tgui.bundle.js" = file("tgui/public/tgui.bundle.js"),
		"tgui.bundle.css" = file("tgui/public/tgui.bundle.css"),
	)

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
/datum/asset/simple/tgui_chunks
	keep_local_name = TRUE
	cross_round_cachable = TRUE

/datum/asset/simple/tgui_chunks/register()
	for(var/filename in flist("tgui/public/"))
		// match `*.chunk.js` (9 chars) and `*.chunk.css` (10 chars)
		if(copytext(filename, -9) == ".chunk.js" || copytext(filename, -10) == ".chunk.css")
			assets[filename] = file("tgui/public/[filename]")
	return ..()

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
