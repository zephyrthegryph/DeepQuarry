// Independent storage lifetime contract; no game state or FFI.
var/global/static_initializations = 0
var/global/instance_initializations = 0
var/const/lifetime_resource = 'contract-resource.txt'

/proc/next_static_value()
    static_initializations++
    return 7

/proc/next_instance_value()
    instance_initializations++
    return instance_initializations * 11

/datum/lifetime_receiver
    var/static/shared_value = next_static_value()
    var/instance_value

/datum/lifetime_receiver/New()
    ..()
    instance_value = next_instance_value()

/world/New()
    ..()
    // Force a real RSC for the existing retained pair contract.
    file2text(lifetime_resource)
    var/datum/lifetime_receiver/first = new
    var/datum/lifetime_receiver/second = new
    world.log << "DQ_LIFETIME static_count [static_initializations]"
    world.log << "DQ_LIFETIME static_first [first.shared_value]"
    world.log << "DQ_LIFETIME static_second [second.shared_value]"
    first.shared_value = 19
    world.log << "DQ_LIFETIME static_after_write [second.shared_value]"
    world.log << "DQ_LIFETIME instance_count [instance_initializations]"
    world.log << "DQ_LIFETIME instance_first [first.instance_value]"
    world.log << "DQ_LIFETIME instance_second [second.instance_value]"
    world.log << "DQ_LIFETIME finished"
    shutdown()
