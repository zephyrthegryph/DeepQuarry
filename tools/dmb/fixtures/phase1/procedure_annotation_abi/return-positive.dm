/datum/item
    var/amount = 7
/proc/plain()
    return 1
/proc/number() as num
    return 1
/proc/object() as /datum/item
    return 1
/proc/unrestricted() as anything
    return 1
/proc/union() as num|null
    return 1
/proc/typed_call()
    return object().amount
