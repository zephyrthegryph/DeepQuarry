var/global/order_trace = ""
var/global/order_asset = 'contract-resource.txt'
var/global/datum/ordered_value/previous_ordered

/datum/ordered_value
    var/value

/datum/ordered_value/New(label, amount)
    ..()
    if(label == "second")
        value = previous_ordered.value + 1
    else
        value = amount
    previous_ordered = src
    order_trace += "[label]=[value];"

/world/New()
    ..()
    var/datum/ordered/probe = new
    world.log << "DQ_INIT_ORDER values first=[probe.first.value] second=[probe.second.value] trace=[order_trace] resource=[order_asset]"
    if(probe.first.value != 11 || probe.second.value != 12 || order_trace != "first=11;second=12;")
        world.log << "DQ_INIT_ORDER FAILED"
        shutdown()
        return
    world.log << "DQ_INIT_ORDER PASS"
    world.log << "DQ_INIT_ORDER finished"
    shutdown()
