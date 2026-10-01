/obj/mod_list_item
    var/amount = 0
/datum/mod_list_holder
    var/list/presets = list(/obj/mod_list_item{amount=20}, /obj/mod_list_item{amount=21})
/proc/mod_list_proc()
    return list(/obj/mod_list_item{amount=22})