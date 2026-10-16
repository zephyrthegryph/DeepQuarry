// Thermal shell policy: immutable declared heat coverage, with historical map/VV values.
STATIC_ENTRY(thermal_shell)
/proc/thermal_shell(insulation = null)
	return entry_make(ENTRY_THERMAL_SHELL, null, list("insulation" = insulation))
/datum/type_trait/thermal_shell
	var/insulation = 0
/datum/type_trait/thermal_shell/copy_values(datum/type_trait/thermal_shell/into)
	into.insulation = insulation
/datum/entry_engine/type_trait/thermal_shell
	kind = ENTRY_THERMAL_SHELL
	trait_type = /datum/type_trait/thermal_shell
	publish_key = THERMAL_SHELL_KEY
	base_type = /obj
	var_names = list("insulation" = "insulation")
// Instance accessor is for historical editable value visibility, not PROPERTY.
READS_AS(/proc/thermal_shell_of, THERMAL_SHELL_KEY)
/proc/thermal_shell_of(obj/O) as /datum/type_trait/thermal_shell
	READS_FROM(O)
	return type_trait_of(O, ENTRY_THERMAL_SHELL)
/proc/thermal_shell_of_type(path) as /datum/type_trait/thermal_shell
	READS_FROM()
	return type_trait_of_type(path, ENTRY_THERMAL_SHELL)
