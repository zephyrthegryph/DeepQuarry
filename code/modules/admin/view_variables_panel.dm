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
	var/tmp/client/owner
	/// The datum or list currently being viewed.
	var/thing
	/// Saved ref string so refresh actions land on the same target.
	var/refid

/datum/view_variables_panel/New(client/owner_client)
	..()
	owner = owner_client // a client, not a datum: the client owns us by design (dq_vv_panel)

// clears the client's cached panel (clients aren't datums).

CAPABILITIES(/datum/view_variables_panel)
	interface("ViewVariables", title = "Variables", rights = R_HOLDER)
	op("refresh", ui_act("refresh"), then(PROC_REF(ui_act_refresh)))
	op("forward_topic", ui_act("forward_topic", arg("href", schema_text(4096))), then(PROC_REF(ui_act_forward_topic)))
	op("dropdown_select", ui_act("dropdown_select", arg("link", schema_text(4096))), then(PROC_REF(ui_act_dropdown_select)))

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

/datum/view_variables_panel/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["ref"] = refid
	var/list/merged_1 = ui_data_datum_view_variables_panel(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /datum/view_variables_panel's window data.
/datum/view_variables_panel/proc/ui_data_datum_view_variables_panel(mob/user, datum/tgui/ui, datum/tgui_state/state)
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
	data["ref_for_paste"] = "@[copytext(refid, 2, -1)]"
	data["title"] = "[thing] ([refid]) = [type_text]"

	// Atom-specific cords + sprite handling.
	if(isatom(thing))
		var/atom/AT = thing
		data["coords"] = list("x" = AT.x, "y" = AT.y, "z" = AT.z)
	else
		data["coords"] = null

	// Marker flags.
	var/datum/admins/holder = owner() ? owner().holder : null
	var/datum/thing_datum = is_listy ? null : thing
	data["marked"] = (holder && holder.marked_datum() == thing)
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

/datum/view_variables_panel/proc/ui_gate(datum/act/op/A)
	if(!owner())
		return FALSE
	return TRUE

/datum/view_variables_panel/proc/ui_act_refresh(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/datum/refresh_target = thing
	if(refresh_target && !QDELETED(refresh_target))
		owner().debug_variables(refresh_target, user)
	SStgui.update_uis(src)
	return TRUE

/datum/view_variables_panel/proc/ui_act_forward_topic(datum/act/op/A, href)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	// The variable HTML and dropdown links all use the byond:// scheme
	// dispatched through /client.Topic with _src_=vars (or _src_=holder
	// for some operations). dispatch_forwarded_topic mirrors what the
	// browser would do.
	dispatch_forwarded_topic(user, thing, "[href]")
	SStgui.update_uis(src)
	return TRUE

/datum/view_variables_panel/proc/ui_act_dropdown_select(datum/act/op/A, link)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	// React passes us the chosen option's link string verbatim. The
	// link is already a fully-formed byond:// querystring.
	var/href_str = "[link]"
	if(length(href_str))
		dispatch_forwarded_topic(user, thing, href_str)
		SStgui.update_uis(src)
	return TRUE

/client/proc/debug_variables(datum/thing in world, mob/requester)
	requester = requester || mob
	if(!requester?.client || !check_rights_for(requester.client, R_HOLDER))
		to_chat(requester, span_danger("You need to be an administrator to access this."), confidential = TRUE)
		return
	if(!thing)
		return
	if(isappearance(thing))
		thing = get_vv_appearance(thing)
	var/islist = islist(thing) || (!isdatum(thing) && hascall(thing, "Cut"))
	if(!islist && !isdatum(thing))
		return
	if(!dq_vv_panel)
		dq_vv_panel = new /datum/view_variables_panel(src) // ALLOW(ownership): /client is not a datum and is the one owner of this by design
	dq_vv_panel.thing = thing
	dq_vv_panel.refid = REF(thing)
	dq_vv_panel.tgui_interact(requester)
	SStgui.update_uis(dq_vv_panel)

/client/proc/vv_update_display(datum/thing, span, content)
	// Legacy callers ping us for live single-span updates. Since the
	// structured panel re-renders its full data shape per tgui_update, we
	// just trigger an update if the open VV is on this same target.
	if(!thing || QDELETED(thing) || !mob)
		return
	if(dq_vv_panel && dq_vv_panel.thing == thing)
		SStgui.update_uis(dq_vv_panel)


/// The client this panel belongs to.
/datum/view_variables_panel/proc/owner() as /client
	return owner

