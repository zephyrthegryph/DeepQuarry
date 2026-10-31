var/global/datum/controller/global_vars/GLOB
var/global/top_boot = 0
var/global/top_runtime = 0
var/global/pair_shadow = 0
var/global/local_shadow = 0
var/global/loop_shadow = 0
/datum/controller/global_vars
    var/list/boot_table
    var/list/runtime_table
    var/version_only
/datum/controller/global_vars/proc/InitGlobalboot_table()
    boot_table = list()
/world/New()
    initialize_boot()
/proc/initialize_boot()
    top_boot = 1
/datum/system
/datum/system/boot
/datum/system/boot/proc/initialize()
    load_private()
    escaped()
    cycle_a()
    repeated()
/datum/system/boot/proc/load_private()
    GLOB.boot_table["key"] = 1
/datum/system/boot/proc/escaped()
    GLOB.runtime_table.Add(1)
/datum/system/boot/proc/cycle_a()
    cycle_b()
/datum/system/boot/proc/cycle_b()
    cycle_a()
/proc/runtime_entry()
    top_runtime++
    escaped()
    PROC_REF(load_private)
/datum/system/boot/proc/repeated()
    GLOB.version_only = 1
/datum/system/boot/repeated()
    return
var/global/global_only_control=0
