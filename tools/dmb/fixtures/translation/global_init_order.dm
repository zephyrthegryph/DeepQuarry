var/global/list/trace = list()
/datum/value/New(label)
    trace += label
/datum/early
    parent_type = /datum/value
var/global/datum/value/A = new /datum/late("global A")
var/global/datum/value/B = new /datum/early("global B")
/proc/static_order()
    var/static/datum/value/SA = new /datum/late("static A")
    var/static/datum/value/SB = new /datum/early("static B")
    return list(SA,SB)
/datum/late
    parent_type = /datum/value
