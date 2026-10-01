/mob/verb/hidden_parent()
    set hidden = 1
    set category = "Parent"
    set desc = "Parent desc"
    return 1
/mob/child/hidden_parent()
    return 2
/mob/child2/hidden_parent()
    set hidden = 0
    return 3
/mob/verb/no_popup_parent()
    set popup_menu = 0
    return 4
/mob/child/no_popup_parent()
    return 5