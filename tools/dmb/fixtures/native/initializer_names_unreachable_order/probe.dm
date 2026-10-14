/proc/unused_registration()
    return 7
    return "a_second"

var/global/order_trace = ""
var/global/order_asset = 'contract-resource.txt'

/datum/ordered_value
    var/label

/datum/ordered_value/New(current_label)
    ..()
    label = current_label
    order_trace += "[label];"

/datum/orderkind/z_first
/datum/orderkind/a_second

/proc/observe_static()
    var/static/datum/ordered_value/procedure_value = new /datum/ordered_value("procedure")
    return procedure_value.label

/world/New()
    ..()
    world.log << "DQ_VISIBLE_ORDER boot trace=[order_trace] resource=[order_asset]"
    var/datum/orderholder/holder = new
    var/member_order = ""
    for(var/name in holder.vars)
        if(name == "z_first" || name == "a_second" || name == "type_value")
            member_order += "[name];"
    world.log << "DQ_VISIBLE_ORDER holder trace=[order_trace] vars=[member_order]"
    world.log << "DQ_VISIBLE_ORDER procedure result=[observe_static()] trace=[order_trace]"
    var/type_order = ""
    for(var/type_path in typesof(/datum/orderkind))
        type_order += "[type_path];"
    world.log << "DQ_VISIBLE_ORDER types=[type_order]"
    world.log << "DQ_VISIBLE_ORDER finished"
    shutdown()
