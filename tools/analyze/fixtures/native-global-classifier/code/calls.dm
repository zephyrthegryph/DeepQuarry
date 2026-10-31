/proc/callbacks()
    TYPE_PROC_REF(/datum/system/boot, cycle_a)
    GLOBAL_PROC_REF(initialize_boot)
    var/datum/box/B
    B::write_typed()
    new /datum/box()
    new B()
    ::initialize_boot()
    var/list/local_list
    sortTim(local_list)
    GLOB.runtime_table.len = 2
/proc/binding_scope()
    var/local_shadow
    local_shadow = 2
    for(var/loop_shadow in list())
        loop_shadow = 3
    for(var/key, pair_shadow in list())
        pair_shadow = 4
