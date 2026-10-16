STATIC_ENTRY(machine_interaction_config)

/proc/machine_interaction_config(clicksound = null, clickvol = null, interact_offline = null, maintenance_wrench_time = null, maintenance_weld_time = null, maintenance = null)
	return entry_make(ENTRY_MACHINE_INTERACTION_CONFIG, null, list("clicksound" = clicksound, "clickvol" = clickvol, "interact_offline" = interact_offline, "maintenance_wrench_time" = maintenance_wrench_time, "maintenance_weld_time" = maintenance_weld_time, "maintenance" = maintenance))

/datum/type_trait/machine_interaction_config
	var/clicksound = null
	var/clickvol = 40
	var/interact_offline = 0
	var/maintenance_wrench_time = 0
	var/maintenance_weld_time = 2 SECONDS
	var/maintenance = NONE

/datum/type_trait/machine_interaction_config/copy_values(datum/type_trait/machine_interaction_config/into)
	into.clicksound = clicksound
	into.clickvol = clickvol
	into.interact_offline = interact_offline
	into.maintenance_wrench_time = maintenance_wrench_time
	into.maintenance_weld_time = maintenance_weld_time
	into.maintenance = maintenance

/datum/entry_engine/type_trait/machine_interaction_config
	kind = ENTRY_MACHINE_INTERACTION_CONFIG
	trait_type = /datum/type_trait/machine_interaction_config
	publish_key = MACHINE_INTERACTION_CONFIG_KEY
	base_type = /obj/machinery
	var_names = list("clicksound" = "clicksound", "clickvol" = "clickvol", "interact_offline" = "interact_offline", "maintenance_wrench_time" = "maintenance_wrench_time", "maintenance_weld_time" = "maintenance_weld_time", "maintenance_flags" = "maintenance")

READS_AS(/proc/machine_interaction_config_of, MACHINE_INTERACTION_CONFIG_KEY)
/proc/machine_interaction_config_of(obj/machinery/holder) as /datum/type_trait/machine_interaction_config
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_MACHINE_INTERACTION_CONFIG)

/proc/machine_interaction_config_of_type(path) as /datum/type_trait/machine_interaction_config
	READS_FROM()
	return type_trait_of_type(path, ENTRY_MACHINE_INTERACTION_CONFIG)

/obj/machinery/proc/set_maintenance_flags(value)
	return set_trait(src, ENTRY_MACHINE_INTERACTION_CONFIG, "maintenance", value)
