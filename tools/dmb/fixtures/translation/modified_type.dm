/obj/tagged
    var/amount = 1
    var/list/stuff
/datum/modified_holder
    var/tag_plain = /obj/tagged
    var/tag_modified = /obj/tagged{amount = 20}
    var/tag_modified_other = /obj/tagged{amount = 21}
    var/tag_modified_list = /obj/tagged{stuff = list(1, 2)}
/datum/modified_holder/child
    tag_modified = /obj/tagged{amount = 22}
