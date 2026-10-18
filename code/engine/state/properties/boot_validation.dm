/// Builds the property registry at boot and compiles every rule against it, and reports every validation error (code/datums/properties/).
/// SSatoms calls it after the map's atoms initialize (fold wave F4; was SSproperties).
/// Property and rule validation fail the
/// unit tests on any of them. Returns TRUE when everything validated.
/proc/validate_property_registry()
	var/datum/property_registry/registry = dq_property_registry()
	var/list/errors = registry.errors.Copy()
	for(var/error in errors)
		log_world("Property registry: [error]")
		stack_trace("Property registry: [error]")
	var/list/rule_errors = property_environment().validate_rules()
	for(var/error in rule_errors)
		log_world("Rules: [error]")
		stack_trace("Rules: [error]")
	var/total = length(errors) + length(rule_errors)
	log_world("Property registry validated: [total] error\s.")
	return !total
