/var/list/force_516 = alist()
/datum/receiver_leaf/proc/action(value)
    return value
/datum/receiver_box
    var/datum/receiver_leaf/child
/proc/replace_child(datum/receiver_box/box)
    box.child = new /datum/receiver_leaf
    return 1
/proc/receiver_field_argument(datum/receiver_box/box)
    return box.child.action(replace_child(box))
/proc/receiver_field_safe_argument(datum/receiver_box/box)
    return box.child?.action(replace_child(box))
/proc/receiver_field_expression_argument(datum/receiver_box/box)
    return (box.child || new /datum/receiver_leaf).action(replace_child(box))
