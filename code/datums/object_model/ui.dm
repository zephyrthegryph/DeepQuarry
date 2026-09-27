// Server-side adapter for declaration-driven tgui interfaces. Definitions are
// shared; a session is sparse and exists only while a UI is open.
/datum/object_model/ui
	var/interface
	var/title
	var/list/actions // action name -> parameter schema
	var/list/data_schema // generated data key -> leaf schema
	var/list/requirements // action name -> requirement paths

/datum/object_model/ui/proc/data(datum/source, mob/user, datum/object_model/ui_data/D)
	return

/datum/object_model/ui/proc/can_see(datum/source, mob/user)
	return TRUE

/datum/object_model/ui/proc/can_act(datum/source, mob/user, action, list/params)
	return TRUE

/datum/object_model/ui/proc/act(datum/source, mob/user, action, list/params)
	return FALSE

/proc/om_ui_definition(path)
	if(!ispath(path, /datum/object_model/ui))
		return null
	var/static/list/definitions = list()
	var/datum/object_model/ui/definition = definitions[path]
	if(!definition)
		definition = new path
		definitions[path] = definition
	return definition

/datum/object_model/ui/proc/why_not(datum/source, mob/user, action, list/params)
	if(!can_see(source, user) || !can_act(source, user, action, params))
		return "That action is unavailable"
	var/list/needed = requirements?[action]
	for(var/path in needed)
		var/datum/object_model/requirement/R = om_requirement(path)
		if(!R)
			return "Unknown requirement [path]"
		var/reason = R.why_not(source, user)
		if(reason)
			return reason
	return null

/datum/object_model/ui_data
	var/list/values = list()
	var/list/schema
	var/valid = TRUE

/datum/object_model/ui_data/New(list/schema)
	. = ..()
	src.schema = schema

/datum/object_model/ui_data/proc/put(key, value)
	if(schema && !(key in schema))
		valid = FALSE
		return FALSE
	if(schema)
		var/list/spec = schema[key]
		var/type_name = spec["type"]
		if((type_name == "number" && !isnum(value)) || (type_name == "text" && !istext(value)) || (type_name == "boolean" && value != TRUE && value != FALSE))
			valid = FALSE
			return FALSE
		if((type_name == "number" && ((!isnull(spec["min"]) && value < spec["min"]) || (!isnull(spec["max"]) && value > spec["max"]))) || (type_name == "text" && !isnull(spec["max"]) && length(value) > spec["max"]))
			valid = FALSE
			return FALSE
		if(spec["values"] && !(value in spec["values"]))
			valid = FALSE
			return FALSE
	values[key] = value
	return TRUE

/datum/object_model/ui_data/proc/complete()
	if(!valid)
		return FALSE
	for(var/key in schema)
		var/list/spec = schema[key]
		if(!spec["optional"] && !(key in values))
			return FALSE
	return TRUE

// The source owns the session; this edge also ends it when its viewer dies.
/datum/object_model/relation/ui_viewer
	from_type = /mob
	to_type = /datum/object_model/ui_session
	shape = OM_REL_ONE_TO_MANY
	on_end_lost = OM_REL_DESTROY_TARGET

// Schema leaf: "number", "text", or "boolean"; optionally a list with
// "type", "min", "max", and "values". Unknown keys are never forwarded.
/proc/om_ui_params(list/schema, list/raw)
	var/list/clean = list()
	if(!schema)
		return (!raw || !length(raw)) ? clean : null
	for(var/key in schema)
		var/spec = schema[key]
		var/type_name = islist(spec) ? spec["type"] : spec
		var/value = raw?[key]
		if(isnull(value))
			if(islist(spec) && spec["optional"])
				continue
			return null
		switch(type_name)
			if("number")
				if(!isnum(value) && !(istext(value) && length(value) && isnum(text2num(value))))
					return null
				value = isnum(value) ? value : text2num(value)
				if(islist(spec) && ((!isnull(spec["min"]) && value < spec["min"]) || (!isnull(spec["max"]) && value > spec["max"])))
					return null
			if("text")
				if(!istext(value))
					return null
				if(islist(spec) && !isnull(spec["max"]) && length(value) > spec["max"])
					return null
			if("boolean")
				if(!(value == TRUE || value == FALSE))
					return null
			else
				return null
		if(islist(spec) && spec["values"] && !(value in spec["values"]))
			return null
		clean[key] = value
	return clean

/datum/object_model/ui_session
	var/datum/source
	var/mob/user
	var/datum/object_model/ui/definition

/datum/object_model/ui_session/New(datum/source, mob/user, datum/object_model/ui/definition)
	. = ..()
	src.source = source
	src.user = user
	src.definition = definition

/datum/object_model/ui_session/Destroy()
	SStgui.close_uis(src)
	source = null
	user = null
	definition = null
	return ..()

/datum/object_model/ui_session/tgui_close(mob/viewer)
	. = ..()
	if(viewer == user && !QDELETED(src))
		om_release(src)
		qdel(src)

/datum/object_model/ui_session/tgui_host(mob/viewer)
	return source ? source.tgui_host(viewer) : src

/datum/object_model/ui_session/tgui_state(mob/viewer)
	return source ? source.tgui_state(viewer) : ..()

/datum/object_model/ui_session/tgui_interact(mob/viewer, datum/tgui/ui, datum/tgui/parent_ui)
	if(viewer != user || !source || QDELETED(source) || !definition?.can_see(source, viewer))
		return FALSE
	ui = SStgui.try_update_ui(viewer, src, ui)
	if(!ui)
		ui = new(viewer, src, definition.interface, definition.title, parent_ui)
		ui.open()
	return TRUE

/datum/object_model/ui_session/tgui_data(mob/viewer, datum/tgui/ui, datum/tgui_state/state)
	var/list/result = list()
	if(viewer != user || !source || QDELETED(source) || !definition?.can_see(source, viewer))
		return result
	var/datum/object_model/ui_data/D = new(definition.data_schema)
	definition.data(source, viewer, D)
	if(!D.complete())
		qdel(D)
		return result
	result = D.values
	result["revision"] = source.om_state?.revision || 0
	var/list/can = list()
	for(var/action in definition.actions)
		can[action] = definition.why_not(source, viewer, action)
	result["can"] = can
	qdel(D)
	return result

/datum/object_model/ui_session/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE
	if(!ui || ui.user != user || ui.status != STATUS_INTERACTIVE)
		return FALSE
	return dispatch(action, params)

/datum/object_model/ui_session/proc/dispatch(action, list/params)
	if(!source || QDELETED(source) || !user || QDELETED(user) || !definition || !params)
		return FALSE
	if(!(action in definition.actions))
		return FALSE
	var/list/schema = definition.actions[action]
	var/revision = source.om_state?.revision || 0
	if(isnull(params?["revision"]) || text2num("[params["revision"]]") != revision)
		return FALSE
	var/list/raw = params.Copy()
	raw -= "revision"
	var/list/clean = om_ui_params(schema, raw)
	if(!clean || definition.why_not(source, user, action, clean))
		return FALSE
	if(!definition.act(source, user, action, clean))
		return FALSE
	om_bump_revision(source)
	om_changed(source)
	SStgui.update_uis(src)
	return TRUE

/proc/om_ui_open(datum/source, mob/user, datum/tgui/parent_ui)
	if(!source || !user || QDELETED(source) || QDELETED(user))
		return null
	var/datum/object_model/archetype/A = om_archetype_for(source.type, source)
	if(!A?.ui_type || !ispath(A.ui_type, /datum/object_model/ui))
		return null
	var/datum/object_model/ui/definition = om_ui_definition(A.ui_type)
	if(!definition.interface || !definition.can_see(source, user))
		return null
	var/datum/object_model/ui_session/session = new(source, user, definition)
	if(!om_claim(source, "om:ui", session))
		qdel(session)
		return null
	if(!om_link(user, /datum/object_model/relation/ui_viewer, session))
		om_release(session)
		qdel(session)
		return null
	if(!session.tgui_interact(user, null, parent_ui))
		om_release(session)
		qdel(session)
		return null
	return session
