// Editing the blob's appearance. Every menu is driven by the style data in
// protean_form.dm: simple styles pick a sprite; layered styles walk their
// layers, and import/export serialise the same layer list.

/// Radial editor. Returns TRUE if anything changed.
/datum/form/protean_blob/proc/edit_appearance(mob/living/carbon/human/H)
	var/list/choices = list(
		"Primary" = image(icon = 'icons/mob/species/protean/protean.dmi', icon_state = "primary"),
		"Highlight" = image(icon = 'icons/mob/species/protean/protean.dmi', icon_state = "highlight"),
	)
	var/list/styles = protean_blob_styles()
	for(var/id in styles)
		var/datum/protean_blob_style/S = styles[id]
		choices[id] = S.radial_image()
	var/choice = show_radial_menu(H, H, choices, require_near = TRUE, tooltips = FALSE)
	if(!choice || QDELETED(H) || H.incapacitated())
		return FALSE
	switch(choice)
		if("Primary")
			var/new_color = tgui_color_picker(H, "Pick primary color:", "Protean Primary", color_primary)
			if(!new_color)
				return FALSE
			color_primary = new_color
			return TRUE
		if("Highlight")
			var/new_color = tgui_color_picker(H, "Pick highlight color:", "Protean Highlight", color_highlight)
			if(!new_color)
				return FALSE
			color_highlight = new_color
			return TRUE
	var/datum/protean_blob_style/picked = styles[choice]
	if(!picked)
		return FALSE
	if(istype(picked, /datum/protean_blob_style/layered))
		if(!edit_layers(H, picked))
			return FALSE
	return set_style(picked.id, H)

/// Walk a layered style's menus. Returns TRUE if the style should be worn.
/datum/form/protean_blob/proc/edit_layers(mob/living/carbon/human/H, datum/protean_blob_style/layered/S)
	var/list/menu = list()
	for(var/datum/protean_blob_layer/L as anything in S.layers)
		if(L.editable)
			menu[L.label] = image(S.label_icon, L.label)
	menu["Import"] = image(S.label_icon, "Import")
	menu["Export"] = image(S.label_icon, "Export")
	var/choice = show_radial_menu(H, H, menu, radius = 60)
	if(!choice || QDELETED(H) || H.incapacitated())
		return FALSE
	switch(choice)
		if("Export")
			to_chat(H, span_notice("Exported style string is \" [S.export_string(src)] \". Use this to get the same style in the future with Import."))
			return TRUE
		if("Import")
			var/text = sanitizeSafe(tgui_input_text(H, "Paste the style string you exported with Export.", "Style loading", "", 240, encode = FALSE), 256)
			if(!text)
				return FALSE
			if(!S.import_string(src, H, text))
				to_chat(H, span_warning("That style string doesn't fit the [S.name] style."))
				return FALSE
			return TRUE
	var/layer_index = 0
	for(var/i in 1 to length(S.layers))
		var/datum/protean_blob_layer/L = S.layers[i]
		if(L.label == choice)
			layer_index = i
			break
	if(!layer_index)
		return FALSE
	var/datum/protean_blob_layer/L = S.layers[layer_index]
	var/list/options = list()
	for(var/option in S.layer_options(L, H))
		options[option] = image(S.icon, option, dir = L.preview_dir, pixel_x = L.preview_pixel_x, pixel_y = L.preview_pixel_y)
	var/new_state = show_radial_menu(H, H, options, radius = 90)
	if(!new_state || QDELETED(H) || H.incapacitated())
		return FALSE
	var/list/states = states_for(S)
	var/list/colors = colors_for(S)
	var/new_color = "#FFFFFF"
	if(L.colorable)
		new_color = tgui_color_picker(H, "Pick [lowertext(L.label)] color:", "[L.label] Color", colors[layer_index])
		if(!new_color)
			return FALSE
	states[layer_index] = new_state
	colors[layer_index] = new_color
	S.derive_states(states)
	return TRUE
