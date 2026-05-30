// View Variables — structured TGUI replacement for the legacy 320-line
// debug_variables HTML panel.

ADMIN_VERB_AND_CONTEXT_MENU(debug_variables, (R_DEBUG|R_SERVER|R_ADMIN|R_SPAWN|R_FUN|R_EVENT), "View Variables", "View the variables of a datum.", "Debug.Investigate", datum/thing in world)
	user.debug_variables(thing)
//
// Structured chrome: typed header (sprite, type, refs, marker flags,
// coords), dropdown options, search box (client-side React filter),
// refresh. The per-variable rendering still goes through the legacy
// vv_get_var() override chain (each type defines its own value/edit-link
// HTML), so the panel ships per-variable `value_html` strings rendered
// through HtmlRenderer with forwardTopic for the E/C/M / Mass-modify
// click handlers. This avoids re-implementing dozens of type-specific
// overrides while still giving the chrome a real component model.

/client
	/// Cached VV panel datum, lazily created the first time debug_variables runs.
	var/datum/view_variables_panel/dq_vv_panel

/datum/view_variables_panel
	var/client/owner
	/// The datum or list currently being viewed.
	var/thing
	/// Saved ref string so refresh actions land on the same target.
	var/refid

/datum/view_variables_panel/New(client/owner_client)
	owner = owner_client

/datum/view_variables_panel/Destroy(force, ...)
	if(owner)
		owner.dq_vv_panel = null
	owner = null
	thing = null
	return ..()

/datum/view_variables_panel/tgui_state(mob/user)
	return ADMIN_STATE(R_HOLDER)

/datum/view_variables_panel/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ViewVariables", "Variables")
		ui.open()

/// Parses the legacy "<option value='[link]'>[name]</option>" strings into
/// typed (name, link) records. Separator rows ("---") and the empty-link
/// "Select option" placeholder are tagged with is_separator/is_placeholder.
/datum/view_variables_panel/proc/parse_dropdown_options(list/raw_options)
	var/list/out = list()
	for(var/raw in raw_options)
		var/text = "[raw]"
		if(!length(text))
			continue
		// "<option value='LINK'>NAME</option>" or "<option value selected>NAME</option>"
		var/name_start = findtext(text, ">")
		var/name_end = findtext(text, "</option>")
		var/name = (name_start && name_end) ? copytext(text, name_start + 1, name_end) : text
		var/link = ""
		var/value_start = findtext(text, "value='")
		if(value_start)
			var/link_start = value_start + 7
			var/link_end = findtext(text, "'", link_start)
			if(link_end)
				link = copytext(text, link_start, link_end)
		out += list(list(
			"name" = name,
			"link" = link,
			"is_separator" = (name == "---"),
		))
	return out

/datum/view_variables_panel/tgui_data(mob/user)
	var/list/data = list()
	data["has_target"] = !!thing
	if(!thing)
		return data
	var/is_listy = islist(thing) || (!isdatum(thing) && hascall(thing, "Cut"))
	data["is_list"] = !!is_listy
	var/datum/maybe_datum = is_listy ? null : thing
	var/type_text
	if(is_listy)
		type_text = "/list"
	else
		type_text = "[maybe_datum.type]"
	data["type"] = type_text
	data["ref"] = refid
	data["ref_for_paste"] = "@[copytext(refid, 2, -1)]"
	data["title"] = "[thing] ([refid]) = [type_text]"

	// Atom-specific cords + sprite handling.
	if(isatom(thing))
		var/atom/AT = thing
		data["coords"] = list("x" = AT.x, "y" = AT.y, "z" = AT.z)
	else
		data["coords"] = null

	// Marker flags.
	var/datum/admins/holder = owner ? owner.holder : null
	var/datum/thing_datum = is_listy ? null : thing
	data["marked"] = (holder && holder.marked_datum == thing)
	data["tagged_index"] = (holder && LAZYFIND(holder.tagged_datums, thing)) || 0
	data["varedited"] = (thing_datum && (thing_datum.datum_flags & DF_VAR_EDITED))
	data["gc_destroyed"] = (thing_datum && thing_datum.gc_destroyed)

	// Header text from vv_get_header() for datums (lists have no header).
	if(is_listy)
		data["header"] = list("<b>/list</b>")
	else
		data["header"] = thing_datum.vv_get_header()

	// Dropdown options.
	var/list/raw_dropdown
	if(is_listy)
		raw_dropdown = list(
			"---",
			"<option value='[VV_HREF_TARGETREF_INTERNAL(refid, VV_HK_LIST_ADD)]'>Add Item</option>",
			"<option value='[VV_HREF_TARGETREF_INTERNAL(refid, VV_HK_LIST_ERASE_NULLS)]'>Remove Nulls</option>",
			"<option value='[VV_HREF_TARGETREF_INTERNAL(refid, VV_HK_LIST_ERASE_DUPES)]'>Remove Dupes</option>",
			"<option value='[VV_HREF_TARGETREF_INTERNAL(refid, VV_HK_LIST_SET_LENGTH)]'>Set len</option>",
			"<option value='[VV_HREF_TARGETREF_INTERNAL(refid, VV_HK_LIST_SHUFFLE)]'>Shuffle</option>",
			"<option value='[VV_HREF_TARGETREF_INTERNAL(refid, VV_HK_EXPOSE)]'>Show VV To Player</option>",
			"---",
		)
		data["dropdown"] = parse_dropdown_options(raw_dropdown)
	else
		data["dropdown"] = parse_dropdown_options(thing_datum.vv_get_dropdown())

	// Variable list. Each entry's value_html comes from the legacy
	// vv_get_var() / debug_variable() chain — we keep its rendering since
	// reimplementing per-type would require rewriting dozens of overrides.
	var/list/variables = list()
	if(is_listy)
		var/list/list_value = thing
		for(var/i in 1 to list_value.len)
			var/key = list_value[i]
			var/value
			if(IS_NORMAL_LIST(list_value) && IS_VALID_ASSOC_KEY(key))
				value = list_value[key]
			var/value_html = debug_variable(i, value, 0, list_value)
			variables += list(list(
				"index" = i,
				"name" = "[key]",
				"value_html" = "[value_html]",
			))
	else
		var/list/names = list()
		for(var/varname in thing_datum.vars)
			names += varname
		names = sortList(names)
		for(var/varname in names)
			if(thing_datum.can_vv_get(varname))
				variables += list(list(
					"name" = varname,
					"value_html" = "[thing_datum.vv_get_var(varname)]",
				))
	data["variables"] = variables

	return data

/datum/view_variables_panel/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	if(!owner)
		return
	switch(action)
		if("refresh")
			var/datum/refresh_target = thing
			if(refresh_target && !QDELETED(refresh_target))
				owner.debug_variables(refresh_target)
			SStgui.update_uis(src)
			return TRUE
		if("forward_topic")
			// The variable HTML and dropdown links all use the byond:// scheme
			// dispatched through /client.Topic with _src_=vars (or _src_=holder
			// for some operations). dispatch_forwarded_topic mirrors what the
			// browser would do.
			dispatch_forwarded_topic(ui.user, thing, "[params["href"]]")
			SStgui.update_uis(src)
			return TRUE
		if("dropdown_select")
			// React passes us the chosen option's link string verbatim. The
			// link is already a fully-formed byond:// querystring.
			var/href_str = "[params["link"]]"
			if(length(href_str))
				dispatch_forwarded_topic(ui.user, thing, href_str)
				SStgui.update_uis(src)
			return TRUE

/client/proc/debug_variables(datum/thing in world)
	if(!usr.client || !check_rights_for(usr.client, R_HOLDER))
		to_chat(usr, span_danger("You need to be an administrator to access this."), confidential = TRUE)
		return
	if(!thing)
		return
	if(isappearance(thing))
		thing = get_vv_appearance(thing)
	var/islist = islist(thing) || (!isdatum(thing) && hascall(thing, "Cut"))
	if(!islist && !isdatum(thing))
		return
	if(!dq_vv_panel)
		dq_vv_panel = new(src)
	dq_vv_panel.thing = thing
	dq_vv_panel.refid = REF(thing)
	dq_vv_panel.tgui_interact(usr)
	SStgui.update_uis(dq_vv_panel)

/client/proc/vv_update_display(datum/thing, span, content)
	// Legacy callers ping us for live single-span updates. Since the
	// structured panel re-renders its full data shape per tgui_update, we
	// just trigger an update if the open VV is on this same target.
	if(!thing || QDELETED(thing) || !mob)
		return
	if(dq_vv_panel && dq_vv_panel.thing == thing)
		SStgui.update_uis(dq_vv_panel)
