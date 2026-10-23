// How a machine is used and serviced: the machine_usage() type trait (doc/rewrite/proposals/base_vars.md). Declared in CAPABILITIES
// (configure(machine_usage(click_volume = 20))), read with usage_of(M).click_volume, written at run time with set_<old var>().
//
//   interface_sound   the sound played when its interface answers
//   click_volume   that sound's volume
//   interact_offline   it can be used while unpowered
//   wrench_time   how long wrenching it takes (deciseconds; 0 uses the default)
//   weld_time   how long welding it takes

STATIC_ENTRY(machine_usage)

/proc/machine_usage(interface_sound = null, click_volume = null, interact_offline = null, wrench_time = null, weld_time = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_MACHINE_USAGE, null, list("interface_sound" = interface_sound, "click_volume" = click_volume, "interact_offline" = interact_offline, "wrench_time" = wrench_time, "weld_time" = weld_time))

/datum/type_trait/machine_usage
	var/interface_sound = null
	var/click_volume = 40
	var/interact_offline = 0
	var/wrench_time = 0
	var/weld_time = 2 SECONDS

/datum/type_trait/machine_usage/copy_values(datum/type_trait/machine_usage/into)
	into.interface_sound = interface_sound
	into.click_volume = click_volume
	into.interact_offline = interact_offline
	into.wrench_time = wrench_time
	into.weld_time = weld_time

/datum/entry_engine/type_trait/machine_usage
	kind = ENTRY_MACHINE_USAGE
	trait_type = /datum/type_trait/machine_usage
	publish_key = MACHINE_USAGE_KEY
	base_type = /obj/machinery
	var_names = list("clicksound" = "interface_sound", "clickvol" = "click_volume", "interact_offline" = "interact_offline", "maintenance_wrench_time" = "wrench_time", "maintenance_weld_time" = "weld_time")

/// The holder's machine_usage values (its own once one was set at run time). Read only.
READS_AS(/proc/usage_of, MACHINE_USAGE_KEY)
/proc/usage_of(obj/machinery/holder) as /datum/type_trait/machine_usage
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_MACHINE_USAGE)

/// What a type declares (no instance): the old initial().
/proc/usage_of_type(type) as /datum/type_trait/machine_usage
	READS_FROM() // declared per type: constant
	return type_trait_of_type(type, ENTRY_MACHINE_USAGE)

/obj/machinery/proc/set_clicksound(value)
	return set_trait(src, ENTRY_MACHINE_USAGE, "interface_sound", value)

/obj/machinery/proc/set_clickvol(value)
	return set_trait(src, ENTRY_MACHINE_USAGE, "click_volume", value)

/obj/machinery/proc/set_interact_offline(value)
	return set_trait(src, ENTRY_MACHINE_USAGE, "interact_offline", value)

/obj/machinery/proc/set_maintenance_wrench_time(value)
	return set_trait(src, ENTRY_MACHINE_USAGE, "wrench_time", value)

/obj/machinery/proc/set_maintenance_weld_time(value)
	return set_trait(src, ENTRY_MACHINE_USAGE, "weld_time", value)
