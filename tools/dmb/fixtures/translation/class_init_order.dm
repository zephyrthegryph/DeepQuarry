var/global/list/trace = list()
/datum/value/New(label)
    trace += label
/datum/early
    parent_type = /datum/value
/datum/holder
    var/datum/value/a = new /datum/late("A")
    var/datum/value/b = new /datum/early("B")
/datum/late
    parent_type = /datum/value
