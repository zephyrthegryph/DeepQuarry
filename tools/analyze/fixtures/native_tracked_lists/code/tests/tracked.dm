/datum/test_box
    var/list/test_items = list()
    var/test_items_version = 99
TRACKED(/datum/test_box, test_items)
/datum/test_box/proc/add_test_items(x)
    return x
