/proc/null_list_slot(var/list/values, var/key)
    values[key] = null

/proc/null_field(var/atom/owner)
    owner.name = null
