/datum/item
    var/amount = 7
/proc/typed_index(datum/item/values[])
    return values[1].amount
/proc/typed_iteration(datum/item/values[])
    for(var/datum/item/value in values)
        return value.amount
/proc/typed_context(datum/item/values[])
    values += new
    return values
/proc/plain_list(values[])
    return values[1]
