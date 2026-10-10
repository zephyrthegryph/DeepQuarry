// Compile-only receiver/cache operand oracle. No production macros or runtime.
/world
    name = "Receiver operations compile oracle"

/datum/receiver_holder
    var/list/by_type
    var/datum/receiver_holder/child

var/global/datum/receiver_holder/global_holder

/datum/receiver_base
    var/list/by_type
    var/datum/receiver_holder/holder

/datum/receiver_base/proc/check()
    return 17

/datum/receiver_base/derived/check()
    if(global_holder.by_type[type] == src)
        global_holder.by_type -= type
    return ..()

/datum/receiver_base/proc/direct_receiver()
    if(src.by_type[type] == src)
        src.by_type -= type
    return 23

/datum/receiver_base/proc/nested_receiver()
    if(global_holder.child.by_type[type] == src)
        global_holder.child.by_type -= type
    return 29

/datum/receiver_base/proc/local_receiver(datum/receiver_holder/target)
    if(target.by_type[type] == src)
        target.by_type -= type
    return 31

/datum/receiver_base/proc/member_receiver()
    if(holder.by_type[type] == src)
        holder.by_type -= type
    return 37
