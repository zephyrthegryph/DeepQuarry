// Asynchronous character preview rendering (doc/rewrite/fixes.md Q4).
//
// update_character_previews used to call getFlatIcon once per direction,
// which blocked the server for ~350 ms on every preference edit. Now the
// mannequin's appearance tree is translated into an iconforge sprite
// description (cheap: vars reads, rust-g metadata lookups, and one file copy
// per runtime-generated icon), and rust-g composites it on a worker thread.
// A poller applies the result once it lands.
//
// The translation mirrors getFlatIcon(no_anim = TRUE) step for step, NOT
// get_flat_uni_icon: that proc differs from getFlatIcon in parent-colour
// handling, crop conditions, pixel_w/pixel_z and TOPDOWN layering, so it
// would change what the preview looks like. Like getFlatIcon, this ignores
// filters and vis_contents. Anything the translation can't reproduce
// exactly (a /icon datum as an icon, a non-DMI icon file, a hex-string or
// odd-length colour matrix) makes that one direction fall back to the
// synchronous getFlatIcon path, so it never renders differently.
//
// Final size scaling still happens in DM, on the PNG rust-g wrote, so the
// size slider uses BYOND's Scale() exactly as before.

/// Where iconforge writes preview sheets. Each file is deleted once read.
#define DQ_PREVIEW_JOB_DIR "data/dq_previews/"
/// Content-addressed copies of runtime-generated icons, so iconforge can read them.
#define DQ_PREVIEW_RUNTIME_ICON_DIR "tmp/dq_preview_icons/"
/// A job that hasn't finished by then is treated as failed (sync fallback).
#define DQ_PREVIEW_JOB_TIMEOUT (30 SECONDS)
/// The blank canvas getFlatIcon starts from.
#define DQ_PREVIEW_BLANK_ICON "icons/effects/effects.dmi"
#define DQ_PREVIEW_BLANK_STATE "nothing"

/datum/preferences
	/// Bumped for every preview render. Only the latest generation's result is applied.
	var/dq_preview_generation = 0
	/// Number of async preview renders whose poller hasn't finished yet.
	var/dq_preview_jobs_in_flight = 0
	/// Set after an async render failed: the next render uses getFlatIcon for every direction.
	var/dq_preview_force_sync = FALSE
	/// Why the most recent direction fell back to getFlatIcon, for debugging.
	var/dq_last_preview_fallback

/// rust-g won't create output directories, so make sure ours exist.
/proc/dq_preview_ensure_dirs()
	var/static/done = FALSE
	if(done)
		return
	rustg_file_write("", "[DQ_PREVIEW_JOB_DIR].keep")
	rustg_file_write("", "[DQ_PREVIEW_RUNTIME_ICON_DIR].keep")
	done = TRUE

/// Translates an appearance tree into an iconforge sprite, following getFlatIcon exactly.
/datum/dq_preview_flattener
	/// Set to a reason string when the appearance can't be expressed exactly.
	var/unsupported
	/// "\ref[runtime icon]" -> on-disk DMI copy, shared by every direction of one render.
	var/list/runtime_paths

/// A sprite object in the rust-g iconforge format. Always frame 1, like getFlatIcon(no_anim = TRUE).
/datum/dq_preview_flattener/proc/make_sprite(icon_key, icon_state, dir)
	return list("icon_file" = resolve_icon_dmi_path(icon_key), "icon_state" = icon_state, "dir" = dir, "frame" = 1, "transform" = list())

/datum/dq_preview_flattener/proc/blank()
	var/list/dims = get_icon_dimensions(DQ_PREVIEW_BLANK_ICON)
	return list(make_sprite(DQ_PREVIEW_BLANK_ICON, DQ_PREVIEW_BLANK_STATE, SOUTH), dims["width"], dims["height"])

/// Returns a DMI path string rust-g can read for an appearance's icon, or null (setting unsupported).
/datum/dq_preview_flattener/proc/icon_key_for(icon_ref)
	if(istype(icon_ref, /icon))
		unsupported = "/icon datum used as an appearance icon"
		return null
	var/icon_string = "[icon_ref]"
	if(isfile(icon_ref) && length(icon_string))
		if(!findtextEx(icon_string, ".dmi"))
			unsupported = "non-DMI icon file [icon_string]"
			return null
		return icon_string
	// Runtime-generated icon (a dyn.rsc cache reference). Copy it to disk under its hash.
	var/ref_key = "\ref[icon_ref]"
	if(LAZYACCESS(runtime_paths, ref_key))
		return LAZYACCESS(runtime_paths, ref_key)
	dq_preview_ensure_dirs()
	var/staging = "[DQ_PREVIEW_RUNTIME_ICON_DIR]staging-[rand(1, 999999)].dmi"
	if(!fcopy(icon_ref, staging))
		unsupported = "couldn't copy a runtime icon to disk"
		return null
	var/file_hash = rustg_hash_file(RUSTG_HASH_MD5, staging)
	var/path = "[DQ_PREVIEW_RUNTIME_ICON_DIR][file_hash].dmi"
	if(!rustg_file_exists(path))
		fcopy(staging, path)
	fdel(staging)
	LAZYSET(runtime_paths, ref_key, path)
	return path

/// Number of dirs an icon state has, from rust-g metadata. Null (and unsupported) if unknown.
/datum/dq_preview_flattener/proc/state_dir_count(icon_key, icon_state)
	var/list/metadata = icon_metadata(icon_key)
	if(islist(metadata))
		for(var/list/state_data as anything in metadata["states"])
			if(state_data["name"] == icon_state)
				return state_data["dirs"]
	unsupported = "no metadata for [icon_key]:[icon_state]"
	return null

/// Appends an appearance colour (string or matrix) to a sprite, as getFlatIcon's Blend/MapColors would.
/datum/dq_preview_flattener/proc/apply_color(list/sprite, color)
	var/list/transforms = sprite["transform"]
	if(!islist(color))
		transforms += list(list("type" = RUSTG_ICONFORGE_BLEND_COLOR, "color" = color, "blend_mode" = ICON_MULTIPLY))
		return
	var/list/matrix = color
	for(var/value in matrix)
		if(!isnum(value))
			unsupported = "non-numeric colour matrix"
			return
	var/list/m
	switch(length(matrix))
		if(9)
			m = list(matrix[1], matrix[2], matrix[3], 0, matrix[4], matrix[5], matrix[6], 0, matrix[7], matrix[8], matrix[9], 0, 0, 0, 0, 1, 0, 0, 0, 0)
		if(12)
			m = list(matrix[1], matrix[2], matrix[3], 0, matrix[4], matrix[5], matrix[6], 0, matrix[7], matrix[8], matrix[9], 0, 0, 0, 0, 1, matrix[10], matrix[11], matrix[12], 0)
		if(16)
			m = matrix.Copy() + list(0, 0, 0, 0)
		if(20)
			m = matrix.Copy()
		else
			unsupported = "colour matrix of length [length(matrix)]"
			return
	transforms += list(list(
		"type" = RUSTG_ICONFORGE_MAP_COLORS,
		"rr" = m[1], "rg" = m[2], "rb" = m[3], "ra" = m[4],
		"gr" = m[5], "gg" = m[6], "gb" = m[7], "ga" = m[8],
		"br" = m[9], "bg" = m[10], "bb" = m[11], "ba" = m[12],
		"ar" = m[13], "ag" = m[14], "ab" = m[15], "aa" = m[16],
		"r0" = m[17], "g0" = m[18], "b0" = m[19], "a0" = m[20],
	))

/datum/dq_preview_flattener/proc/apply_alpha(list/sprite, alpha)
	var/list/transforms = sprite["transform"]
	transforms += list(list("type" = RUSTG_ICONFORGE_BLEND_COLOR, "color" = rgb(255, 255, 255, alpha), "blend_mode" = ICON_MULTIPLY))

/**
 * Mirror of getFlatIcon(appearance, defdir, ..., no_anim = TRUE).
 * Returns list(sprite, width, height), or null when getFlatIcon would return null.
 * Check `unsupported` afterwards: when set, the result must not be used.
 */
/datum/dq_preview_flattener/proc/flatten(image/appearance, defdir, deficon, defstate, defblend, start = TRUE)
	// Same layer sort as getFlatIcon's PROCESS_OVERLAYS_OR_UNDERLAYS.
	#define DQ_SORT_LAYERS(process, base_layer) \
		for (var/i in 1 to process.len) { \
			var/image/current = process[i]; \
			if (!current) { \
				continue; \
			} \
			if (current.plane != FLOAT_PLANE && current.plane != appearance.plane) { \
				continue; \
			} \
			var/current_layer = current.layer; \
			if (current_layer < 0) { \
				if (current_layer <= -1000) { \
					return blank(); \
				} \
				current_layer = base_layer + appearance.layer + current_layer / 1000; \
			} \
			for (var/index_to_compare_to in 1 to layers.len) { \
				var/compare_to = layers[index_to_compare_to]; \
				if (current_layer < layers[compare_to]) { \
					layers.Insert(index_to_compare_to, current); \
					break; \
				} \
			} \
			layers[current] = current_layer; \
		}

	if(unsupported)
		return null
	if(!appearance || appearance.alpha <= 0)
		return blank()
	if(start)
		if(!defdir)
			defdir = appearance.dir
		if(!deficon)
			deficon = appearance.icon
		if(!defstate)
			defstate = appearance.icon_state
		if(!defblend)
			defblend = appearance.blend_mode

	var/curicon = appearance.icon || deficon
	var/curstate = appearance.icon_state || defstate
	var/curdir = (!appearance.dir || appearance.dir == SOUTH) ? defdir : appearance.dir

	var/render_icon = !!curicon
	var/icon_key
	if(render_icon)
		icon_key = icon_key_for(curicon)
		if(unsupported)
			return null
		if(!icon_exists(icon_key, curstate))
			if(icon_exists(icon_key, ""))
				curstate = ""
			else
				render_icon = FALSE

	var/base_icon_dir
	if(render_icon && curdir != SOUTH)
		var/dir_count = state_dir_count(icon_key, curstate)
		if(unsupported)
			return null
		if(dir_count == 1)
			base_icon_dir = SOUTH
	if(!base_icon_dir)
		base_icon_dir = curdir

	var/curblend = appearance.blend_mode || defblend

	if(length(appearance.overlays) || length(appearance.underlays))
		var/list/blank_result = blank()
		var/list/flat = blank_result[1]
		var/list/flat_transforms = flat["transform"]
		var/list/layers = list()
		var/image/copy
		if(render_icon)
			copy = image(icon = curicon, icon_state = curstate, layer = appearance.layer, dir = base_icon_dir)
			copy.alpha = appearance.alpha
			copy.blend_mode = curblend
			layers[copy] = appearance.layer

		DQ_SORT_LAYERS(appearance.underlays, 0)
		DQ_SORT_LAYERS(appearance.overlays, 1)

		var/flatX1 = 1
		var/flatX2 = blank_result[2]
		var/flatY1 = 1
		var/flatY2 = blank_result[3]

		for(var/image/layer_image as anything in layers)
			if(layer_image.alpha == 0)
				continue
			var/list/add
			if(layer_image == copy)
				curblend = BLEND_OVERLAY
				var/list/dims = get_icon_dimensions(icon_key)
				add = list(make_sprite(icon_key, curstate, base_icon_dir), dims["width"], dims["height"])
			else
				add = flatten(layer_image, curdir, curicon, curstate, curblend, FALSE)
			if(unsupported)
				return null
			if(!add)
				continue

			var/addX1 = min(flatX1, layer_image.pixel_x + 1)
			var/addX2 = max(flatX2, layer_image.pixel_x + add[2])
			var/addY1 = min(flatY1, layer_image.pixel_y + 1)
			var/addY2 = max(flatY2, layer_image.pixel_y + add[3])
			if(addX1 != flatX1 || addX2 != flatX2 || addY1 != flatY1 || addY2 != flatY2)
				flat_transforms += list(list(
					"type" = RUSTG_ICONFORGE_CROP,
					"x1" = addX1 - flatX1 + 1,
					"y1" = addY1 - flatY1 + 1,
					"x2" = addX2 - flatX1 + 1,
					"y2" = addY2 - flatY1 + 1,
				))
				flatX1 = addX1
				flatX2 = addX2
				flatY1 = addY1
				flatY2 = addY2

			flat_transforms += list(list(
				"type" = RUSTG_ICONFORGE_BLEND_ICON,
				"icon" = add[1],
				"blend_mode" = blendMode2iconMode(curblend),
				"x" = layer_image.pixel_x + 2 - flatX1,
				"y" = layer_image.pixel_y + 2 - flatY1,
			))

		if(appearance.color)
			apply_color(flat, appearance.color)
		if(appearance.alpha < 255)
			apply_alpha(flat, appearance.alpha)
		if(unsupported)
			return null
		return list(flat, flatX2 - flatX1 + 1, flatY2 - flatY1 + 1)

	if(render_icon)
		var/list/dims = get_icon_dimensions(icon_key)
		var/list/final_sprite = make_sprite(icon_key, curstate, base_icon_dir)
		if(appearance.alpha < 255)
			apply_alpha(final_sprite, appearance.alpha)
		if(appearance.color)
			apply_color(final_sprite, appearance.color)
		if(unsupported)
			return null
		return list(final_sprite, dims["width"], dims["height"])

	return null
	#undef DQ_SORT_LAYERS

/// Scales a flattened preview by the size slider (exactly as before Q4) and base-64 encodes it.
/proc/dq_preview_icon_to_b64(icon/flat, scale_x, scale_y)
	if(scale_x != 1 || scale_y != 1)
		flat.Scale(max(1, round(flat.Width() * scale_x)), max(1, round(flat.Height() * scale_y)))
	return icon2base64(flat)

/**
 * Starts a preview render. `sprites` (dir key -> iconforge sprite) is composited
 * by rust-g off-thread; `ready` (key -> base-64) holds parts already done
 * synchronously. Everything is applied together, and only if no newer render
 * started meanwhile. Never sleeps. Returns this render's generation.
 */
/datum/preferences/proc/dq_queue_preview_render(list/sprites, list/ready, scale_x = 1, scale_y = 1)
	SHOULD_NOT_SLEEP(TRUE)
	var/generation = ++dq_preview_generation
	if(!length(sprites))
		dq_apply_preview_result(generation, ready)
		return generation
	var/static/job_serial = 0
	dq_preview_ensure_dirs()
	var/list/jobs = list()
	for(var/dir_key in sprites)
		var/sheet_name = "preview_[++job_serial]_[dir_key]"
		var/job_id = rustg_iconforge_generate_async(DQ_PREVIEW_JOB_DIR, sheet_name, json_encode(list("preview" = sprites[dir_key])), FALSE, FALSE, TRUE)
		jobs[dir_key] = list(job_id, sheet_name)
	dq_preview_jobs_in_flight++
	INVOKE_ASYNC(src, PROC_REF(dq_poll_preview_jobs), generation, jobs, ready, scale_x, scale_y, !!client)
	return generation

/// Waits for a render's iconforge jobs, then applies them unless the render went stale.
/datum/preferences/proc/dq_poll_preview_jobs(generation, list/jobs, list/ready, scale_x, scale_y, had_client)
	var/list/outputs = list()
	var/deadline = world.time + DQ_PREVIEW_JOB_TIMEOUT
	while(length(outputs) < length(jobs) && world.time <= deadline)
		for(var/dir_key in jobs)
			if(!isnull(outputs[dir_key]))
				continue
			var/output = rustg_iconforge_check(jobs[dir_key][1])
			if(output != RUSTG_JOB_NO_RESULTS_YET)
				outputs[dir_key] = output
		if(length(outputs) < length(jobs))
			stoplag()
	dq_preview_jobs_in_flight--

	var/current = !QDELETED(src) && generation == dq_preview_generation && (!had_client || client)
	var/list/result = current ? (ready ? ready.Copy() : list()) : null
	var/failed = length(outputs) < length(jobs)
	for(var/dir_key in outputs)
		var/png_path = dq_preview_job_png(jobs[dir_key][2], outputs[dir_key])
		if(!png_path)
			failed = TRUE
			continue
		if(result && !failed)
			result[dir_key] = dq_preview_icon_to_b64(icon(file(png_path)), scale_x, scale_y)
		fdel(png_path)
	if(!current)
		return
	if(failed)
		// Don't show a half-rendered or wrong preview: redo it the old synchronous way.
		dq_last_preview_fallback = "iconforge job failed"
		dq_preview_force_sync = TRUE
		update_preview_icon()
		return
	dq_apply_preview_result(generation, result)

/// Path of the PNG a finished iconforge job wrote, or null if the job failed.
/datum/preferences/proc/dq_preview_job_png(sheet_name, output)
	if(output == RUSTG_JOB_ERROR || output == RUSTG_JOB_NO_SUCH_JOB || !findtext(output, "{", 1, 2))
		stack_trace("Character preview iconforge job failed: [output]")
		return null
	var/list/data = json_decode(output)
	if(length(data["error"]))
		stack_trace("Character preview iconforge job reported: [data["error"]]")
	var/list/sprite_data = data["sprites"]?["preview"]
	if(!sprite_data)
		return null
	var/png_path = "[DQ_PREVIEW_JOB_DIR][sheet_name]_[sprite_data["size_id"]].png"
	if(!rustg_file_exists(png_path))
		return null
	return png_path

/// Applies a finished render if it's still the latest one. Returns TRUE if applied.
/datum/preferences/proc/dq_apply_preview_result(generation, list/result)
	if(generation != dq_preview_generation)
		return FALSE
	LAZYINITLIST(character_preview_b64)
	for(var/key in result)
		character_preview_b64[key] = result[key]
	dq_schedule_data_push()
	return TRUE

#undef DQ_PREVIEW_JOB_DIR
#undef DQ_PREVIEW_RUNTIME_ICON_DIR
#undef DQ_PREVIEW_JOB_TIMEOUT
#undef DQ_PREVIEW_BLANK_ICON
#undef DQ_PREVIEW_BLANK_STATE
