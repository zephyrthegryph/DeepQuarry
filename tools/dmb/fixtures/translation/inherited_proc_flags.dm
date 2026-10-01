/datum/proc/flagged()
    set waitfor = 0
    set background = 1
    set instant = 1
    return 1
/datum/child/flagged()
    return 2
/datum/child2/flagged()
    set waitfor = 1
    set background = 0
    set instant = 0
    return 3