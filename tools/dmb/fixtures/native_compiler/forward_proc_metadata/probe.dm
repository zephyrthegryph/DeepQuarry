/datum/parent/child/action()
    return 2
/datum/parent/proc/action()
    set waitfor = 0
    set name = "Visible action"
    set desc = "Inherited description"
    set category = "Inherited category"
    set src in view(2)
    return 1
