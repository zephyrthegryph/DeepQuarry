/mob/verb/parent_action()
    set name = "Parent Action"
    return 1
/mob/child/parent_action()
    return 2
/mob/child/verb/own_action()
    return 3