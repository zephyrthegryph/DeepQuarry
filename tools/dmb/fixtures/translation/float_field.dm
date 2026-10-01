/datum/float_owner
    var/value
/proc/fa_zero(var/datum/float_owner/owner)
    owner.value = 0
/proc/fa_one(var/datum/float_owner/owner)
    owner.value = 1
/proc/fa_name_zero(var/atom/owner)
    owner.name = 0
/proc/fa_name_one(var/atom/owner)
    owner.name = 1
/proc/fa_return(var/datum/float_owner/owner)
    return owner.value = 1