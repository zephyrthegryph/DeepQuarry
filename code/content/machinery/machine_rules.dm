// Per-type rules of a machine: the machine_rules() type trait (doc/rewrite/proposals/base_vars.md). Declared in CAPABILITIES
// (configure(machine_rules(heat_dissipation = ...))), read with machine_rules_of(A).heat_dissipation, written at run time with set_<old var>().
//
//   heat_dissipation   conductance to its surroundings (null keeps the default)
//   maintenance_flags   which maintenance steps it takes

STATIC_ENTRY(machine_rules)

/proc/machine_rules(heat_dissipation = null, maintenance_flags = null, heat_output = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_MACHINE_RULES, null, list("heat_dissipation" = heat_dissipation, "maintenance_flags" = maintenance_flags, "heat_output" = heat_output))

/datum/type_trait/machine_rules
	var/heat_dissipation = null
	var/maintenance_flags = NONE
	var/heat_output = 0

/datum/type_trait/machine_rules/copy_values(datum/type_trait/machine_rules/into)
	into.heat_dissipation = heat_dissipation
	into.maintenance_flags = maintenance_flags
	into.heat_output = heat_output

/datum/entry_engine/type_trait/machine_rules
	kind = ENTRY_MACHINE_RULES
	trait_type = /datum/type_trait/machine_rules
	publish_key = MACHINE_RULES_KEY
	base_type = /obj/machinery
	var_names = list("heat_dissipation" = "heat_dissipation", "maintenance_flags" = "maintenance_flags", "heat_output" = "heat_output")

/// The holder's machine_rules values (its own once one was set at run time). Read only.
READS_AS(/proc/machine_rules_of, MACHINE_RULES_KEY)
/proc/machine_rules_of(obj/machinery/holder) as /datum/type_trait/machine_rules
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_MACHINE_RULES)

/// What a type declares (no instance): the old initial().
/proc/machine_rules_of_type(type) as /datum/type_trait/machine_rules
	READS_FROM() // declared per type: constant
	return type_trait_of_type(type, ENTRY_MACHINE_RULES)

/obj/machinery/proc/set_heat_dissipation(value)
	return set_trait(src, ENTRY_MACHINE_RULES, "heat_dissipation", value)

/obj/machinery/proc/set_maintenance_flags(value)
	return set_trait(src, ENTRY_MACHINE_RULES, "maintenance_flags", value)
