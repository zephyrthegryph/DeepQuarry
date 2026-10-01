/datum/other_owner
    proc/get_values()
        set name = "Other Fancy"
        return 9
/datum/named_owner
    proc/get_values()
        set name = "Fancy Value"
        return 7
    proc/normal_values()
        return 8
/proc/name_untyped(owner)
    return owner:get_values()
/proc/name_typed(datum/named_owner/owner)
    return owner.get_values()
/proc/name_call_identifier(owner)
    return call(owner,"get_values")()
/proc/name_call_display(owner)
    return call(owner,"get values")()
/proc/name_call_authored(owner)
    return call(owner,"Fancy Value")()
/proc/name_normal_untyped(owner)
    return owner:normal_values()
/proc/name_normal_typed(datum/named_owner/owner)
    return owner.normal_values()
/proc/name_other_typed(datum/other_owner/owner)
    return owner.get_values()
/proc/name_other_colon(datum/other_owner/owner)
    return owner:get_values()
