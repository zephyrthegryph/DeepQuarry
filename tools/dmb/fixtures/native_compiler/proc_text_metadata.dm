/datum/text_metadata_base/proc/action()
    set name = "Quoted \"action\""
    set desc = "\proper Some description"
    set category = "First " + "Category"
    return 1
/datum/text_metadata_base/child/action()
    return 2
