var/world
world = null
/datum/base
    var/static/kept = 1
    var/ordinary = 1
/datum/base
    kept = 2
    ordinary = 2
/datum/base/child
    kept = 3
/proc/check(holder)
    holder.world
    holder.kept
    holder.ordinary
