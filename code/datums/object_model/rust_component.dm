// Definition schema generated from #[vg::component]. No Rust or BYOND object
// references are stored in a definition. Converted atoms opt in explicitly.
/datum/object_model/rust_component
	var/domain
	var/domain_id
	var/kind
	var/dm_type
	/// field name -> role, unit, min, max, default, on_invalid.
	var/list/fields

/datum/object_model/rust_component/proc/validate_config(list/config, list/errors)
	for(var/key in config)
		var/list/field = fields[key]
		if(!field || field["role"] != "config")
			errors += "[type]: unknown config field [key]"
			continue
		var/value = config[key]
		var/value_type = field["value_type"]
		if(value_type == "bool")
			if(!isnum(value) || (value != TRUE && value != FALSE))
				errors += "[type]: [key] has the wrong value type"
		else if(value_type == "f32" || value_type == "f64")
			if(!isnum(value))
				errors += "[type]: [key] has the wrong value type"
				continue
			if((!isnull(field["min"]) && value < field["min"]) || (!isnull(field["max"]) && value > field["max"]))
				errors += "[type]: [key] is outside its declared range"
		else
			errors += "[type]: unsupported config value type [value_type]"
	for(var/key in fields)
		var/list/field = fields[key]
		if(field["role"] == "config" && !(key in config))
			config[key] = field["default"]

/// Generated per component. Returns the resulting entity handle or zero.
/datum/object_model/rust_component/proc/bind(atom/movable/entity, handle, list/config)
	return 0

/// Generated event ID -> object-model event adapter; opt-in until migration.
/datum/object_model/rust_component/proc/dispatch_event(atom/movable/entity, event_id)
	return

/proc/om_rust_component(path)
	RETURN_TYPE(/datum/object_model/rust_component)
	if(!ispath(path, /datum/object_model/rust_component))
		return null
	var/static/list/cache = list()
	var/datum/object_model/rust_component/C = cache[path]
	if(!C)
		C = new path
		cache[path] = C
	return C

/// Install every declared component on an existing or new entity. Probe each
/// domain first: matching components are adopted, empty slots are installed,
/// and conflicting kinds or stale handles leave the prior entity untouched.
/proc/om_rust_bind(atom/movable/entity)
	if(!entity || QDELETED(entity))
		return FALSE
	var/datum/object_model/archetype/A = om_archetype_for(entity.type, entity)
	if(!A || !length(A.components))
		return FALSE
	var/original_handle = entity.vg_entity
	var/handle = original_handle
	var/list/new_components = list()
	for(var/path in A.component_order)
		var/datum/object_model/rust_component/C = om_rust_component(path)
		var/installed = handle ? vg_entity_component_kind(handle, C.domain_id) : 0
		if(installed < 0 || (installed && installed != C.kind))
			return FALSE
	for(var/path in A.component_order)
		var/datum/object_model/rust_component/C = om_rust_component(path)
		if(handle && vg_entity_component_kind(handle, C.domain_id) == C.kind)
			continue
		var/new_handle = C.bind(entity, handle, A.components[path])
		if(!new_handle)
			if(handle)
				if(original_handle)
					for(var/index = length(new_components); index >= 1; index--)
						var/datum/object_model/rust_component/added = om_rust_component(new_components[index])
						vg_entity_detach_component(handle, added.domain_id, added.kind)
				else
					vg_entity_unbind(handle)
			return FALSE
		handle = new_handle
		new_components += path
	entity.vg_entity = handle
	return handle

/// Uses the existing entity unbind and SSvg index. Dematerialization sees 0.
/proc/om_rust_unbind(atom/movable/entity)
	if(!entity || !entity.vg_entity)
		return
	SSvg.unregister(entity)
	vg_entity_unbind(entity.vg_entity)
	entity.vg_entity = 0
