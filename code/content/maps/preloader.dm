GLOBAL_VAR_INIT(use_preloader, FALSE)
GLOBAL_VAR_INIT(_preloader_path, null)
GLOBAL_LIST_EMPTY(_preloader_attributes)

/world/proc/preloader_setup(list/the_attributes, path)
	if(LAZYLEN(the_attributes))
		GLOB.use_preloader = TRUE
		GLOB._preloader_attributes = the_attributes
		GLOB._preloader_path = path

/world/proc/preloader_load(atom/what)
	GLOB.use_preloader = FALSE
	var/list/attributes = GLOB._preloader_attributes
	for(var/attribute in attributes)
		var/value = attributes[attribute]
		if(islist(value))
			value = deepCopyList(value)
		#ifdef TESTING
		if(what.vars[attribute] == value)
			var/message = span_green("[what.type]") + " at [AREACOORD(what)] - " + span_bold("VAR:") + " " + span_red("[attribute] = [isnull(value) ? "null" : (isnum(value) ? value : "\"[value]\"")]")
			world.log << "DIRTY VAR: [message]"
			// dirty_vars += message
		#endif
		if(!(attribute in what.vars))
			// A var that left the base type for a trait block (a mixer's active_power_usage): the edit goes to the holder's own trait.
			var/list/trait_field = type_trait_field_for_var(what, attribute)
			if(trait_field)
				set_trait(what, trait_field[1], trait_field[2], value)
				continue
			if(map_edit_moved_var(what, attribute, value))
				continue
			stack_trace("map edit of unknown var [attribute] on [what.type]")
			continue
		what.vars[attribute] = value // ALLOW(api): map loader: DMM var overrides

/// A var that left the atom for another home but keeps its map edits: a lazy state field, the glow, the emag state. TRUE when the edit landed.
/// tools/analyze/src/lints/map_edits.rs names the same vars, so an edit of anything else fails the gate before the map is ever loaded.
/world/proc/map_edit_moved_var(atom/what, attribute, value)
	var/slot = vv_slot_named(what, attribute)
	if(slot)
		vv_slot_write(what, slot, value)
		return TRUE
	switch(attribute)
		if("light_range")
			set_glow(what, GLOW(value, null, null))
			return TRUE
		if("light_power")
			set_glow(what, GLOW(null, value, null))
			return TRUE
		if("light_color")
			set_glow(what, GLOW(null, null, value))
			return TRUE
		if("emagged")
			return value ? map_edit_set_emagged(what) : TRUE
		if("cap_state")
			return (value & CAP_EMAGGED) ? map_edit_set_emagged(what) : TRUE
		if("req_access_txt", "req_one_access_txt")
			// The old text form; "0" meant no requirement. The one kind of map left using it writes "0" beside a real req_access list.
			if(value == "0" || !length("[value]"))
				return TRUE
			var/list/ids = list()
			for(var/id in splittext("[value]", ";"))
				ids += text2num(id)
			var/obj/holder = what
			if(attribute == "req_access_txt")
				holder.set_req_access(ids)
			else
				holder.set_req_one_access(ids)
			return TRUE
	return FALSE

/// A map that places something already subverted (a derelict's hacked vendor) sets the generic bit is_emagged() reads.
/world/proc/map_edit_set_emagged(atom/what)
	cap_set(what, CAP_EMAGGED, TRUE)
	return TRUE

/area/template_noop
	name = "Area Passthrough"

/turf/template_noop
	name = "Turf Passthrough"
	icon_state = "template_void"
