var/global/order_trace = ""
var/global/order_asset = 'contract-resource.txt'

/proc/record_initializer(label, value)
    order_trace += "[label]=[value];"
    return value

/world/New()
    ..()
    var/datum/ordered/probe = new
    world.log << "DQ_INIT_ORDER values first=[probe.first] second=[probe.second] trace=[order_trace] resource=[order_asset]"
    if(probe.first != 11 || probe.second != 12 || order_trace != "first=11;second=12;")
        world.log << "DQ_INIT_ORDER FAILED"
        shutdown()
        return
    world.log << "DQ_INIT_ORDER PASS"
    world.log << "DQ_INIT_ORDER finished"
    shutdown()
