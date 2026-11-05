// Optional clothing recolour through up to 3 colour channels.
//
// strings/clothing_channels/generated.json (tools/clothing_channels/generate.sh, never hand edited) says which source colours make up
// each channel of each wearable type, the channel's base colour first. strings/clothing_channels/overrides.json (hand written, the
// generator never touches it) wins over it, one type at a time:
//   "/obj/item/clothing/x": {"disabled": true}                          no channels for this type
//   "/obj/item/clothing/x": {"channels": ["aabbcc112233", "ddeeff"]}    replace the channels (6 hex digits a colour, the base first)
//   "/obj/item/clothing/x": {"move": {"aabbcc": 2, "112233": 0}}        move single colours: to channel 1-3, or 0 to lock (never recoloured)
//
// This is the only way clothing is recoloured: the loadout's channels tweak (/datum/gear_tweak/channels) and the in-game Recolour verb
// both end here. An item with chosen colours carries them in the lazy state field clothing_channel_colors. Nothing else changes on it: the sprite is
// resolved when it is drawn, so every sheet (species, in-hand, rolled states) works, and only the state in use is ever copied.
// An item without chosen colours pays one null check when it is drawn.

#define CLOTHING_CHANNELS_MAX 3
#define CLOTHING_CHANNELS_GENERATED "strings/clothing_channels/generated.json"
#define CLOTHING_CHANNELS_OVERRIDES "strings/clothing_channels/overrides.json"


/// The data, read on first use: a server where nobody recolours anything never parses it.
GLOBAL_LIST_EMPTY(clothing_channel_data)

PROC_SUMMARY(/proc/clothing_channel_data_load) // constant data read once from disk: nothing a look could follow
/proc/clothing_channel_data_load()
	if(length(GLOB.clothing_channel_data))
		return GLOB.clothing_channel_data
	var/list/generated = json_decode(file2text(CLOTHING_CHANNELS_GENERATED))
	GLOB.clothing_channel_data = list(
		"luts" = generated["luts"],
		"types" = generated["types"],
		"overrides" = json_decode(file2text(CLOTHING_CHANNELS_OVERRIDES)) || list(),
	)
	return GLOB.clothing_channel_data

/// list(key, channels): the channels of a type and the key its work is cached under (types with the same channels share one). Null when it has none.
PROC_SUMMARY(/proc/clothing_channels_of) // a lookup in that constant data, by type
/proc/clothing_channels_of(item_type)
	var/list/data = clothing_channel_data_load()
	var/type_key = "[item_type]"
	var/list/row = data["types"][type_key]
	var/list/channels
	var/key
	if(row)
		key = "g[row[1]]"
		channels = data["luts"][row[1] + 1]
	var/list/override = data["overrides"][type_key]
	if(override)
		if(override["disabled"])
			return null
		key = "o[type_key]"
		if(override["channels"])
			channels = override["channels"]
		if(override["move"])
			channels = clothing_channels_move(channels, override["move"])
	if(!length(channels))
		return null
	return list(key, channels)

/// A copy of `channels` with the colours of `moves` (rrggbb -> channel 1-3, 0 locks it) taken out and put at the end of their new channel.
/proc/clothing_channels_move(list/channels, list/moves)
	var/list/out = list()
	for(var/i in 1 to CLOTHING_CHANNELS_MAX)
		out += ""
	for(var/i in 1 to min(length(channels), CLOTHING_CHANNELS_MAX))
		var/text = channels[i]
		for(var/at = 1; at < length(text); at += 6)
			var/hex = copytext(text, at, at + 6)
			if(isnull(moves[hex]))
				out[i] += hex
	for(var/hex in moves)
		var/to_channel = moves[hex]
		if(isnum(to_channel) && to_channel >= 1 && to_channel <= CLOTHING_CHANNELS_MAX)
			out[to_channel] += hex
	while(length(out) && !length(out[length(out)]))
		out.len--
	return out

/// The base colour of each channel ("#rrggbb"): what the loadout offers. Empty for a type without channels.
/proc/clothing_channel_bases(item_type)
	var/list/found = clothing_channels_of(item_type)
	var/list/bases = list()
	if(found)
		for(var/text in found[2])
			bases += length(text) ? "#[copytext(text, 1, 7)]" : ""
	return bases

/// A chosen list of colours as one canonical text ("#aabbcc||#112233"), null when nothing is chosen. The cache key and the lazy state field.
/proc/clothing_channel_colors_key(list/colors)
	if(!islist(colors))
		return null
	var/list/parts = list()
	var/any = FALSE
	for(var/i in 1 to min(length(colors), CLOTHING_CHANNELS_MAX))
		var/normal = clothing_channel_normal_hex(colors[i])
		parts += normal || ""
		any = any || !!normal
	return any ? jointext(parts, "|") : null

/// "#rrggbb" in lower case, or null when `text` is not a colour.
/proc/clothing_channel_normal_hex(text)
	if(!istext(text) || length(text) != 7 || copytext(text, 1, 2) != "#")
		return null
	var/lower = lowertext(text)
	if(isnull(hex2num(copytext(lower, 2))) || !findtext(lower, regex(@"^#[0-9a-f]{6}$")))
		return null
	return lower

// ---------------------------------------------------------------- the colour mapping

/proc/clothing_channel_srgb_to_linear(c)
	c /= 255
	return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4

/proc/clothing_channel_linear_to_srgb(c)
	c = clamp(c, 0, 1)
	return round((c <= 0.0031308 ? c * 12.92 : 1.055 * c ** (1 / 2.4) - 0.055) * 255 + 0.5)

/proc/clothing_channel_cbrt(x)
	return x < 0 ? -((-x) ** (1 / 3)) : x ** (1 / 3)

/// rrggbb -> list(L, a, b) in OKLab.
/proc/clothing_channel_oklab(hex)
	var/r = clothing_channel_srgb_to_linear(hex2num(copytext(hex, 1, 3)))
	var/g = clothing_channel_srgb_to_linear(hex2num(copytext(hex, 3, 5)))
	var/b = clothing_channel_srgb_to_linear(hex2num(copytext(hex, 5, 7)))
	var/l = clothing_channel_cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
	var/m = clothing_channel_cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
	var/s = clothing_channel_cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
	return list(0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s, 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s, 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s)

/// OKLab -> "#rrggbb".
/proc/clothing_channel_from_oklab(L, a, b)
	var/l1 = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
	var/m1 = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
	var/s1 = (L - 0.0894841775 * a - 1.291485548 * b) ** 3
	return rgb(clothing_channel_linear_to_srgb(4.0767416621 * l1 - 3.3077115913 * m1 + 0.2309699292 * s1), clothing_channel_linear_to_srgb(-1.2684380046 * l1 + 2.6097574011 * m1 - 0.3413193965 * s1), clothing_channel_linear_to_srgb(-0.0041960863 * l1 - 0.7034186147 * m1 + 1.707614701 * s1))

/// Maps a channel's colours onto a new base: each keeps its offset from the old base, its hue turned and its chroma scaled to the target,
/// its lightness offset compressed only as far as it would clip. Fills `into` ("#source" -> "#result"). The generator's recolour().
/proc/clothing_channel_map_channel(text, target, list/into)
	var/base_hex = copytext(text, 1, 7)
	if("#[base_hex]" == target)
		return // the base itself: exactly the original art
	var/list/base = clothing_channel_oklab(base_hex)
	var/list/goal = clothing_channel_oklab(copytext(target, 2))
	var/list/hexes = list()
	var/list/deltas = list()
	var/up = 0.000001
	var/down = 0.000001
	for(var/at = 1; at < length(text); at += 6)
		var/hex = copytext(text, at, at + 6)
		var/list/lab = clothing_channel_oklab(hex)
		var/delta_l = lab[1] - base[1]
		up = max(up, delta_l)
		down = max(down, -delta_l)
		hexes += hex
		deltas += list(list(delta_l, lab[2] - base[2], lab[3] - base[3]))
	var/scale_up = min(1, (1 - goal[1]) / up)
	var/scale_down = min(1, goal[1] / down)
	var/goal_chroma = sqrt(goal[2] ** 2 + goal[3] ** 2)
	var/base_chroma = sqrt(base[2] ** 2 + base[3] ** 2)
	var/turn = FALSE
	var/ca = 1
	var/sa = 0
	var/scale = 1
	if(base_chroma > 0.02)
		turn = TRUE
		scale = min(1, goal_chroma / base_chroma)
		if(goal_chroma > 0.01)
			// cos and sin of the angle from the base's hue to the goal's: a rotation, no angle needed
			ca = (goal[2] * base[2] + goal[3] * base[3]) / (goal_chroma * base_chroma)
			sa = (goal[3] * base[2] - goal[2] * base[3]) / (goal_chroma * base_chroma)
	for(var/i in 1 to length(hexes))
		var/list/d = deltas[i]
		var/dl = d[1] * (d[1] > 0 ? scale_up : scale_down)
		var/da = d[2]
		var/db = d[3]
		if(turn)
			var/ta = (ca * da - sa * db) * scale
			db = (sa * da + ca * db) * scale
			da = ta
		into["#[hexes[i]]"] = clothing_channel_from_oklab(goal[1] + dl, goal[2] + da, goal[3] + db)

/// A colour no sheet is expected to hold, for breaking a cycle of swaps.
#define CLOTHING_CHANNEL_SPARE_BASE 0xFE01FD

/// Orders a mapping (source -> result) so that running it as SwapColors, one after another, acts as one simultaneous mapping: a colour is
/// swapped away before anything is swapped into it, and a cycle goes through a spare colour. Returns a flat list(from, to, from, to...).
/proc/clothing_channel_order_swaps(list/mapping)
	var/list/pending = list()
	for(var/from in mapping)
		if(mapping[from] != from)
			pending[from] = mapping[from]
	var/list/ordered = list()
	var/spare = CLOTHING_CHANNEL_SPARE_BASE
	while(length(pending))
		var/progress = FALSE
		for(var/from in pending.Copy())
			if(!isnull(pending[pending[from]]))
				continue
			ordered += from
			ordered += pending[from]
			pending -= from
			progress = TRUE
		if(progress)
			continue
		// Only cycles are left. Free one colour by moving it to a spare that nothing maps to or from.
		var/from = pending[1]
		var/spare_hex
		do
			spare_hex = "#[num2hex(spare, 6)]"
			spare--
		while(!isnull(mapping[spare_hex]) || (spare_hex in pending))
		ordered += from
		ordered += spare_hex
		pending[spare_hex] = pending[from]
		pending -= from
	return ordered

#undef CLOTHING_CHANNEL_SPARE_BASE

DECLARE_SHARED_CACHE_EX(clothing_channel_swaps, GLOBAL_PROC_REF(build_clothing_channel_swaps), SC_NEVER, 1024, 0)

/// The ordered swaps of one set of channels and one choice of colours.
/proc/build_clothing_channel_swaps(list/channels, colors_key)
	var/list/targets = splittext(colors_key, "|")
	var/list/mapping = list()
	for(var/i in 1 to min(length(channels), length(targets)))
		if(length(targets[i]) && length(channels[i]))
			clothing_channel_map_channel(channels[i], targets[i], mapping)
	return clothing_channel_order_swaps(mapping)

/// Bounded: unlimited colour choices must not grow without end. Measured November 2026 over 600 distinct items: 21 ms for a first sight (mapping, item sheet, worn sprite), 0.33 ms for a cached draw.
DECLARE_SHARED_CACHE_EX(clothing_channel_icons, GLOBAL_PROC_REF(build_clothing_channel_resource), SC_NEVER, 2048, 0)

/// One state of one sheet with the swaps applied, as a one-state icon. The whole sheet is never copied.
/proc/build_clothing_channel_icon(source_icon, state, list/swaps, addblends)
	var/icon/result = icon(source_icon, state)
	for(var/i = 1; i < length(swaps); i += 2)
		result.SwapColor(swaps[i], swaps[i + 1])
	if(addblends)
		result.Blend(icon(source_icon, addblends), ICON_ADD)
	return result

/// The cached value: the sprite as a resource. Drawing from it costs what drawing from a sheet costs; an /icon would be hashed into the resource cache on every image().
/proc/build_clothing_channel_resource(source_icon, state, list/swaps, addblends)
	return fcopy_rsc(build_clothing_channel_icon(source_icon, state, swaps, addblends))

/// The recoloured sprite of (sheet, state) for a type and a colour key, shared by everything that asks for the same; null when there is nothing to do.
/proc/clothing_channel_icon(item_type, source_icon, state, colors_key, addblends)
	READS_FROM()
	if(!colors_key || !source_icon)
		return null
	if(istext(source_icon))
		source_icon = file(source_icon)
	if(!isfile(source_icon) || !length("[source_icon]")) // an icon made at runtime has no key to share under
		return null
	var/list/found = clothing_channels_of(item_type)
	if(!found)
		return null
	var/list/swaps = CACHED_KEY(clothing_channel_swaps, "[found[1]]|[colors_key]", found[2], colors_key)
	if(!length(swaps))
		return null
	return CACHED_KEY(clothing_channel_icons, "[found[1]]|[colors_key]|[source_icon]|[state]|[addblends]", source_icon, state, swaps, addblends)

DECLARE_SHARED_CACHE_EX(clothing_channel_item_sheets, GLOBAL_PROC_REF(build_clothing_channel_item_sheet), SC_NEVER, 1024, 0)

/// The item's own sprite as a small sheet that keeps state names, so an item that toggles its state (a coat opening) still finds it. The default ""
/// state repeats the main sprite: a state the data does not know shows that rather than nothing.
/proc/build_clothing_channel_item_sheet(source_icon, state, list/family, list/swaps)
	var/icon/sheet = new
	sheet.Insert(build_clothing_channel_icon(source_icon, state, swaps), "")
	sheet.Insert(build_clothing_channel_icon(source_icon, state, swaps), state)
	var/list/present = icon_states(source_icon)
	for(var/name in family)
		if(name in present)
			sheet.Insert(build_clothing_channel_icon(source_icon, name, swaps), name)
	return fcopy_rsc(sheet)

PROC_SUMMARY(/obj/item/proc/clothing_channel_worn) // the colours are set once, when the item spawns, before anything draws it
/// The recoloured worn sprite of this item, or null: an item with no chosen colours stops at the first check.
/obj/item/proc/clothing_channel_worn(source_icon, state, addblends)
	if(!(!isnull(STATE_PEEK(src, item_misc, clothing_channel_colors))))
		return null
	return clothing_channel_icon(type, source_icon, state, STATE_PEEK(src, item_misc, clothing_channel_colors), addblends)

/// Gear metadata with every channel colour linked to a palette slot replaced by the slot's colour now. The saved metadata is never
/// written to; metadata without channel colours comes back as it is.
/proc/clothing_channel_resolve_links(datum/gear/G, list/metadata, datum/preferences/prefs)
	if(!prefs || !G || !islist(metadata))
		return metadata
	var/index = G.channels_tweak_index()
	var/list/stored = index ? metadata["[index]"] : null
	if(!islist(stored))
		return metadata
	var/list/colors = list()
	for(var/entry in stored)
		colors += prefs.resolve_color_link(entry)
	var/list/resolved = metadata.Copy()
	resolved["[index]"] = colors
	return resolved

/// Puts chosen colours on an item, or with no colour chosen takes them off. The item's own `color` goes: its channels are its colour.
/obj/item/proc/apply_clothing_channels(list/colors)
	var/colors_key = clothing_channel_colors_key(colors)
	var/list/found = clothing_channels_of(type)
	if(!found)
		return FALSE
	var/had_colours = (!isnull(STATE_PEEK(src, item_misc, clothing_channel_colors)))
	if(!colors_key)
		if(had_colours)
			STATE_SET(src, item_misc, clothing_channel_colors, null)
			set_icon(initial(icon))
		return FALSE
	STATE_SET(src, item_misc, clothing_channel_colors, colors_key)
	set_color(null)
	// Recolouring again starts from the type's own sheet: the current icon is already a recoloured copy.
	var/source_icon = had_colours ? initial(icon) : icon
	if(istext(source_icon))
		source_icon = file(source_icon)
	if(isfile(source_icon) && icon_state)
		var/list/swaps = CACHED_KEY(clothing_channel_swaps, "[found[1]]|[colors_key]", found[2], colors_key)
		if(length(swaps))
			var/list/data = clothing_channel_data_load()
			var/list/row = data["types"]["[type]"]
			var/list/family = length(row) > 1 ? row.Copy(2) : null
			set_icon(CACHED_KEY(clothing_channel_item_sheets, "[found[1]]|[colors_key]|[source_icon]|[icon_state]", source_icon, icon_state, family, swaps))
		else
			set_icon(source_icon)
	return TRUE

// ---------------------------------------------------------------- save migration
//
// Loadout clothing used to be coloured four other ways: a colour tweak (a hex string at its own index) and the recolor tweak's "tint",
// "palette" and "matrix" modes (list("mode" = ..., "value" = ...)). Each becomes the channel colours that reproduce it on each channel's
// base colour: what the old method did to the pixel the channel is named after. Runs from the gear_list sanitizer on load.

/// `hex` ("#rrggbb") multiplied by a tint, as add_atom_colour() drew it.
/proc/clothing_channel_tint(hex, tint)
	var/list/a = rgb2num(hex)
	var/list/b = rgb2num(tint)
	return lowertext(rgb(round(a[1] * b[1] / 255 + 0.5), round(a[2] * b[2] / 255 + 0.5), round(a[3] * b[3] / 255 + 0.5)))

/// `hex` through a BYOND colour matrix (12, 16 or 20 numbers), or null for a list that is not one.
/proc/clothing_channel_matrix(hex, list/m)
	var/stride
	var/offset
	switch(length(m))
		if(12)
			stride = 3
			offset = 9
		if(16)
			stride = 4
		if(20)
			stride = 4
			offset = 16
		else
			return null
	var/list/c = rgb2num(hex)
	var/list/out = list()
	for(var/k in 1 to 3)
		var/v = c[1] / 255 * m[k] + c[2] / 255 * m[stride + k] + c[3] / 255 * m[stride * 2 + k]
		if(offset)
			v += m[offset + k]
		out += round(clamp(v, 0, 1) * 255 + 0.5)
	return lowertext(rgb(out[1], out[2], out[3]))

/// Multiplies each channel (its choice so far, else its base) by `tint`, as the old tint did. FALSE for a tint that is not a colour.
/proc/clothing_channel_apply_tint(list/targets, list/bases, tint)
	tint = clothing_channel_normal_hex(istext(tint) ? lowertext(tint) : null)
	if(!tint)
		return FALSE
	if(tint == "#ffffff")
		return TRUE
	for(var/i in 1 to length(targets))
		var/from = clothing_channel_normal_hex(targets[i]) || bases[i]
		if(from)
			targets[i] = clothing_channel_tint(from, tint)
	return TRUE

/// One gear entry's saved metadata with every old colour method turned into channel colours, in place. Returns `meta`. Running it
/// again changes nothing: what it reads is gone once converted, and a colour is never saved at the removed tweak's index again.
/proc/clothing_channel_migrate_meta(datum/gear/G, list/meta)
	if(!G || !islist(meta))
		return meta
	var/index = G.channels_tweak_index()
	var/key = index ? "[index]" : null
	var/list/bases = clothing_channel_bases(G.path)
	var/list/targets = list()
	for(var/base in bases)
		targets += ""
	var/changed = FALSE
	// The recolor tweak's old shape, or a colour saved where the channels tweak now sits (an entry that only had a colour tweak).
	var/old = key ? meta[key] : null
	if(istext(old))
		clothing_channel_apply_tint(targets, bases, old)
		meta -= key
		changed = TRUE
	else if(islist(old) && !isnull(old["mode"]))
		var/list/value = old["value"]
		switch(old["mode"])
			if("channels")
				if(islist(value))
					for(var/i in 1 to min(length(value), length(targets)))
						targets[i] = value[i]
			if("tint")
				clothing_channel_apply_tint(targets, bases, value)
			if("palette")
				if(islist(value))
					for(var/i in 1 to length(bases))
						var/swapped = value[bases[i]] || value[uppertext(bases[i])]
						if(clothing_channel_normal_hex(istext(swapped) ? lowertext(swapped) : null))
							targets[i] = lowertext(swapped)
			if("matrix")
				if(islist(value))
					for(var/i in 1 to length(bases))
						var/mapped = clothing_channel_matrix(bases[i], value)
						if(mapped)
							targets[i] = mapped
		meta -= key
		changed = TRUE
	// The removed colour tweak: its saved colour, and every tweak after it one index down.
	var/legacy = G.legacy_colour_index
	var/legacy_value = legacy ? meta["[legacy]"] : null
	if(legacy && legacy != index && istext(legacy_value) && copytext(legacy_value, 1, 2) == "#")
		clothing_channel_apply_tint(targets, bases, legacy_value)
		var/last = legacy
		for(var/k in meta)
			var/n = text2num(k)
			if(isnum(n) && n > last)
				last = n
		for(var/n in legacy to last - 1)
			if(isnull(meta["[n + 1]"]))
				meta -= "[n]"
			else
				meta["[n]"] = meta["[n + 1]"]
		meta -= "[last]"
		changed = TRUE
	if(!changed)
		return meta
	// A channel left at its base colour is drawn as it is.
	for(var/i in 1 to length(targets))
		if(targets[i] == bases[i])
			targets[i] = ""
	var/list/cleaned = clothing_channel_clean_choice(targets)
	if(cleaned && key)
		meta[key] = cleaned
	return meta

#undef CLOTHING_CHANNELS_GENERATED
#undef CLOTHING_CHANNELS_OVERRIDES
