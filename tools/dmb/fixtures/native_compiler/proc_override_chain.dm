/datum/override_probe
    var/last_ref
/datum/override_probe/child
/datum/override_probe/child/grandchild
/datum/override_probe/proc/foo()
    last_ref = __PROC__
    return 10
/datum/override_probe/child/foo()
    last_ref = __PROC__
    return ..() + 20
/datum/override_probe/child/grandchild/foo()
    last_ref = __PROC__
    return ..() + 30
/datum/override_probe/proc/under_score()
    set name = "Custom Visible Name"
    return __PROC__
/datum/override_probe/proc/plain_method()
    return 19
/proc/global_under_score()
    set name = "Global Visible Name"
    return __PROC__
/proc/invoke_source_name(datum/override_probe/D)
    return D.under_score()
/proc/invoke_dynamic_source_name(datum/override_probe/D)
    return call(D, "under_score")()
/proc/invoke_named_colon(datum/override_probe/D)
    return D:under_score()
/proc/invoke_plain_typed(datum/override_probe/D)
    return D.plain_method()
/proc/invoke_plain_colon(datum/override_probe/D)
    return D:plain_method()
/proc/invoke_named_colon_untyped(D)
    return D:under_score()
/proc/invoke_plain_colon_untyped(D)
    return D:plain_method()
/proc/invoke_global_source_name()
    return global_under_score()
