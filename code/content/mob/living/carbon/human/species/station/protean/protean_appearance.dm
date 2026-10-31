// Editing the blob's appearance. Every menu is driven by the style data in
// protean_form.dm: simple styles pick a sprite; layered styles walk their
// layers, and import/export serialise the same layer list.

/// Radial editor. The answer procs apply the change and refresh the worn appearance.
/datum/form/protean_blob/proc/edit_appearance(mob/living/carbon/human/H)
	var/list/choices = list(
		"Primary" = image(icon = 'icons/mob/species/protean/protean.dmi', icon_state = "primary"),
		"Highlight" = image(icon = 'icons/mob/species/protean/protean.dmi', icon_state = "highlight"),
	)
	var/list/styles = GLOBAL_TABLE_GET(protean_blob_styles)
	for(var/id in styles)
		var/datum/protean_blob_style/S = styles[id]
		choices[id] = S.radial_image()
	open_request(src, /datum/prompt/choice, PROC_REF(appearance_chosen), answerer = H, timeout = 0, radial = TRUE, autopick_single_option = TRUE, choices = choices, anchor = H, require_near = TRUE, tooltips = FALSE)

/// First radial answer: a colour, or a style (layered styles open their layer menu).
/datum/form/protean_blob/proc/appearance_chosen(datum/act/request/context)
	var/datum/prompt/choice/ask = context.request
	if(!context.answer)
		return
	var/mob/living/carbon/human/H = ask.answerer
	var/choice = ask.value
	if(!choice || QDELETED(H) || H.incapacitated())
		return
	switch(choice)
		if("Primary")
			// The answer sets the colour and refreshes the appearance.
			open_request(src, /datum/prompt/color/protean_blob, PROC_REF(blob_color_picked), answerer = H, question = "Pick primary color:", title = "Protean Primary", default = color_primary, highlight = FALSE)
			return
		if("Highlight")
			open_request(src, /datum/prompt/color/protean_blob, PROC_REF(blob_color_picked), answerer = H, question = "Pick highlight color:", title = "Protean Highlight", default = color_highlight, highlight = TRUE)
			return
	var/list/styles = GLOBAL_TABLE_GET(protean_blob_styles)
	var/datum/protean_blob_style/picked = styles[choice]
	if(!picked)
		return
	if(istype(picked, /datum/protean_blob_style/layered))
		edit_layers(H, picked)
		return
	if(set_style(picked.id, H))
		refresh_if_worn(H)

/// Opens a layered style's layer menu; its answer walks on to the layer's states.
/datum/form/protean_blob/proc/edit_layers(mob/living/carbon/human/H, datum/protean_blob_style/layered/S)
	var/list/menu = list()
	for(var/datum/protean_blob_layer/L as anything in S.layers)
		if(L.editable)
			menu[L.label] = image(S.label_icon, L.label)
	menu["Import"] = image(S.label_icon, "Import")
	menu["Export"] = image(S.label_icon, "Export")
	open_request(src, /datum/prompt/choice/protean_layers, PROC_REF(layer_menu_chosen), answerer = H, choices = menu, anchor = H, radius = 60, style = S)

/datum/form/protean_blob/proc/layer_menu_chosen(datum/act/request/context)
	var/datum/prompt/choice/protean_layers/ask = context.request
	if(!context.answer || QDELETED(ask.style))
		return
	var/mob/living/carbon/human/H = ask.answerer
	var/datum/protean_blob_style/layered/S = ask.style
	var/choice = ask.value
	if(!choice || QDELETED(H) || H.incapacitated())
		return
	switch(choice)
		if("Export")
			to_chat(H, span_notice("Exported style string is \" [S.export_string(src)] \". Use this to get the same style in the future with Import."))
			if(set_style(S.id, H))
				refresh_if_worn(H)
			return
		if("Import")
			open_request(src, /datum/prompt/text/protean_style, PROC_REF(style_string_entered), answerer = H, style = S)
			return // The answer imports and wears the style.
	var/layer_index = 0
	for(var/i in 1 to length(S.layers))
		var/datum/protean_blob_layer/L = S.layers[i]
		if(L.label == choice)
			layer_index = i
			break
	if(!layer_index)
		return
	var/datum/protean_blob_layer/L = S.layers[layer_index]
	var/list/options = list()
	for(var/option in S.layer_options(L, H))
		options[option] = image(S.icon, option, dir = L.preview_dir, pixel_x = L.preview_pixel_x, pixel_y = L.preview_pixel_y)
	open_request(src, /datum/prompt/choice/protean_layer_state, PROC_REF(layer_state_chosen), answerer = H, choices = options, anchor = H, radius = 90, style = S, layer_index = layer_index)

/datum/form/protean_blob/proc/layer_state_chosen(datum/act/request/context)
	var/datum/prompt/choice/protean_layer_state/ask = context.request
	if(!context.answer || QDELETED(ask.style))
		return
	var/mob/living/carbon/human/H = ask.answerer
	var/datum/protean_blob_style/layered/S = ask.style
	var/new_state = ask.value
	if(!new_state || QDELETED(H) || H.incapacitated())
		return
	var/layer_index = ask.layer_index
	var/datum/protean_blob_layer/L = S.layers[layer_index]
	if(L.colorable)
		// The answer sets the layer, wears the style and refreshes the appearance.
		var/list/colors = colors_for(S)
		open_request(src, /datum/prompt/color/protean_layer, PROC_REF(layer_color_picked), answerer = H, question = "Pick [lowertext(L.label)] color:", title = "[L.label] Color", default = colors[layer_index], style = S, layer_index = layer_index, new_state = new_state)
		return
	set_layer(S, layer_index, new_state, "#FFFFFF")
	if(set_style(S.id, H))
		refresh_if_worn(H)

/// A layered style's layer menu; carries the style.
/datum/prompt/choice/protean_layers
	timeout = 0
	radial = TRUE
	autopick_single_option = TRUE
	var/datum/protean_blob_style/layered/style

CAPABILITIES(/datum/prompt/choice/protean_layers)
	ref_one(nameof(style), /datum/protean_blob_style/layered)

/datum/prompt/choice/protean_layers/prepare(datum/act/A)
	..()
	var/datum/protean_blob_style/layered/captured_style = style
	rel_clear(src, nameof(style))
	rel_set(src, nameof(style), captured_style)

/// A layer's state menu; carries the style and the layer.
/datum/prompt/choice/protean_layer_state
	timeout = 0
	radial = TRUE
	autopick_single_option = TRUE
	var/datum/protean_blob_style/layered/style
	var/layer_index

CAPABILITIES(/datum/prompt/choice/protean_layer_state)
	ref_one(nameof(style), /datum/protean_blob_style/layered)

/datum/prompt/choice/protean_layer_state/prepare(datum/act/A)
	..()
	var/datum/protean_blob_style/layered/captured_style = style
	rel_clear(src, nameof(style))
	rel_set(src, nameof(style), captured_style)

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
/datum/prompt/color/protean_blob
	timeout = 0
	ask_flags = ASK_CONSCIOUS
	var/highlight = FALSE

/// A layer's colour; carries the style, the layer and its new state. Re-checked: conscious.
/datum/prompt/color/protean_layer
	timeout = 0
	ask_flags = ASK_CONSCIOUS
	var/datum/protean_blob_style/layered/style
	var/layer_index
	var/new_state

CAPABILITIES(/datum/prompt/color/protean_layer)
	ref_one(nameof(style), /datum/protean_blob_style/layered)

/datum/prompt/color/protean_layer/prepare(datum/act/A)
	..()
	var/datum/protean_blob_style/layered/captured_style = style
	rel_clear(src, nameof(style))
	rel_set(src, nameof(style), captured_style)

/// Importing a style string into a layered style. Re-checked on the answer: conscious.
/datum/prompt/text/protean_style
	timeout = 0
	title = "Style loading"
	question = "Paste the style string you exported with Export."
	max_len = 240
	encode = FALSE
	ask_flags = ASK_CONSCIOUS
	var/datum/protean_blob_style/layered/style

CAPABILITIES(/datum/prompt/text/protean_style)
	ref_one(nameof(style), /datum/protean_blob_style/layered)

/datum/prompt/text/protean_style/prepare(datum/act/A)
	..()
	var/datum/protean_blob_style/layered/captured_style = style
	rel_clear(src, nameof(style))
	rel_set(src, nameof(style), captured_style)

/datum/form/protean_blob/proc/blob_color_picked(datum/act/request/context)
	var/datum/prompt/color/protean_blob/ask = context.request
	if(!context.answer)
		return
	if(!ask.value)
		return
	if(ask.highlight)
		color_highlight = ask.value
	else
		color_primary = ask.value
	refresh_if_worn(ask.answerer)

/datum/form/protean_blob/proc/layer_color_picked(datum/act/request/context)
	var/datum/prompt/color/protean_layer/ask = context.request
	if(!context.answer || QDELETED(ask.style))
		return
	if(!ask.value)
		return
	set_layer(ask.style, ask.layer_index, ask.new_state, ask.value)
	if(set_style(ask.style.id, ask.answerer))
		refresh_if_worn(ask.answerer)

/datum/form/protean_blob/proc/style_string_entered(datum/act/request/context)
	var/datum/prompt/text/protean_style/ask = context.request
	if(!context.answer || QDELETED(ask.style))
		return
	var/mob/living/carbon/human/H = ask.answerer
	var/datum/protean_blob_style/layered/S = ask.style
	var/text = sanitizeSafe(ask.value, 256)
	if(!text)
		return
	if(!S.import_string(src, H, text))
		to_chat(H, span_warning("That style string doesn't fit the [S.name] style."))
		return
	if(set_style(S.id, H))
		refresh_if_worn(H)
