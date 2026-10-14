/obj/link_order/z_child
    parent_type = /obj/link_order/base
    var/z_child_value = 3
/obj/link_order/base
    var/z_value = 1
    var/a_value = 2
    verb/z_verb()
        set name = "Z Visible"
        set desc = "Z description"
        set category = "Phase0"
        set waitfor = 1
        set background = 0
        set instant = 0
        set hidden = 1
        set popup_menu = 0
        set invisibility = 10
        set src in world
        return "z"
    verb/a_verb()
        set name = "A Visible"
        set category = "Phase0"
        return "a"
    proc/foo()
        return "base"
/obj/link_order/a_child
    parent_type = /obj/link_order/base
    foo()
        return "child|" + ..()
/obj/link_order/base
    var/reopened_value = 4
/world/New()
    ..()
    var/list/type_names = list()
    for(var/T in typesof(/obj/link_order))
        type_names += "[T]"
    phase0_emit("types", type_names)
    var/obj/link_order/base/B = new
    var/list/variable_names = list()
    for(var/V in B.vars)
        variable_names += "[V]"
    phase0_emit("vars", variable_names)
    var/list/verb_names = list()
    for(var/F in B.verbs)
        verb_names += "[F]"
    phase0_emit("verbs", verb_names)
    var/obj/link_order/a_child/C = new
    phase0_emit("override_result", C.foo())
    phase0_emit("proc_reference", "[/obj/link_order/base/proc/foo]")
    phase0_emit("verb_reference", "[/obj/link_order/base/verb/z_verb]")
    phase0_finish()
