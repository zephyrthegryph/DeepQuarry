// DQAdd — Unified recolor tweak. Replaces /datum/gear_tweak/matrix_recolor as the
// default recolor slot on every gear datum (see /datum/gear/New() override).
//
// Metadata shape: list("mode" = "off"|"tint"|"palette"|"matrix", "value" = …)
//   off     — no recoloring; value ignored
//   tint    — value is a hex string ("#aabbcc"); multiplies via add_atom_colour
//   palette — value is a {original_hex: new_hex} dict; SwapColor per entry
//   matrix  — value is a 12+ element color matrix list; applied via add_atom_colour
//
// The palette swap mode reads the gear's source icon at edit time to enumerate the
// distinct colors the user can recolor. dq_get_gear_palette() caches per gear-type so
// the icon scan only runs once per type per session.

GLOBAL_DATUM_INIT(gear_tweak_unified_recolor, /datum/gear_tweak/recolor, new)

/datum/gear_tweak/recolor

/datum/gear_tweak/recolor/get_default()
	return list("mode" = "off")

/datum/gear_tweak/recolor/get_contents(metadata)
	if(!islist(metadata))
		return "Recolor: off"
	var/mode = metadata["mode"]
	switch(mode)
		if(null, "off")
			return "Recolor: off"
		if("tint")
			return "Recolor: tint [metadata["value"]]"
		if("palette")
			var/list/swaps = metadata["value"]
			var/count = islist(swaps) ? length(swaps) : 0
			return "Recolor: palette ([count] swap[count == 1 ? "" : "s"])"
		if("matrix")
			return "Recolor: matrix"
	return "Recolor: ?"

// Modal flow is unused for this tweak — React drives all three modes inline through
// the dedicated set_recolor action. Returning metadata unchanged means the legacy
// Change-button flow is a no-op if someone routes through it.
/datum/gear_tweak/recolor/get_metadata(user, metadata, datum/gear/gear)
	return metadata

/datum/gear_tweak/recolor/tweak_item(obj/item/I, metadata)
	if(!islist(metadata) || !istype(I))
		dq_log("recolor tweak_item: skipped — metadata=[islist(metadata) ? "list" : "[metadata]"] I=[I]")
		return
	var/mode = metadata["mode"]
	dq_log("recolor tweak_item: mode=[mode] for [I]")
	switch(mode)
		if(null, "off")
			return
		if("tint")
			var/color = metadata["value"]
			if(istext(color) && length(color) >= 4 && color != "#ffffff")
				I.add_atom_colour(color, FIXED_COLOUR_PRIORITY)
				dq_log("tint apply: color=[color] applied to [I] (atom_colours after: [json_encode(I.atom_colours)])")
			else
				dq_log("tint apply: skipped — color=[color] istext=[istext(color)] len=[istext(color) ? length(color) : 0]")
		if("palette")
			var/list/swaps = metadata["value"]
			if(!islist(swaps) || !length(swaps))
				dq_log("palette apply: skipped — no swaps for [I]")
				return
			// Swap colors across every icon resource the item exposes — the ground/inv
			// sprite (I.icon), the worn override (I.icon_override), per-slot worn icons
			// (I.item_icons), and per-species sheets (I.sprite_sheets). Items that rely
			// on a default worn sheet (no override, no item_icons) only get their ground
			// sprite recolored; the mob render still uses the un-swapped default sheet.
			// A full fix needs `update_clothing_icon`-level intervention per clothing
			// subtype.
			var/swap_count = 0
			var/icon/ground = _swap_icon(I.icon, swaps)
			if(ground)
				I.icon = ground
				swap_count += swaps.len
			if(I.icon_override)
				var/icon/swapped_override = _swap_icon(I.icon_override, swaps)
				if(swapped_override)
					I.icon_override = swapped_override
			else
				// No explicit override — mob renderer falls back to a per-slot default
				// worn sheet (e.g. icons/inventory/uniform/mob.dmi for uniforms). Clone
				// that sheet, apply the swap, and stash it as icon_override so the
				// renderer's get_worn_icon_file picks it up.
				//
				// Skip the icon_override path when the wearer's species has its own entry
				// in sprite_sheets — icon_override would otherwise win over the species
				// sheet (which we already swapped above), clobbering species-specific
				// worn art for Teshari / Vox / Werebeast / etc.
				var/skip_override = FALSE
				if(islist(I.sprite_sheets) && ishuman(I.loc))
					var/mob/living/carbon/human/wearer = I.loc
					var/species_name = wearer.species?.name
					if(species_name && I.sprite_sheets[species_name])
						skip_override = TRUE
				if(!skip_override)
					var/default_worn = _default_worn_icon(I)
					if(default_worn)
						var/icon/swapped_default = _swap_icon(default_worn, swaps)
						if(swapped_default)
							I.icon_override = swapped_default
			if(islist(I.item_icons))
				var/list/new_item_icons = list()
				for(var/slot in I.item_icons)
					var/icon/swapped_slot = _swap_icon(I.item_icons[slot], swaps)
					new_item_icons[slot] = swapped_slot || I.item_icons[slot]
				I.item_icons = new_item_icons
			if(islist(I.sprite_sheets))
				var/list/new_sheets = list()
				for(var/species in I.sprite_sheets)
					var/icon/swapped_sheet = _swap_icon(I.sprite_sheets[species], swaps)
					new_sheets[species] = swapped_sheet || I.sprite_sheets[species]
				I.sprite_sheets = new_sheets
			dq_log("palette apply: [swap_count] swaps applied to [I] (worn override=[I.icon_override ? "yes" : "no"], slot icons=[islist(I.item_icons) ? I.item_icons.len : 0], species sheets=[islist(I.sprite_sheets) ? I.sprite_sheets.len : 0])")
		if("matrix")
			var/list/m = metadata["value"]
			if(islist(m) && length(m) >= 12)
				I.add_atom_colour(m, FIXED_COLOUR_PRIORITY)

/// Clone an icon resource (file or /icon) and apply the `swaps` color mapping. Returns
/// a new /icon, or null if the source can't be cloned. Identity swaps (orig == new) are
/// no-ops and skipped.
/datum/gear_tweak/recolor/proc/_swap_icon(source, list/swaps)
	if(!source)
		return null
	var/icon/working
	try
		working = new /icon(source)
	catch
		return null
	if(!working)
		return null
	// `new /icon(source)` always returns an /icon datum with its own bitmap copy regardless
	// of whether source is a file path or another /icon. The defensive second clone we
	// briefly carried here was redundant — the codebase's other SwapColor sites in
	// _helpers/icons.dm use a single new(src) + SwapColor and don't bleed.
	for(var/orig in swaps)
		var/new_color = swaps[orig]
		if(istext(new_color) && new_color != orig)
			working.SwapColor(orig, new_color)
	return working

/// Returns the default worn-icon file that the mob renderer falls back to for items of
/// this type when no icon_override / sprite_sheets / item_icons entry covers the slot.
/// Mirrors the INV_*_DEF_ICON constants used in update_icons.dm's update_inv_* procs.
/// Returns null for item types we don't know about (no override applied for those).
/datum/gear_tweak/recolor/proc/_default_worn_icon(obj/item/I)
	if(istype(I, /obj/item/clothing/under))     return INV_W_UNIFORM_DEF_ICON
	if(istype(I, /obj/item/clothing/suit))      return INV_SUIT_DEF_ICON
	if(istype(I, /obj/item/clothing/head))      return INV_HEAD_DEF_ICON
	if(istype(I, /obj/item/clothing/mask))      return INV_MASK_DEF_ICON
	if(istype(I, /obj/item/clothing/gloves))    return INV_GLOVES_DEF_ICON
	if(istype(I, /obj/item/clothing/shoes))     return INV_FEET_DEF_ICON
	if(istype(I, /obj/item/clothing/ears))      return INV_EARS_DEF_ICON
	if(istype(I, /obj/item/clothing/glasses))   return INV_EYES_DEF_ICON
	if(istype(I, /obj/item/storage/belt))       return INV_BELT_DEF_ICON
	if(istype(I, /obj/item/storage/backpack))   return INV_BACK_DEF_ICON
	if(istype(I, /obj/item/clothing/accessory)) return INV_ACCESSORIES_DEF_ICON
	return null

/// Same lookup as _default_worn_icon, but keyed by type path (no instance available at
/// palette-scan time). Used by dq_get_gear_palette to include the worn-sheet colors in
/// the swatch grid — without this, the user picks colors from the ground sprite and
/// SwapColor finds no matches in the worn sprite (different .dmi with different shading
/// palette), leaving the mob render visually unchanged.
/proc/_dq_default_worn_icon_for_path(item_path)
	if(!ispath(item_path))
		return null
	if(ispath(item_path, /obj/item/clothing/under))     return INV_W_UNIFORM_DEF_ICON
	if(ispath(item_path, /obj/item/clothing/suit))      return INV_SUIT_DEF_ICON
	if(ispath(item_path, /obj/item/clothing/head))      return INV_HEAD_DEF_ICON
	if(ispath(item_path, /obj/item/clothing/mask))      return INV_MASK_DEF_ICON
	if(ispath(item_path, /obj/item/clothing/gloves))    return INV_GLOVES_DEF_ICON
	if(ispath(item_path, /obj/item/clothing/shoes))     return INV_FEET_DEF_ICON
	if(ispath(item_path, /obj/item/clothing/ears))      return INV_EARS_DEF_ICON
	if(ispath(item_path, /obj/item/clothing/glasses))   return INV_EYES_DEF_ICON
	if(ispath(item_path, /obj/item/storage/belt))       return INV_BELT_DEF_ICON
	if(ispath(item_path, /obj/item/storage/backpack))   return INV_BACK_DEF_ICON
	if(ispath(item_path, /obj/item/clothing/accessory)) return INV_ACCESSORIES_DEF_ICON
	return null

// ─── Palette scanner (used at edit time to expose the gear's source colors) ────────

/// Returns up to `max_colors` distinct hex colors found in the icon, ordered by area
/// covered (most-frequent first). Skips transparent pixels. Used to populate the
/// palette-swap swatch grid in the React widget.
/proc/dq_scan_icon_palette(icon_path, icon_state, max_colors = 12)
	if(!icon_path)
		return list()
	var/icon/sample
	try
		sample = icon(icon_path, icon_state, SOUTH, 1)
	catch
		return list()
	if(!sample)
		return list()
	var/w = sample.Width()
	var/h = sample.Height()
	if(!w || !h)
		return list()
	var/list/counts = list()
	for(var/x in 1 to w)
		for(var/y in 1 to h)
			var/pix = sample.GetPixel(x, y)
			if(!pix)
				continue
			counts[pix] = (counts[pix] || 0) + 1
	// Pick the top-N by count without sorting the whole assoc — N is small so the
	// scan-per-pick approach is fine.
	var/list/out = list()
	var/list/picked = list()
	for(var/i in 1 to max_colors)
		var/best_color = null
		var/best_count = 0
		for(var/color in counts)
			if(picked[color])
				continue
			if(counts[color] > best_count)
				best_count = counts[color]
				best_color = color
		if(!best_color)
			break
		out += best_color
		picked[best_color] = TRUE
	return out

/// Returns the cached palette for a gear datum. Scans both the ground sprite and the
/// item's default worn sheet (e.g. uniform/mob.dmi for /obj/item/clothing/under) so the
/// React swatch grid offers colors that exist in BOTH renders. Without scanning the worn
/// sheet, the user picks a shade from the ground icon that doesn't pixel-match the worn
/// art and SwapColor silently fails to recolor the on-mob sprite.
///
/// Worn-sheet colors are scanned by gear display name (the worn sheet typically uses
/// `icon_state == name` minus spaces — see how update_inv_w_uniform/etc. derive their
/// state), falling back to the gear's main `icon_state` if a derived name yields nothing.
/proc/dq_get_gear_palette(datum/gear/G)
	var/static/list/cache = list()
	if(!G || !G.path)
		return list()
	var/key = "[G.type]"
	// `key in cache` correctly distinguishes "not yet scanned" from "scanned and empty";
	// !cache[key] would re-scan icons that legitimately have no extractable palette
	// (transparent-only, missing icon_state, etc.) on every UI poll.
	if(!(key in cache))
		var/atom/A = G.path
		var/list/combined = list()
		var/list/seen = list()
		var/list/ground = dq_scan_icon_palette(initial(A.icon), initial(A.icon_state))
		for(var/c in ground)
			if(!seen[c])
				combined += c
				seen[c] = TRUE
		var/worn_icon = _dq_default_worn_icon_for_path(G.path)
		if(worn_icon)
			// Worn .dmi files key states off the item's icon_state (same string as the
			// ground sheet uses). If the worn sheet doesn't expose that state, fall back
			// to scanning the icon's first state (icon_state = null grabs frame-1 of the
			// first state).
			var/list/worn = dq_scan_icon_palette(worn_icon, initial(A.icon_state))
			if(!length(worn))
				worn = dq_scan_icon_palette(worn_icon, null)
			for(var/c in worn)
				if(!seen[c])
					combined += c
					seen[c] = TRUE
		cache[key] = combined
	return cache[key]
