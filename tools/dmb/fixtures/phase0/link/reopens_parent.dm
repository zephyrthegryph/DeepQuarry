/obj/phase0_reopen/z_child
    parent_type = /obj/phase0_reopen/base
    chain()
        return "child|" + ..()
/obj/phase0_reopen/base
    var/z_first = 1
    verb/a_source()
        set name = "Z displayed"
        return "a"
    proc/chain()
        return "base"
/obj/phase0_reopen/a_child
    parent_type = /obj/phase0_reopen/base
/obj/phase0_reopen/base
    var/a_later = 2
    verb/z_source()
        set name = "A displayed"
        return "z"
/world/New()
    ..()
    var/list/types_seen = list()
    for(var/T in typesof(/obj/phase0_reopen))
        types_seen += "[T]"
    phase0_emit("reopen_types", types_seen)
    var/obj/phase0_reopen/base/B = new
    var/list/verbs_seen = list()
    for(var/V in B.verbs)
        verbs_seen += "[V]"
    phase0_emit("reopen_verbs", verbs_seen)
    var/list/vars_seen = list()
    for(var/V in B.vars)
        vars_seen += "[V]"
    phase0_emit("reopen_vars", vars_seen)
    var/obj/phase0_reopen/z_child/C = new
    phase0_emit("reopen_override", C.chain())
    phase0_finish()
