/proc/computed_field(var/list/items)
    return items[1].name

/proc/computed_field_new()
    return (new /obj()).name

/proc/computed_field_branch(var/choice, var/atom/first, var/atom/second)
    return (choice ? first : second).name

/proc/computed_field_store(var/list/values, var/list/items)
    values[1] = items[2].name
