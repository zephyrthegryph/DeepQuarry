/// Builds the property registry at boot and reports every validation error
/// (code/datums/properties/registry.dm). dq_property_registry_validates fails
/// the unit tests on any of them.
SUBSYSTEM_DEF(properties)
	name = "Properties"
	flags = SS_NO_FIRE

/datum/controller/subsystem/properties/Initialize()
	var/datum/property_registry/registry = dq_property_registry()
	if(!length(registry.errors))
		return SS_INIT_SUCCESS
	for(var/error in registry.errors)
		log_world("Property registry: [error]")
		stack_trace("Property registry: [error]")
	return SS_INIT_FAILURE
