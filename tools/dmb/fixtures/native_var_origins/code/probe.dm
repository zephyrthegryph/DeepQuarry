/datum/probe
    var/
        item = list(
            1)
        list/
            things
    var/first;var/second = 2
/datum/probe
    second = 3
#define FIELD var/macro_item
/datum/probe
    FIELD
