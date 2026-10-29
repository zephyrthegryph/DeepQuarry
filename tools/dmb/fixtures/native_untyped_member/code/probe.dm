/datum/static_owner
    var/static/danger
/datum/typed
    var/danger
/proc/make()
    return new /datum/typed
/proc/check(holder, datum/typed/typed, list/items)
    holder.danger
    typed.danger
    make().danger
    items[1].danger
    (new /datum/typed).danger
    if(holder.danger)
        return
    else if(holder.danger)
        return
    holder.phantom
