// The content half of code/host/helpers/icons.dm: what names content, so the layer the engine calls cannot hold it.

/**
* Animate a 'halo' around an object.
*
* This proc is not exactly cheap. You'd be well advised to set up many-loops rather than call this super-often. getCompoundIcon is
* mostly to blame for this. If Byond ever implements a way to get something's icon more 'gently' than this, do that instead.
*
* @param A This is the atom to put the halo on
* @param simple_icons If set to TRUE, will just perform a very basic icon and icon_state steal. DO USE when possible.
* @param color This is the color for the halo
* @param anim_duration This decides how fast (or slow) the animation plays
* @param offset Mysterious variable that determines size of the halo's gap from icon
* @param loops How many times the animation loops
* @param grow_to Relative to the size of the icon, how big the halo grows while fading (don't use negatives for inward halos, use < 1)
* @param pixel_scale If you'd like the halo to use pixel scale or the default 'fuzzy' scale
*/
/proc/animate_aura(atom/A, simple_icons, color = "#00FF22", anim_duration = 5, offset = 1, loops = 1, grow_to = 2, pixel_scale = FALSE)
	ASSERT(A)

	//Take a guess at this, if they didn't set it
	if(isnull(simple_icons))
		if(ismob(A))
			simple_icons = FALSE
		else
			simple_icons = TRUE

	//Get their icon
	var/icon/hole

	if(simple_icons)
		hole = icon(A.icon, A.icon_state)
	else
		hole = getCompoundIcon(A)

	hole.MapColors(0,0,0, 0,0,0, 0,0,0, 1,1,1) //White.

	//Make a bigger version
	var/icon/grower = new(hole)
	var/orig_width = grower.Width()
	var/orig_height = grower.Height()
	var/end_width = orig_width+(offset*2)
	var/end_height = orig_height+(offset*2)
	var/half_diff_width = (end_width-orig_width)*0.5
	var/half_diff_height = (end_height-orig_height)*0.5

	//Make icon black
	grower.SwapColor("#FFFFFF","#000000") //Black.

	//Scale both icons big so we don't have to deal with low-pixel garbage issues
	grower.Scale(orig_width*10,orig_height*10)
	hole.Scale(orig_width*9,orig_height*9)

	//Blend the hole in
	grower.Blend(hole,ICON_OVERLAY, x = ((orig_width*10-orig_width*9)*0.5)+1, y = ((orig_height*10-orig_height*9)*0.5)+1)

	//Swap white to zero alpha
	grower.SwapColor("#FFFFFF","#00000000")

	//Color it
	grower.SwapColor("#000000",color)

	//Scale it to final height
	grower.Scale(end_width,end_height)

	//Flick it onto them
	var/image/img = image(grower,A)
	if(pixel_scale)
		img.appearance_flags |= PIXEL_SCALE
	img.pixel_x = half_diff_width*-1
	img.pixel_y = half_diff_height*-1
	flick_overlay_view(img, A, anim_duration*loops, TRUE)

	//Animate it growing
	animate(img, alpha = 0, transform = matrix()*grow_to, time = anim_duration, loop = loops)

/**
 * generate an asset for the given icon or the icon of the given appearance for [thing], and send it to any clients in target.
 * Arguments:
 * * thing - either a /icon object, or an object that has an appearance (atom, image, mutable_appearance).
 * * target - either a reference to or a list of references to /client's or mobs with clients
 * * icon_state - string to force a particular icon_state for the icon to be used
 * * dir - dir number to force a particular direction for the icon to be used
 * * frame - what frame of the icon_state's animation for the icon being used
 * * moving - whether or not to use a moving state for the given icon
 * * sourceonly - if TRUE, only generate the asset and send back the asset url, instead of tags that display the icon to players
 * * extra_clases - string of extra css classes to use when returning the icon string
 */
/proc/icon2html(atom/thing, client/target, icon_state, dir = SOUTH, frame = 1, moving = FALSE, sourceonly = FALSE, extra_classes = null)
	if (!thing)
		return

	var/key
	var/icon/icon2collapse = thing

	if (!target)
		return
	if (target == world)
		target = GLOB.clients

	var/list/targets
	if (!islist(target))
		targets = list(target)
	else
		targets = target
	if(!length(targets))
		return

	//check if the given object is associated with a dmi file in the icons folder. if it is then we dont need to do a lot of work
	//for asset generation to get around byond limitations
	var/icon_path = get_icon_dmi_path(thing)

	if (!isicon(icon2collapse))
		if (isfile(thing)) //special snowflake
			var/name = SANITIZE_FILENAME("[generate_asset_name(thing)].png")
			if (!SSassets.cached_asset(name))
				SSassets.register_asset(name, thing)
			for (var/thing2 in targets)
				SSassets.send_assets(thing2, name)
			if(sourceonly)
				return SSassets.get_asset_url(name)
			return "<img class='[extra_classes] icon icon-misc' src='[SSassets.get_asset_url(name)]'>"

		//its either an atom, image, or mutable_appearance, we want its icon var
		icon2collapse = thing.icon

		if (isnull(icon_state))
			icon_state = thing.icon_state
			//Despite casting to atom, this code path supports mutable appearances, so let's be nice to them
			//if(isnull(icon_state) || (isatom(thing) && thing.flags_1 & HTML_USE_INITAL_ICON_1))
			if(isnull(icon_state) && isatom(thing))
				icon_state = initial(thing.icon_state)
				if (isnull(dir))
					dir = initial(thing.dir)

		if (isnull(dir))
			dir = thing.dir

		if (ishuman(thing)) // Shitty workaround for a BYOND issue.
			var/icon/temp = icon2collapse
			icon2collapse = icon()
			icon2collapse.Insert(temp, dir = SOUTH)
			dir = SOUTH
	else
		if (isnull(dir))
			dir = SOUTH
		if (isnull(icon_state))
			icon_state = ""

	icon2collapse = icon(icon2collapse, icon_state, dir, frame, moving)

	var/list/name_and_ref = generate_and_hash_rsc_file(icon2collapse, icon_path)//pretend that tuples exist

	var/rsc_ref = name_and_ref[1] //weird object thats not even readable to the debugger, represents a reference to the icons rsc entry
	var/file_hash = name_and_ref[2]
	key = "[name_and_ref[3]].png"

	if(!SSassets.cached_asset(key))
		SSassets.register_asset(key, rsc_ref, file_hash, icon_path)
	for (var/client_target in targets)
		SSassets.send_assets(client_target, key)
	if(sourceonly)
		return SSassets.get_asset_url(key)
	return "<img class='[extra_classes] icon icon-[icon_state]' src='[SSassets.get_asset_url(key)]'>"

/proc/icon2base64html(target, custom_classes = "")
	if (!target)
		return
	var/static/list/bicon_cache = list() // ALLOW(cache): hot icon2html path, keys include refs of runtime icons
	if (isicon(target))
		var/icon/target_icon = target
		var/icon_base64 = icon2base64(target_icon)

		if (target_icon.Height() > world.icon_size || target_icon.Width() > world.icon_size)
			var/icon_md5 = md5(icon_base64)
			icon_base64 = bicon_cache[icon_md5]
			if (!icon_base64) // Doesn't exist yet, make it.
				bicon_cache[icon_md5] = icon_base64 = icon2base64(target_icon)


		return "<img class='icon icon-misc [custom_classes]' src='data:image/png;base64,[icon_base64]'>"

	// Either an atom or somebody fucked up and is gonna get a runtime, which I'm fine with.
	var/atom/target_atom = target
	var/key = "[istype(target_atom.icon, /icon) ? "[REF(target_atom.icon)]" : target_atom.icon]:[target_atom.icon_state]"


	if (!bicon_cache[key]) // Doesn't exist, make it.
		var/icon/target_icon = icon(target_atom.icon, target_atom.icon_state, SOUTH, 1)
		if(ishuman(target)) // Shitty workaround for a BYOND issue.
			var/icon/temp = target_icon
			target_icon = icon()
			target_icon.Insert(temp, dir = SOUTH)

		bicon_cache[key] = icon2base64(target_icon)

	return "<img class='icon icon-[target_atom.icon_state] [custom_classes]' src='data:image/png;base64,[bicon_cache[key]]'>"

/// Returns rustg-parsed metadata for an icon, universal icon, or DMI file, using cached values where possible.
/// Returns null if the argument is not a filepath or icon backed by a valid DMI file.
/// If the file does not exist at its source path, retries against icons/gen/ via resolve_icon_dmi_path().
/// Crashes with a stack trace if the file cannot be found at either location.
/proc/icon_metadata(file)
	if(istype(file, /datum/universal_icon))
		var/datum/universal_icon/u_icon = file
		file = u_icon.icon_file
	var/file_string = "[file]"
	if(!istext(file) && !(isfile(file) && length(file_string)) || findtext(file_string, ".png"))
		return null
	return CACHED(icon_dmi_metadata, file_string)

/// Returns a list containing the width and height of an icon file. Shared for files: never written.
/proc/get_icon_dimensions(icon_path)
	if(istype(icon_path, /datum/universal_icon))
		var/datum/universal_icon/u_icon = icon_path
		icon_path = u_icon.icon_file
	// Icons can be a real file(), a rsc backed file(), a dynamic rsc (dyn.rsc) reference (known as a cache reference in byond docs), or an /icon which is pointing to one of those.
	// Runtime generated dynamic icons are an unbounded concept cache identity wise, the same icon can exist millions of ways and holding them in a list as a key can lead to unbounded memory usage if called often by consumers.
	// Check distinctly that this is something that has this unspecified concept, and thus that we should not cache.
	if (!istext(icon_path) && (!isfile(icon_path) || !length("[icon_path]")))
		return build_icon_size_pure(icon_path)
	return CACHED_KEY(icon_size, "[icon_path]", icon_path)
//Costlier version of icon2html() that uses getFlatIcon() to account for overlays, underlays, etc. Use with extreme moderation, ESPECIALLY on mobs.
/proc/costly_icon2html(thing, target, sourceonly = FALSE, force_south = FALSE)
	if (!thing)
		return

	if (isicon(thing))
		return icon2html(thing, target)

	var/icon/I = getFlatIcon(thing, force_south = force_south)
	return icon2html(I, target, sourceonly = sourceonly)

/// A file's states and their direction counts (state name -> dirs), from its DMI metadata. Null when it has none.
/proc/build_icon_state_dir_counts(file)
	var/list/metadata = icon_metadata(file)
	if(!islist(metadata) || !islist(metadata["states"]))
		return null
	. = list()
	for(var/list/state_data as anything in metadata["states"])
		.[state_data["name"]] = state_data["dirs"]

/proc/build_icon_state_names(file)
	. = list()
	// Try to use rustg first
	var/list/metadata = icon_metadata(file)
	if(islist(metadata) && islist(metadata["states"]))
		for(var/list/state_data as anything in metadata["states"])
			. += state_data["name"]
	else // Otherwise, we have to use the slower BYOND proc
		for(var/istate in icon_states(file))
			. += istate

/proc/build_icon_size(icon_path)
	// Used cached icon metadata
	var/list/metadata = icon_metadata(icon_path)
	if(islist(metadata) && isnum(metadata["width"]) && isnum(metadata["height"]))
		return list("width" = metadata["width"], "height" = metadata["height"])
	// Otherwise, we have to use the slower BYOND proc
	return build_icon_size_pure(icon_path)

