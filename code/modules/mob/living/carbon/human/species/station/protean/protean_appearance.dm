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
			// The answer sets the colour and refreshes the appearance.
			om_ask(H, /datum/om/prompt/color/protean_blob, PROC_REF(blob_color_picked), message = "Pick primary color:", title = "Protean Primary", default = color_primary, highlight = FALSE)
			return FALSE
		if("Highlight")
			om_ask(H, /datum/om/prompt/color/protean_blob, PROC_REF(blob_color_picked), message = "Pick highlight color:", title = "Protean Highlight", default = color_highlight, highlight = TRUE)
			return FALSE
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
			om_ask(H, /datum/om/prompt/text/protean_style, PROC_REF(style_string_entered), style = S)
			return FALSE // The answer imports and wears the style.
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
	if(L.colorable)
		// The answer sets the layer, wears the style and refreshes the appearance.
		var/list/colors = colors_for(S)
		om_ask(H, /datum/om/prompt/color/protean_layer, PROC_REF(layer_color_picked), message = "Pick [lowertext(L.label)] color:", title = "[L.label] Color", default = colors[layer_index], style = S, layer_index = layer_index, new_state = new_state)
		return FALSE
	set_layer(S, layer_index, new_state, "#FFFFFF")
	return TRUE

/// Sets one layer of a layered style and re-derives its states.
/datum/form/protean_blob/proc/set_layer(datum/protean_blob_style/layered/S, layer_index, new_state, new_color)
	var/list/states = states_for(S)
	var/list/colors = colors_for(S)
	states[layer_index] = new_state
	colors[layer_index] = new_color
	S.derive_states(states)

/// Refreshes H's appearance if this blob form is the one worn.
/datum/form/protean_blob/proc/refresh_if_worn(mob/living/carbon/human/H)
	var/datum/forms/F = H.get_forms()
	if(F?.current == src)
		F.refresh_appearance()

/// A blob colour (primary, or highlight). Re-checked on the answer: conscious.
/datum/om/prompt/color/protean_blob
	ask_flags = ASK_CONSCIOUS
	var/highlight = FALSE

/// A layer's colour; carries the style, the layer and its new state. Re-checked: conscious.
/datum/om/prompt/color/protean_layer
	ask_flags = ASK_CONSCIOUS
	var/datum/protean_blob_style/layered/style
	var/layer_index
	var/new_state

/// Importing a style string into a layered style. Re-checked on the answer: conscious.
/datum/om/prompt/text/protean_style
	title = "Style loading"
	message = "Paste the style string you exported with Export."
	max_length = 240
	encode = FALSE
	ask_flags = ASK_CONSCIOUS
	var/datum/protean_blob_style/layered/style

/datum/form/protean_blob/proc/blob_color_picked(datum/om/prompt/color/protean_blob/ask)
	if(!ask.picked_color)
		return
	if(ask.highlight)
		color_highlight = ask.picked_color
	else
		color_primary = ask.picked_color
	refresh_if_worn(ask.answerer)

/datum/form/protean_blob/proc/layer_color_picked(datum/om/prompt/color/protean_layer/ask)
	if(!ask.picked_color)
		return
	set_layer(ask.style, ask.layer_index, ask.new_state, ask.picked_color)
	if(set_style(ask.style.id, ask.answerer))
		refresh_if_worn(ask.answerer)

/datum/form/protean_blob/proc/style_string_entered(datum/om/prompt/text/protean_style/ask)
	var/mob/living/carbon/human/H = ask.answerer
	var/datum/protean_blob_style/layered/S = ask.style
	var/text = sanitizeSafe(ask.text, 256)
	if(!text)
		return
	if(!S.import_string(src, H, text))
		to_chat(H, span_warning("That style string doesn't fit the [S.name] style."))
		return
	if(set_style(S.id, H))
		refresh_if_worn(H)
