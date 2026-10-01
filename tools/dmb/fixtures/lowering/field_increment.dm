/datum/field_counter
    var/value = 3

/proc/field_identity(var/datum/field_counter/owner)
    return owner

/proc/field_postincrement(var/datum/field_counter/owner)
    return owner.value++

/proc/field_postdecrement(var/datum/field_counter/owner)
    return owner.value--

/proc/field_preincrement(var/datum/field_counter/owner)
    return ++owner.value

/proc/field_predecrement(var/datum/field_counter/owner)
    return --owner.value

/proc/field_computed_increment(var/datum/field_counter/owner)
    return field_identity(owner).value++
