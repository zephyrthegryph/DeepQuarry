#define TO_HEX_DIGIT(n) ascii2text((n&15) + ((n&15)<10 ? 48 : 87))

/icon/proc/MakeLying()
	var/icon/I = new(src,dir=SOUTH)
	I.BecomeLying()
	return I

/icon/proc/BecomeLying()
	Turn(90)
	Shift(SOUTH,6)
	Shift(EAST,1)

// Multiply all alpha values by this float
/icon/proc/ChangeOpacity(opacity = 1.0)
	MapColors(1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,opacity, 0,0,0,0)

// Convert to grayscale
/icon/proc/GrayScale()
	MapColors(0.3,0.3,0.3, 0.59,0.59,0.59, 0.11,0.11,0.11, 0,0,0)

/icon/proc/ColorTone(tone)
	GrayScale()

	var/list/TONE = rgb2num(tone)
	var/gray = round(TONE[1]*0.3 + TONE[2]*0.59 + TONE[3]*0.11, 1)

	var/icon/upper = (255-gray) ? new(src) : null

	if(gray)
		MapColors(255/gray,0,0, 0,255/gray,0, 0,0,255/gray, 0,0,0)
		Blend(tone, ICON_MULTIPLY)
	else SetIntensity(0)
	if(255-gray)
		upper.Blend(rgb(gray,gray,gray), ICON_SUBTRACT)
		upper.MapColors((255-TONE[1])/(255-gray),0,0,0, 0,(255-TONE[2])/(255-gray),0,0, 0,0,(255-TONE[3])/(255-gray),0, 0,0,0,0, 0,0,0,1)
		Blend(upper, ICON_ADD)

// Take the minimum color of two icons; combine transparency as if blending with ICON_ADD
/icon/proc/MinColors(icon)
	var/icon/I = new(src)
	I.Opaque()
	I.Blend(icon, ICON_SUBTRACT)
	Blend(I, ICON_SUBTRACT)

// Take the maximum color of two icons; combine opacity as if blending with ICON_OR
/icon/proc/MaxColors(icon)
	var/icon/I
	if(isicon(icon))
		I = new(icon)
	else
		// solid color
		I = new(src)
		I.Blend("#000000", ICON_OVERLAY)
		I.SwapColor("#000000", null)
		I.Blend(icon, ICON_OVERLAY)
	var/icon/J = new(src)
	J.Opaque()
	I.Blend(J, ICON_SUBTRACT)
	Blend(I, ICON_OR)

// make this icon fully opaque--transparent pixels become black
/icon/proc/Opaque(background = "#000000")
	SwapColor(null, background)
	MapColors(1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,0, 0,0,0,1)

// Change a grayscale icon into a white icon where the original color becomes the alpha
// I.e., black -> transparent, gray -> translucent white, white -> solid white
/icon/proc/BecomeAlphaMask()
	SwapColor(null, "#000000ff")	// don't let transparent become gray
	MapColors(0,0,0,0.3, 0,0,0,0.59, 0,0,0,0.11, 0,0,0,0, 1,1,1,0)

/icon/proc/UseAlphaMask(mask)
	Opaque()
	AddAlphaMask(mask)

/icon/proc/AddAlphaMask(mask)
	var/icon/M = new(mask)
	M.Blend("#ffffff", ICON_SUBTRACT)
	// apply mask
	Blend(M, ICON_ADD)

/proc/BlendRGB(rgb1, rgb2, amount)
	var/list/RGB1 = ReadRGB(rgb1)
	var/list/RGB2 = ReadRGB(rgb2)

	// add missing alpha if needed
	if(!RGB1 || !RGB2) //Don't blend if we don't two! No use blending what we don't have!
		return
	if(RGB1.len < RGB2.len) RGB1 += 255
	else if(RGB2.len < RGB1.len) RGB2 += 255
	var/usealpha = RGB1.len > 3

	var/r = round(RGB1[1] + (RGB2[1] - RGB1[1]) * amount, 1)
	var/g = round(RGB1[2] + (RGB2[2] - RGB1[2]) * amount, 1)
	var/b = round(RGB1[3] + (RGB2[3] - RGB1[3]) * amount, 1)
	var/alpha = usealpha ? round(RGB1[4] + (RGB2[4] - RGB1[4]) * amount, 1) : null

	return isnull(alpha) ? rgb(r, g, b) : rgb(r, g, b, alpha)

// Ported from /tg/station
// Creates a single icon from a given /atom or /image.  Only the first argument is required.
// appearance_flags indicates whether appearance_flags should be respected (at the cost of about 10-20% perf)
/proc/getFlatIcon(image/appearance, defdir, deficon, defstate, defblend, start = TRUE, no_anim = FALSE, force_south = FALSE, appearance_flags = FALSE)
	READS_FROM() // sampled: a flat icon is a picture of the appearance it is handed at this moment, never a value that follows it
	// Loop through the underlays, then overlays, sorting them into the layers list
	#define PROCESS_OVERLAYS_OR_UNDERLAYS(flat, process, base_layer) \
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
					return flat; \
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

	var/static/icon/flat_template = icon('icons/effects/effects.dmi', "nothing")

	if(!appearance || appearance.alpha <= 0)
		return icon(flat_template)
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

	if(force_south)
		curdir = SOUTH

	var/render_icon = curicon

	if (render_icon)
		if(!icon_exists(curicon, curstate))
			if(icon_exists(curicon, ""))
				curstate = ""
			else
				render_icon = FALSE

	var/base_icon_dir //We'll use this to get the icon state to display if not null BUT NOT pass it to overlays as the dir we have

	//Try to remove/optimize this section ASAP, CPU hog.
	//Determines if there's directionals.
	if(render_icon && curdir != SOUTH)
		if(!icon_state_has_directions(curicon, curstate))
			base_icon_dir = SOUTH

	if(!base_icon_dir)
		base_icon_dir = curdir

	var/curblend = appearance.blend_mode || defblend

	if(appearance.overlays.len || appearance.underlays.len)
		var/icon/flat = icon(flat_template)
		// Layers will be a sorted list of icons/overlays, based on the order in which they are displayed
		var/list/layers = list()
		var/image/copy
		// Add the atom's icon itself, without pixel_x/y offsets.
		if(render_icon)
			copy = image(icon=curicon, icon_state=curstate, layer=appearance.layer, dir=base_icon_dir)
			copy.color = appearance.color
			copy.alpha = appearance.alpha
			copy.blend_mode = curblend
			layers[copy] = appearance.layer

		PROCESS_OVERLAYS_OR_UNDERLAYS(flat, appearance.underlays, 0)
		PROCESS_OVERLAYS_OR_UNDERLAYS(flat, appearance.overlays, 1)

		var/icon/add // Icon of overlay being added

		var/flatX1 = 1
		var/flatX2 = flat.Width()
		var/flatY1 = 1
		var/flatY2 = flat.Height()

		var/addX1 = 0
		var/addX2 = 0
		var/addY1 = 0
		var/addY2 = 0

		for(var/image/layer_image as anything in layers)
			if(layer_image.alpha == 0)
				continue

			// variables only relevant when accounting for appearance_flags:
			var/apply_color = TRUE
			var/apply_alpha = TRUE

			if(layer_image == copy) // 'layer_image' is an /image based on the object being flattened.
				curblend = BLEND_OVERLAY
				add = icon(layer_image.icon, layer_image.icon_state, base_icon_dir)
			else // 'I' is an appearance object.
				var/image/layer_as_image = image(layer_image)
				if(appearance_flags)
					if(layer_as_image.appearance_flags & RESET_COLOR)
						apply_color = FALSE
					if(layer_as_image.appearance_flags & RESET_ALPHA)
						apply_alpha = FALSE
				add = getFlatIcon(layer_as_image, curdir, curicon, curstate, curblend, FALSE, no_anim, force_south, appearance_flags)
			if(!add)
				continue

			// Find the new dimensions of the flat icon to fit the added overlay
			addX1 = min(flatX1, layer_image.pixel_x + 1)
			addX2 = max(flatX2, layer_image.pixel_x + add.Width())
			addY1 = min(flatY1, layer_image.pixel_y + 1)
			addY2 = max(flatY2, layer_image.pixel_y + add.Height())

			if (
				addX1 != flatX1 \
				|| addX2 != flatX2 \
				|| addY1 != flatY1 \
				|| addY2 != flatY2 \
			)
				// Resize the flattened icon so the new icon fits
				flat.Crop(
					addX1 - flatX1 + 1,
					addY1 - flatY1 + 1,
					addX2 - flatX1 + 1,
					addY2 - flatY1 + 1
				)

				flatX1 = addX1
				flatX2 = addX2
				flatY1 = addY1
				flatY2 = addY2

			if(appearance_flags)
				// apply parent's color/alpha to the added layers if the layer didn't opt
				if(apply_color && appearance.color)
					if(islist(appearance.color))
						add.MapColors(arglist(appearance.color))
					else
						add.Blend(appearance.color, ICON_MULTIPLY)

				if(apply_alpha && appearance.alpha < 255)
					add.Blend(rgb(255, 255, 255, appearance.alpha), ICON_MULTIPLY)

			// Blend the overlay into the flattened icon
			flat.Blend(add, blendMode2iconMode(curblend), layer_image.pixel_x + 2 - flatX1, layer_image.pixel_y + 2 - flatY1)

		if(!appearance_flags)
			// If we didn't apply parent colors individually per layer respecting appearance_flags, then do it just the one time now
			if(appearance.color)
				if(islist(appearance.color))
					flat.MapColors(arglist(appearance.color))
				else
					flat.Blend(appearance.color, ICON_MULTIPLY)

			if(appearance.alpha < 255)
				flat.Blend(rgb(255, 255, 255, appearance.alpha), ICON_MULTIPLY)

		if(no_anim)
			//Clean up repeated frames
			var/icon/cleaned = new /icon()
			cleaned.Insert(flat, "", SOUTH, 1, 0)
			return cleaned
		else
			return icon(flat, "", SOUTH)
	else if (render_icon) // There's no overlays.
		var/icon/final_icon = icon(icon(curicon, curstate, base_icon_dir), "", SOUTH, no_anim ? TRUE : null)

		if (appearance.alpha < 255)
			final_icon.Blend(rgb(255,255,255, appearance.alpha), ICON_MULTIPLY)

		if (appearance.color)
			if (islist(appearance.color))
				final_icon.MapColors(arglist(appearance.color))
			else
				final_icon.Blend(appearance.color, ICON_MULTIPLY)

		return final_icon

	#undef PROCESS_OVERLAYS_OR_UNDERLAYS

//getFlatIcon but generates an icon that can face ALL four directions. The only four.
/proc/getCompoundIcon(atom/A)
	var/icon/north = getFlatIcon(A,defdir=NORTH)
	var/icon/south = getFlatIcon(A,defdir=SOUTH)
	var/icon/east = getFlatIcon(A,defdir=EAST)
	var/icon/west = getFlatIcon(A,defdir=WEST)

	//Starts with a blank icon because of byond bugs.
	var/icon/full = icon('icons/effects/effects.dmi', "icon_state"="nothing")

	full.Insert(north,dir=NORTH)
	full.Insert(south,dir=SOUTH)
	full.Insert(east,dir=EAST)
	full.Insert(west,dir=WEST)
	spent(north)
	spent(south)
	spent(east)
	spent(west)
	return full

/proc/downloadImage(atom/A, dir, client/user)
	var/icon/this_icon = getFlatIcon(A,defdir=dir)

	user << ftp(this_icon,"[A.name].png")

/proc/getHologramIcon(icon/A, safety=1, no_color = FALSE)//If safety is on, a new icon is not created.
	var/icon/flat_icon = safety ? A : new(A)//Has to be a new icon to not constantly change the same icon.
	/* For AI Vore effects
	if(!no_color)
		flat_icon.ColorTone(rgb(125,180,225))//Let's make it bluish.
	flat_icon.ChangeOpacity(0.5)//Make it half transparent.
	*/ // Removal End
	var/icon/alpha_mask = new('icons/effects/effects.dmi', "scanline")//Scanline effect.
	flat_icon.AddAlphaMask(alpha_mask)//Finally, let's mix in a distortion effect.
	return flat_icon

//For photo camera.
/proc/build_composite_icon(atom/A)
	var/icon/composite = icon(A.icon, A.icon_state, A.dir, 1)
	for(var/image/I as anything in A.overlays)
		composite.Blend(icon(I.icon, I.icon_state, I.dir, 1), ICON_OVERLAY)
	return composite

GLOBAL_LIST_EMPTY(icon_state_lists)
/proc/set_cached_examine_icon(atom/A, icon/I, expiry = 20 MINUTES)
	if(!A)
		return
	sparse_set(A, examine_icon_snapshot, I)
	if(expiry && !after_pending(A, "examine_icon_expiry"))
		after(A, expiry, TYPE_PROC_REF(/atom, uncache_examine_icon), key = "examine_icon_expiry")

/proc/get_cached_examine_icon(atom/A)
	return sparse_get(A, examine_icon_snapshot)

/atom/proc/uncache_examine_icon()
	sparse_set(src, examine_icon_snapshot, null)

/proc/adjust_brightness(color, value)
	if (!color) return "#FFFFFF"
	if (!value) return color

	var/list/RGB = rgb2num(color)
	RGB[1] = CLAMP(RGB[1]+value,0,255)
	RGB[2] = CLAMP(RGB[2]+value,0,255)
	RGB[3] = CLAMP(RGB[3]+value,0,255)
	return rgb(RGB[1],RGB[2],RGB[3])

/proc/sort_atoms_by_layer(list/atoms)
	// Comb sort icons based on levels
	var/list/result = atoms.Copy()
	var/gap = result.len
	var/swapped = 1
	while (gap > 1 || swapped)
		swapped = 0
		if(gap > 1)
			gap = round(gap / 1.3) // 1.3 is the emperic comb sort coefficient
		if(gap < 1)
			gap = 1
		for(var/i = 1; gap + i <= result.len; i++)
			var/atom/l = result[i]		//Fucking hate
			var/atom/r = result[gap+i]	//how lists work here
			if(l.layer > r.layer)		//no "result[i].layer" for me
				result.Swap(i, gap + i)
				swapped = 1
	return result

/proc/gen_hud_image(file, person, state, plane)
	var/image/img = image(file, person, state)
	img.plane = plane //Thanks Byond.
	img.layer = MOB_LAYER-0.2
	img.appearance_flags = APPEARANCE_UI
	return img

/// generates a filename for a given asset.
/// like generate_asset_name(), except returns the rsc reference and the rsc file hash as well as the asset name (sans extension)
/// used so that certain asset files dont have to be hashed twice
/proc/generate_and_hash_rsc_file(file, dmi_file_path)
	var/rsc_ref = fcopy_rsc(file)
	var/hash
	//if we have a valid dmi file path we can trust md5'ing the rsc file because we know it doesnt have the bug described in http://www.byond.com/forum/post/2611357
	if(dmi_file_path)
		hash = md5(rsc_ref)
	else //otherwise, we need to do the expensive fcopy() workaround
		hash = md5asfile(rsc_ref)

	return list(rsc_ref, hash, "asset.[hash]")

/// Gets a dummy savefile for usage in icon generation.
/// The ten scratch files are made once and kept open: a caller writes its own entry, which replaces what the last caller left there, so
/// nothing is deleted or created per call (a join makes three icon2base64() calls, and a delete and create on disk cost several ms each).
/proc/get_dummy_savefile(from_failure = FALSE)
	var/static/slot = 0 // one of ten rotating scratch files, not an entity id
	var/static/list/scratch_files // built on first use: the first caller can run before static initialisers
	if(!scratch_files)
		scratch_files = new /list(10)
	slot = (slot % 10) + 1
	var/savefile/scratch = scratch_files[slot]
	if(scratch)
		return scratch
	// dq_scratch_tag makes this path unique per DreamDaemon process: two
	// worlds that happen to share a working directory (a sharded dm-test run
	// boots N worlds in the same worktree) would otherwise round-robin
	// through the SAME tmp/dummy-save-N.sav paths and race each other for
	// the file (observed as "cannot open savefile buffer dummy for write").
	var/savefile_path = "tmp/dummy-save-[GLOB.dq_scratch_tag]-[slot].sav"
	try
		if(fexists(savefile_path))
			fdel(savefile_path)
		scratch = new /savefile(savefile_path)
		scratch_files[slot] = scratch
		return scratch
	catch(var/exception/error)
		// if we failed to create a dummy once, try again; maybe someone slept somewhere they shouldnt have
		if(from_failure) // this *is* the retry, something fucked up
			throw EXCEPTION("get_dummy_savefile failed to create a dummy savefile: '[error]'")
		return get_dummy_savefile(from_failure = TRUE)

/// Generate a filename for this asset
/// The same asset will always lead to the same asset name
/// (Generated names do not include file extention.)
/proc/generate_asset_name(file)
	return "asset.[md5(fcopy_rsc(file))]"

/**
 * Converts an icon to base64. Operates by putting the icon in the iconCache savefile,
 * exporting it as text, and then parsing the base64 from that.
 * (This relies on byond automatically storing icons in savefiles as base64)
 */
/proc/icon2base64(icon/icon)
	if (!isicon(icon))
		return FALSE
	var/savefile/dummySave = get_dummy_savefile()
	WRITE_FILE(dummySave["dummy"], icon)
	var/iconData = dummySave.ExportText("dummy")
	var/list/partial = splittext(iconData, "{")
	return replacetext(copytext_char(partial[2], 3, -5), "\n", "") //if cleanup fails we want to still return the correct base64

///given a text string, returns whether it is a valid dmi icons folder path
/proc/is_valid_dmi_file(icon_path)
	if(!istext(icon_path) || !length(icon_path))
		return FALSE

	var/is_in_icon_folder = findtextEx(icon_path, "icons/")
	var/is_dmi_file = findtextEx(icon_path, ".dmi")

	if(is_in_icon_folder && is_dmi_file)
		return TRUE
	return FALSE

/// given an icon object, dmi file path, or atom/image/mutable_appearance, attempts to find and return an associated dmi file path.
/// a weird quirk about dm is that /icon objects represent both compile-time or dynamic icons in the rsc,
/// but stringifying rsc references returns a dmi file path
/// ONLY if that icon represents a completely unchanged dmi file from when the game was compiled.
/// so if the given object is associated with an icon that was in the rsc when the game was compiled, this returns a path. otherwise it returns ""
/proc/get_icon_dmi_path(icon/icon)
	/// the dmi file path we attempt to return if the given object argument is associated with a stringifiable icon
	/// if successful, this looks like "icons/path/to/dmi_file.dmi"
	var/icon_path = ""

	if(isatom(icon) || istype(icon, /image) || istype(icon, /mutable_appearance))
		var/atom/atom_icon = icon
		icon = atom_icon.icon
		//atom icons compiled in from 'icons/path/to/dmi_file.dmi' are weird and not really icon objects that you generate with icon().
		//if theyre unchanged dmi's then they're stringifiable to "icons/path/to/dmi_file.dmi"

	if(isicon(icon) && isfile(icon))
		//icons compiled in from 'icons/path/to/dmi_file.dmi' at compile time are weird and arent really /icon objects,
		///but they pass both isicon() and isfile() checks. theyre the easiest case since stringifying them gives us the path we want
		var/locate_icon_string = "[locate(REF(icon))]"

		icon_path = locate_icon_string

	else if(isicon(icon) && "[icon]" == "/icon")
		// icon objects generated from icon() at runtime are icons, but they ARENT files themselves, they represent icon files.
		// if the files they represent are compile time dmi files in the rsc, then
		// the rsc reference returned by fcopy_rsc() will be stringifiable to "icons/path/to/dmi_file.dmi"
		var/rsc_ref = fcopy_rsc(icon)

		var/icon_path_string = "[locate(REF(rsc_ref))]"

		icon_path = icon_path_string

	else if(istext(icon))
		var/rsc_ref = fcopy_rsc(icon)
		//if its the text path of an existing dmi file, the rsc reference returned by fcopy_rsc() will be stringifiable to a dmi path

		var/rsc_ref_string = "[locate(REF(rsc_ref))]"

		icon_path = rsc_ref_string

	if(is_valid_dmi_file(icon_path))
		return icon_path

	return FALSE

// DQ icon pipeline caches (shared caches, doc/rewrite/caching.md). Every one is keyed by the source path text and never invalidated: a
// DMI file does not change while the world runs, so a hit is the builder's value for that path.
DECLARE_SHARED_CACHE(icon_resolved_path, GLOBAL_PROC_REF(build_resolved_icon_path), SC_NEVER)
DECLARE_SHARED_CACHE(icon_dmi_metadata, GLOBAL_PROC_REF(build_icon_metadata), SC_NEVER)
DECLARE_SHARED_CACHE(icon_state_names, GLOBAL_PROC_REF(build_icon_state_names), SC_NEVER)
DECLARE_SHARED_CACHE(icon_state_set, GLOBAL_PROC_REF(build_icon_state_set), SC_NEVER)
DECLARE_SHARED_CACHE(icon_state_dir_counts, GLOBAL_PROC_REF(build_icon_state_dir_counts), SC_NEVER)
DECLARE_SHARED_CACHE(icon_size, GLOBAL_PROC_REF(build_icon_size), SC_NEVER)
DECLARE_SHARED_CACHE(icon_size_pure, GLOBAL_PROC_REF(build_icon_size_pure), SC_NEVER)

/// Resolves a DMI source path to a file rust-g can read.
///
/// DQ Architecture-A: editable .dmi files are repacked into icons/gen/ at build
/// time and do NOT exist on disk at their original source path. rust-g (and
/// iconforge) read the real filesystem rather than the .rsc, so a source-path
/// read silently fails for repacked icons. This proc tries the source path first;
/// if rust-g reports it absent, it retries against the generated copy under
/// icons/gen/. The result is the `icon_resolved_path` shared cache, so repeated
/// calls (e.g. per-frame iconforge lookups) cost only a list lookup.
///
/// Returns the on-disk path rust-g can use, or the original path unchanged when
/// neither location exists (callers may then fail gracefully or crash on their own).
/proc/resolve_icon_dmi_path(path)
	return CACHED(icon_resolved_path, "[path]")

/proc/build_resolved_icon_path(path)
	var/out = path
	if(!rustg_file_exists(path))
		var/gen_path = "icons/gen/[path]"
		if(rustg_file_exists(gen_path))
			out = gen_path
	return out

/proc/build_icon_metadata(file_string)
	// Resolve the on-disk path; handles icons/gen/ fallback for repacked DMIs.
	var/resolved = resolve_icon_dmi_path(file_string)
	var/list/metadata_result = rustg_dmi_read_metadata(resolved)
	if(!islist(metadata_result) || !length(metadata_result))
		CRASH("Error while reading DMI metadata for path '[file_string]' (resolved: '[resolved]'): [metadata_result]")
	return metadata_result

/// Checks whether a given icon state exists in a given icon file. If `file` and `state` both exist,
/// this will return `TRUE` - otherwise, it will return `FALSE`.
///
/// If you want a stack trace to be output when the given state/file doesn't exist, use
/// `/proc/icon_exists_or_scream()`.
/proc/icon_exists(file, state)
	if(isnull(file) || isnull(state))
		return FALSE //This is common enough that it shouldn't panic, imo.
	var/list/known = icon_state_set_of(file)
	return !isnull(known[state])

/// Cached, rustg-based alternative to icon_states(). The list is shared: copy it before changing it.
/proc/icon_states_fast(file)
	RETURN_TYPE(/list)
	if(isnull(file))
		return null
	if(!icon_has_stable_key(file))
		// A runtime /icon or dynamic rsc file has no stable identity to key a cache by.
		return icon_states(file)
	return CACHED_KEY(icon_state_names, "[file]", file)

/// Whether the state `state` of `file` has more than its south frame (north, east or west). A file's DMI metadata says how many directions
/// each state has; a runtime icon has none, so it is asked the slow way: whether the state exists when read for each of those directions.
/proc/icon_state_has_directions(file, state)
	if(icon_has_stable_key(file))
		var/list/dir_counts = CACHED_KEY(icon_state_dir_counts, "[file]", file)
		var/dirs = dir_counts?[state]
		if(!isnull(dirs))
			return dirs != 1
	return length(icon_states_fast(icon(file, state, NORTH))) || length(icon_states_fast(icon(file, state, EAST))) || length(icon_states_fast(icon(file, state, WEST)))

/// Whether an icon argument names a file on disk, so its text form identifies it. A runtime /icon and a dynamic rsc
/// file (a generated body icon) stringify to nothing or to something shared, so keying a cache by that text would hand
/// one icon the state list of another.
/proc/icon_has_stable_key(file)
	return istext(file) || (isfile(file) && length("[file]") > 0)

/// The states of an icon file as a lookup (state name -> TRUE). Shared: never written.
/proc/icon_state_set_of(file)
	if(!icon_has_stable_key(file))
		return build_icon_state_set(file)
	return CACHED_KEY(icon_state_set, "[file]", file)

/proc/build_icon_state_set(file)
	. = list()
	for(var/istate in icon_states_fast(file))
		.[istate] = TRUE

/**
 * Returns the size of the sprite in tiles.
 * Takes the icon size and divides it by the world icon size (default 32).
 * This gives the size of the sprite in tiles.
 *
 * @return size of the sprite in tiles
 */
/proc/get_size_in_tiles(obj/target)
	var/icon/size_check = icon(target.icon, target.icon_state)
	var/size = size_check.Width() / ICON_SIZE_X

	return size

/// Returns a list containing the width and height of an icon file, without using rustg for pure function calls
/proc/get_icon_dimensions_pure(icon_path)
	// Dynamic icons are an unbounded concept cache identity wise (see get_icon_dimensions()): never cached.
	if (!isfile(icon_path) || !length("[icon_path]"))
		return build_icon_size_pure(icon_path)
	return CACHED_KEY(icon_size_pure, "[icon_path]", icon_path)

/proc/build_icon_size_pure(icon_path)
	var/icon/my_icon = icon(icon_path)
	return list("width" = my_icon.Width(), "height" = my_icon.Height())

/proc/AverageColor(icon/I, accurate = 0, ignoreGreyscale = 0)
//Accurate: Use more accurate color averaging, usually has better results and prevents muddied or overly dark colors. Mad thanks to wwjnc.
//ignoreGreyscale: Excempts greyscale colors from the color list, useful for filtering outlines or plate overlays.
	var/list/colors = ListColors(I, ignoreGreyscale)
	if(!colors.len)
		return null

	var/list/colorsum = list(0, 0, 0) //Holds the sum of the RGB values to calculate the average
	var/list/RGB = list(0, 0, 0) //Temp list for each color
	var/total = colors.len

	var/final_average
	if (accurate) //keeping it legible
		for(var/i = 1 to total)
			RGB = rgb2num(colors[i])
			colorsum[1] += RGB[1]*RGB[1]
			colorsum[2] += RGB[2]*RGB[2]
			colorsum[3] += RGB[3]*RGB[3]
		final_average = rgb(sqrt(colorsum[1]/total), sqrt(colorsum[2]/total), sqrt(colorsum[3]/total))
	else
		for(var/i = 1 to total)
			RGB = rgb2num(colors[i])
			colorsum[1] += RGB[1]
			colorsum[2] += RGB[2]
			colorsum[3] += RGB[3]
		final_average = rgb(colorsum[1]/total, colorsum[2]/total, colorsum[3]/total)
	return final_average

/proc/ListColors(icon/I, ignoreGreyscale = 0)
	var/list/colors = list()
	for(var/x_pixel = 1 to I.Width())
		for(var/y_pixel = 1 to I.Height())
			var/this_color = I.GetPixel(x_pixel, y_pixel)
			if(this_color)
				if (ignoreGreyscale && rgb2num(this_color, COLORSPACE_HSV)[2] == 0) //If saturation is 0, must be greyscale
					continue
				colors.Add(this_color)
	return colors

/proc/empty_Y_space(icon/I) //Returns the amount of lines containing only transparent pixels in an icon, starting from the bottom
	for(var/y_pixel = 1 to I.Height())
		for(var/x_pixel = 1 to I.Width())
			if (I.GetPixel(x_pixel, y_pixel))
				return y_pixel - 1
	return null

/proc/ReadRGB(rgb)
	if(!rgb)
		return

	// interpret the HSV or HSVA value
	var/i=1,start=1
	if(text2ascii(rgb) == 35) ++start // skip opening #
	var/ch,which=0,r=0,g=0,b=0,alpha=0,usealpha
	var/digits=0
	for(i=start, i<=length(rgb), ++i)
		ch = text2ascii(rgb, i)
		if(ch < 48 || (ch > 57 && ch < 65) || (ch > 70 && ch < 97) || ch > 102)
			break
		++digits
		if(digits == 8)
			break

	var/single = digits < 6
	if(digits != 3 && digits != 4 && digits != 6 && digits != 8)
		return
	if(digits == 4 || digits == 8)
		usealpha = 1
	for(i=start, digits>0, ++i)
		ch = text2ascii(rgb, i)
		if(ch >= 48 && ch <= 57)
			ch -= 48
		else if(ch >= 65 && ch <= 70)
			ch -= 55
		else if(ch >= 97 && ch <= 102)
			ch -= 87
		else
			break
		--digits
		switch(which)
			if(0)
				r = (r << 4) | ch
				if(single)
					r |= r << 4
					++which
				else if(!(digits & 1))
					++which
			if(1)
				g = (g << 4) | ch
				if(single)
					g |= g << 4
					++which
				else if(!(digits & 1))
					++which
			if(2)
				b = (b << 4) | ch
				if(single)
					b |= b << 4
					++which
				else if(!(digits & 1))
					++which
			if(3)
				alpha = (alpha << 4) | ch
				if(single)
					alpha |= alpha << 4

	. = list(r, g, b)
	if(usealpha)
		. += alpha

/// Save file as an external file then md5 it.
/// Used because md5ing files stored in the rsc sometimes gives incorrect md5 results.
/// https://www.byond.com/forum/post/2611357
/proc/md5asfile(file)
	var/static/notch = 0
	var/filename = "tmp/md5asfile.[world.realtime].[world.timeofday].[world.time].[world.tick_usage].[notch]"
	notch = WRAP(notch+1, 0, 2**15)
	fcopy(file, filename)
	. = md5filepath(filename)
	fdel(filename)

/// Returns the md5 of a file at a given path.
/proc/md5filepath(path)
	. = md5(file(path))
