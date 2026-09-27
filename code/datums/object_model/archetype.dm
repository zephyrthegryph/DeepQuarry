// Composition metadata lives here, not on every datum instance. Static
// declarations build production archetypes without constructing game objects.
/datum/proc/om_declare(datum/object_model/archetype/A)
	SHOULD_CALL_PARENT(TRUE)
	return

/datum/object_model/archetype
	var/entity_type
	var/list/behaviours = list() // behaviour path -> per-type config
	var/list/behaviour_order = list()
	var/list/components = list() // Rust component path -> per-type config
	var/list/component_order = list()
	var/list/slots = list() // name -> /datum/object_model/slot_def
	var/list/relations = list() // relation path -> required
	var/list/watches = list()
	var/list/rates = list()
	var/list/interactions = list()
	var/list/registries = list()
	var/list/caches = list() // compute proc name -> declared dependency metadata
	var/tracked_groups = 0 // scalar change groups explicitly protected by setters
	var/ledger_contribution_groups = 0 // tracked writes that change a slotted item's aggregate contribution
	var/ui_type
	var/list/ui_fragments = list()
	var/list/destruction
	var/list/event_handlers = list() // event path -> ordered behaviour paths
	/// Change bit -> ordered behaviours that should run after that write.
	var/list/run_change_handlers = new/list(24)
	var/list/run_event_handlers = list()
	var/list/errors = list()
	var/list/included_bundles = list()
	var/validated = FALSE

/datum/object_model/archetype/proc/add(path, list/config)
	if(ispath(path, /datum/object_model/rust_component))
		if(path in components)
			errors += "[entity_type]: duplicate Rust component [path]"
			return
		components[path] = config ? config.Copy() : list()
		component_order += path
		return
	if(!ispath(path, /datum/object_model/behaviour))
		errors += "[entity_type]: [path] is not a behaviour"
		return
	if(path in behaviours)
		errors += "[entity_type]: duplicate behaviour [path]"
		return
	behaviours[path] = config ? config.Copy() : list()
	behaviour_order += path

/datum/object_model/archetype/proc/configure(path, list/changes)
	var/list/config = ispath(path, /datum/object_model/rust_component) ? components[path] : behaviours[path]
	if(!config)
		errors += "[entity_type]: cannot configure missing behaviour [path]"
		return
	for(var/key in changes)
		config[key] = changes[key]

/datum/object_model/archetype/proc/remove(path)
	if(path in components)
		components -= path
		component_order -= path
		return
	if(!(path in behaviours))
		errors += "[entity_type]: cannot remove missing behaviour [path]"
		return
	behaviours -= path
	behaviour_order -= path

/datum/object_model/archetype/proc/include(path, list/params)
	if(path in included_bundles)
		errors += "[entity_type]: recursive or duplicate bundle [path]"
		return
	var/datum/object_model/bundle/B = om_bundle(path)
	if(!B)
		errors += "[entity_type]: unknown bundle [path]"
		return
	included_bundles += path
	B.apply(src, params || list())

/datum/object_model/archetype/proc/slot(name, accepts, capacity = 1, on_destroy)
	if(!istext(name) || !length(name) || slots[name])
		errors += "[entity_type]: invalid or duplicate slot [name]"
		return
	if(!ispath(accepts, /datum) || capacity < 1)
		errors += "[entity_type]: invalid slot [name] type or capacity"
		return
	var/datum/object_model/slot_def/S = new
	S.name = name
	S.accepts = accepts
	S.capacity = capacity
	S.on_destroy = on_destroy
	slots[name] = S

/datum/object_model/archetype/proc/relation(path, required = FALSE)
	if(path in relations)
		errors += "[entity_type]: duplicate relation [path]"
		return
	relations[path] = required ? TRUE : FALSE

/datum/object_model/archetype/proc/watch(path, list/config)
	if(!om_watch_definition(path) || (path in watches))
		errors += "[entity_type]: invalid or duplicate watch [path]"
		return
	if(config && ("dynamic_subject" in config))
		errors += "[entity_type]: dynamic watch subjects are not supported by A.watch; use a subscription"
		return
	watches[path] = config ? config.Copy() : list()

/// A converted type opts into only the groups backed by checked mutation APIs.
/datum/object_model/archetype/proc/track_changes(mask)
	if(!om_change_mask_valid(mask))
		errors += "[entity_type]: invalid tracked change mask [mask]"
		return
	tracked_groups |= mask

/// Only these producer groups can change the holder ledger's cached snapshot.
/// Keeping this explicit avoids recomputing properties for unrelated writes.
/datum/object_model/archetype/proc/ledger_contribution_changes(mask)
	if(!om_change_mask_valid(mask))
		errors += "[entity_type]: invalid ledger contribution change mask [mask]"
		return
	ledger_contribution_groups |= mask

/datum/object_model/archetype/proc/rate(name, minimum, maximum, list/thresholds, initial_value)
	if(!istext(name) || !length(name) || rates[name])
		errors += "[entity_type]: invalid or duplicate rate [name]"
		return
	if(!isnum(minimum) || !isnum(maximum) || minimum > maximum)
		errors += "[entity_type]: invalid bounds for rate [name]"
		return
	if(isnull(initial_value))
		initial_value = minimum
	if(!isnum(initial_value) || initial_value < minimum || initial_value > maximum)
		errors += "[entity_type]: invalid initial value for rate [name]"
		return
	for(var/crossing in thresholds)
		var/list/threshold = thresholds[crossing]
		if(!istext(crossing) || !length(crossing) || !islist(threshold) || length(threshold) != 2 || !(threshold[1] in list(REACT_CMP_ABOVE, REACT_CMP_BELOW)) || !isnum(threshold[2]) || threshold[2] < minimum || threshold[2] > maximum)
			errors += "[entity_type]: invalid threshold [crossing] for rate [name]"
			return
	rates[name] = list("min" = minimum, "max" = maximum, "initial" = initial_value, "thresholds" = thresholds ? thresholds.Copy() : null)

/datum/object_model/archetype/proc/interaction(path)
	if(!ispath(path, /datum/interaction) || ispath(path, /datum/interaction/construction))
		errors += "[entity_type]: invalid interaction [path]"
		return
	var/datum/interaction/interaction_path = path
	if(!initial(interaction_path.id))
		errors += "[entity_type]: interaction [path] has no id"
		return
	if(path in interactions)
		errors += "[entity_type]: duplicate interaction [path]"
		return
	interactions += path

/datum/object_model/archetype/proc/registry(path)
	if(!ispath(path, /datum/object_model/registry) || path == /datum/object_model/registry)
		errors += "[entity_type]: invalid registry [path]"
		return
	registries |= path

/// Declare a derived proc and the inputs that invalidate it. TYPE_PROC_REF
/// and NAMEOF keep author-facing proc/field names checked by the compiler.
/datum/object_model/archetype/proc/cache(compute_proc, list/fields, list/slots, list/relations)
	if(!istext(compute_proc) || !length(compute_proc) || (compute_proc in caches))
		errors += "[entity_type]: invalid or duplicate cache proc [compute_proc]"
		return
	var/list/channels = list()
	for(var/field in fields)
		if(!istext(field) || !length(field))
			errors += "[entity_type] [compute_proc]: invalid field dependency [field]"
			continue
		channels |= om_cache_field_channel(field)
	if(length(slots))
		channels |= "children"
	if(length(relations))
		channels |= "relations"
	caches[compute_proc] = list("fields" = fields?.Copy(), "slots" = slots?.Copy(), "relations" = relations?.Copy(), "channels" = channels)

/datum/object_model/archetype/proc/ui(path)
	ui_type = path

/datum/object_model/archetype/proc/ui_fragment(path, list/params)
	ui_fragments[path] = params ? params.Copy() : list()

/datum/object_model/archetype/proc/set_destroy_effects(list/effects)
	destruction = effects ? effects.Copy() : null

/datum/object_model/archetype/proc/validate()
	if(validated)
		return !length(errors)
	validated = TRUE
	if(ledger_contribution_groups & ~tracked_groups)
		errors += "[entity_type]: ledger contribution changes must be tracked groups"
	for(var/datum/object_model/registry/registry_path as anything in registries)
		if(!ispath(entity_type, initial(registry_path.accepts)))
			errors += "[entity_type]: registry [registry_path] does not accept this type"
	if(length(interactions) && !ispath(entity_type, /atom))
		errors += "[entity_type]: interactions require an atom type"
	for(var/interaction_path in interactions)
		if(!GLOB.interactions_by_type[interaction_path])
			errors += "[entity_type]: unregistered interaction [interaction_path]"
	for(var/relation_path in relations)
		var/datum/object_model/relation/relation_def = om_relation_def(relation_path)
		if(!relation_def || (!ispath(entity_type, relation_def.from_type) && !ispath(entity_type, relation_def.to_type)))
			errors += "[entity_type]: invalid relation [relation_path]"
			continue
		if(relations[relation_path] && (!ispath(entity_type, relation_def.from_type) || relation_def.virtual || !(relation_def.source_single || relation_def.shape == OM_REL_ONE_TO_ONE)))
			errors += "[entity_type]: required relation [relation_path] must be a stored, source-single relation"
	for(var/watch_path in watches)
		var/datum/object_model/watch_definition/watch_definition = om_watch_definition(watch_path)
		var/problem = watch_definition.validate_config(watches[watch_path])
		if(problem)
			errors += "[entity_type] [watch_path]: [problem]"
		if(watch_definition.relation_path)
			var/datum/object_model/relation/watched_relation = om_relation_def(watch_definition.relation_path)
			if(!watched_relation || !(watch_definition.relation_path in relations) || !ispath(entity_type, watched_relation.from_type) || !(watched_relation.source_single || watched_relation.shape == OM_REL_ONE_TO_ONE))
				errors += "[entity_type] [watch_path]: related watch needs a declared source-single outgoing relation"
	for(var/compute_proc in caches)
		var/list/cache_def = caches[compute_proc]
		if(!text2path("[entity_type]/proc/[compute_proc]"))
			errors += "[entity_type]: missing cache compute proc [compute_proc]"
		for(var/slot_id in cache_def["slots"])
			if(!slots[slot_id])
				errors += "[entity_type] [compute_proc]: unknown slot dependency [slot_id]"
		for(var/relation_path in cache_def["relations"])
			if(!om_relation_def(relation_path))
				errors += "[entity_type] [compute_proc]: invalid relation dependency [relation_path]"
	om_sort_behaviours()
	var/list/component_domains = list()
	for(var/component_path in component_order)
		var/datum/object_model/rust_component/C = om_rust_component(component_path)
		if(!C || !ispath(entity_type, C.dm_type))
			errors += "[entity_type]: Rust component [component_path] does not apply to this type"
			continue
		if(component_domains[C.domain])
			errors += "[entity_type]: multiple Rust components in domain [C.domain]"
		else
			component_domains[C.domain] = component_path
		C.validate_config(components[component_path], errors)
	for(var/path in behaviour_order)
		var/datum/object_model/behaviour/B = om_behaviour(path)
		var/list/config = behaviours[path]
		B.validate_config(config, errors)
		if(B.run_clock && !ispath(B.run_clock, /datum/object_model/clock_domain))
			errors += "[entity_type] [path]: invalid scheduled clock [B.run_clock]"
		if(B.run_set && !ispath(B.run_set, /datum/object_model/schedule_set))
			errors += "[entity_type] [path]: invalid scheduled set [B.run_set]"
		if(B.run_shared_cadence && (B.run_period <= 0 || B.run_clock))
			errors += "[entity_type] [path]: shared cadence requires a positive world-time period"
		if(B.run_change_mask && (!om_change_mask_valid(B.run_change_mask) || (B.run_change_mask & ~tracked_groups)))
			errors += "[entity_type] [path]: scheduled changes must be declared tracked groups"
		if(!isnum(B.run_period) || B.run_period < 0 || (B.period > 0 && (B.run_period > 0 || B.run_change_mask || length(B.run_owned_inputs) || length(B.run_relation_inputs) || length(B.run_events))))
			errors += "[entity_type] [path]: invalid or conflicting scheduled period"
		for(var/event_path in B.run_events)
			if(!om_event(event_path))
				errors += "[entity_type] [path]: invalid scheduled event [event_path]"
				continue
			if(!run_event_handlers[event_path])
				run_event_handlers[event_path] = list()
			run_event_handlers[event_path] += path
		if(B.run_change_mask)
			var/bit = 1
			for(var/index in 1 to 24)
				if(B.run_change_mask & bit)
					if(!run_change_handlers[index])
						run_change_handlers[index] = list()
					run_change_handlers[index] += path
				bit *= 2
		for(var/list/input as anything in B.run_owned_inputs)
			if(length(input) != 2 || !(input[1] in slots) || !om_change_mask_valid(input[2]))
				errors += "[entity_type] [path]: invalid owned scheduled input"
		for(var/list/input as anything in B.run_relation_inputs)
			var/datum/object_model/relation/input_relation = om_relation_def(input[1])
			if(length(input) != 3 || !input_relation || !(input[1] in relations) || !(input[2] in list(OM_READ_INCOMING, OM_READ_OUTGOING)) || !om_change_mask_valid(input[3]) || (input[2] == OM_READ_OUTGOING && !ispath(entity_type, input_relation.from_type)) || (input[2] == OM_READ_INCOMING && !ispath(entity_type, input_relation.to_type)))
				errors += "[entity_type] [path]: invalid related scheduled input"
		om_validate_observer_plan(B.om_observer_plan(), entity_type, errors)
		if(B.derived_input_mask && (B.derived_input_mask & ~tracked_groups))
			errors += "[entity_type] [path]: derived input reads undeclared local change groups"
		for(var/list/input as anything in B.derived_owned_inputs)
			if(length(input) != 2 || !(input[1] in slots) || !om_change_mask_valid(input[2]))
				errors += "[entity_type] [path]: invalid owned derived input"
		for(var/list/input as anything in B.derived_relation_inputs)
			var/datum/object_model/relation/input_relation = om_relation_def(input[1])
			if(length(input) != 3 || !input_relation || !(input[1] in relations) || !(input[2] in list(OM_READ_INCOMING, OM_READ_OUTGOING)) || !om_change_mask_valid(input[3]) || (input[2] == OM_READ_OUTGOING && !ispath(entity_type, input_relation.from_type)) || (input[2] == OM_READ_INCOMING && !ispath(entity_type, input_relation.to_type)))
				errors += "[entity_type] [path]: invalid related derived input"
		if(B.states)
			if(!(B.initial_state in B.states))
				errors += "[entity_type] [path]: initial state is not declared"
			for(var/old_state in B.transitions)
				if(!(old_state in B.states))
					errors += "[entity_type] [path]: undeclared state [old_state] has transitions"
				for(var/new_state in B.transitions[old_state])
					if(!(new_state in B.states))
						errors += "[entity_type] [path]: transition targets undeclared state [new_state]"
		for(var/key in config)
			var/problem = B.validate_value(key, config[key])
			if(problem)
				errors += "[entity_type] [path] [key]: [problem]"
		for(var/required_path in B.requires_behaviour)
			if(!(required_path in behaviours))
				errors += "[entity_type] [path] needs behaviour [required_path]"
		for(var/excluded_path in B.excludes)
			if(excluded_path in behaviours)
				errors += "[entity_type] [path] excludes behaviour [excluded_path]"
		for(var/interface_path in B.provides)
			var/datum/object_model/interface/provided_interface = om_interface(interface_path)
			if(!provided_interface)
				errors += "[entity_type] [path] provides invalid interface [interface_path]"
				continue
			var/provider_problem = provided_interface.validate_provider(B)
			if(provider_problem)
				errors += "[entity_type] [path] does not provide [interface_path]: [provider_problem]"
		for(var/interface_path in B.needs)
			if(!om_interface(interface_path))
				errors += "[entity_type] [path] needs invalid interface [interface_path]"
				continue
			var/found = FALSE
			for(var/provider_path in behaviour_order)
				var/datum/object_model/behaviour/provider = om_behaviour(provider_path)
				if(provider.provides && (interface_path in provider.provides))
					found = TRUE
					break
			if(!found)
				errors += "[entity_type] [path] needs interface [interface_path]"
		for(var/requirement_path in B.requires)
			var/datum/object_model/requirement/R = om_requirement(requirement_path)
			if(!R)
				errors += "[entity_type] [path] has unknown requirement [requirement_path]"
			else if(R.change_mask && (!om_change_mask_valid(R.change_mask) || (R.change_mask & ~tracked_groups)))
				errors += "[entity_type] [path] requirement [requirement_path] watches undeclared change groups"
		for(var/event_path in B.events)
			if(!om_event(event_path))
				errors += "[entity_type] [path] has unknown event [event_path]"
				continue
			var/list/handlers = event_handlers[event_path]
			if(!handlers)
				handlers = list()
				event_handlers[event_path] = handlers
			handlers += path
	return !length(errors)

/// Stable topological order. Declaration order wins when no edge constrains it.
/datum/object_model/archetype/proc/om_sort_behaviours()
	var/list/incoming = list()
	var/list/outgoing = list()
	for(var/path in behaviour_order)
		incoming[path] = 0
		outgoing[path] = list()
	for(var/path in behaviour_order)
		var/datum/object_model/behaviour/B = om_behaviour(path)
		for(var/prior in B.after)
			if(!(prior in behaviours))
				errors += "[entity_type] [path] orders after missing behaviour [prior]"
				continue
			var/list/prior_next = outgoing[prior]
			if(!(path in prior_next))
				prior_next += path
				incoming[path]++
		for(var/later in B.before)
			if(!(later in behaviours))
				errors += "[entity_type] [path] orders before missing behaviour [later]"
				continue
			var/list/path_next = outgoing[path]
			if(!(later in path_next))
				path_next += later
				incoming[later]++
	var/list/sorted = list()
	while(length(sorted) < length(behaviour_order))
		var/chosen
		for(var/path in behaviour_order)
			if(!(path in sorted) && incoming[path] == 0)
				chosen = path
				break
		if(!chosen)
			errors += "[entity_type]: behaviour ordering cycle"
			return
		sorted += chosen
		for(var/next_path in outgoing[chosen])
			incoming[next_path]--
	behaviour_order = sorted

/datum/object_model/archetype/proc/behaviour_ready(datum/source, datum/object_model/behaviour/B)
	if(!om_required_relations_ready(source, src))
		return FALSE
	for(var/requirement_path in B.requires)
		var/datum/object_model/requirement/R = om_requirement(requirement_path)
		if(R.why_not(source))
			return FALSE
	return TRUE

/// Required relations gate behaviour work until their partner is linked.
/// The relation remains a live dependency, so losing it deactivates work.
/proc/om_required_relations_ready(datum/entity, datum/object_model/archetype/A)
	if(!A)
		return TRUE
	for(var/relation_path in A.relations)
		if(A.relations[relation_path] && !om_first_linked(entity, relation_path))
			return FALSE
	return TRUE

/datum/object_model/slot_def
	var/name
	var/accepts
	var/capacity
	var/on_destroy

/// Side-effect-free DEF route for mapped prefabs. A declaration type is
/// discovered and validated without constructing the target atom.
/datum/object_model/declaration
	var/target_type

/datum/object_model/declaration/proc/build(datum/object_model/archetype/A)
	return

/proc/om_declarations()
	var/static/list/registry
	if(registry)
		return registry
	registry = list()
	for(var/datum/object_model/declaration/path as anything in subtypesof(/datum/object_model/declaration))
		if(!initial(path.target_type))
			continue
		var/datum/object_model/declaration/D = new path
		if(registry[D.target_type])
			CRASH("duplicate object-model declaration for [D.target_type]")
		registry[D.target_type] = D
	return registry

/// Find the nearest static declaration without constructing the entity.
/proc/om_declaration_for(path)
	var/list/declarations = om_declarations()
	for(var/datum/candidate = path; candidate && ispath(candidate, /datum); candidate = initial(candidate.parent_type))
		var/datum/object_model/declaration/D = declarations[candidate]
		if(D)
			return D
	return null

/// Apply static builders base-first, matching the parent-chain semantics of
/// om_declare() without constructing any entity in the chain.
/proc/om_declaration_lineage_for(path)
	var/list/lineage = list()
	var/list/declarations = om_declarations()
	for(var/datum/candidate = path; candidate && ispath(candidate, /datum); candidate = initial(candidate.parent_type))
		var/datum/object_model/declaration/D = declarations[candidate]
		if(D)
			lineage.Insert(1, D)
	return lineage

/// Safe CI/boot validation for every static declaration. Inherited subtypes
/// use the nearest declaration; CI rejects production om_declare overrides.
/proc/om_validate_declarations()
	var/list/failures = list()
	for(var/path in om_declarations())
		var/datum/object_model/archetype/A = om_archetype_for(path)
		if(!A)
			failures += "[path]: no archetype"
		else if(length(A.errors))
			failures += A.errors
	return failures

/// Pass an existing instance on cache miss. No arbitrary atom is constructed
/// for validation: constructors can have world effects.
/proc/om_archetype_for(path, datum/sample)
	var/static/list/cache = list()
	var/datum/object_model/archetype/A = cache[path]
	if(A)
		return A
	var/list/lineage = om_declaration_lineage_for(path)
	if(!length(lineage) && (!sample || sample.type != path))
		return null
	A = new
	A.entity_type = path
	if(length(lineage))
		for(var/datum/object_model/declaration/D in lineage)
			D.build(A)
	else
		sample.om_declare(A)
	if(!A.validate())
		CRASH("object-model archetype [path]: [jointext(A.errors, "; ")]")
	cache[path] = A
	return A
