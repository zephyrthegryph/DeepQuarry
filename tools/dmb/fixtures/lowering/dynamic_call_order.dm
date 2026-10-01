/var/list/force_516 = alist()
/var/target_path = /proc/dynamic_probe_target
/var/target_owner
/var/target_name = "action"
/proc/dynamic_probe_target(a, b)
    return a + b
/datum/dynamic_probe/proc/action(a, b)
    return a + b
/proc/replace_dynamic_target()
    target_path = /proc/replace_dynamic_target
    target_owner = new /datum/dynamic_probe
    target_name = "replacement"
    return 3
/proc/dynamic_path_mutation()
    return call(target_path)(replace_dynamic_target(), 4)
/proc/dynamic_owner_mutation()
    return call(target_owner, target_name)(replace_dynamic_target(), 4)
/proc/dynamic_computed_targets()
    return call((target_owner || new /datum/dynamic_probe), (target_name || "action"))(replace_dynamic_target(), 4)
/proc/dynamic_path_arglist_mutation()
    return call(target_path)(arglist(list(replace_dynamic_target(), 4)))
/proc/dynamic_owner_arglist_mutation()
    return call(target_owner, target_name)(arglist(list(replace_dynamic_target(), 4)))
/proc/dynamic_named_arguments()
    return call(target_owner, "action")(b = replace_dynamic_target(), a = 4)
/proc/dynamic_external_mutation()
    return call_ext(target_owner, target_name)(replace_dynamic_target(), 4)
/proc/dynamic_external_arglist()
    return call_ext(target_owner, target_name)(arglist(list(replace_dynamic_target(), 4)))
