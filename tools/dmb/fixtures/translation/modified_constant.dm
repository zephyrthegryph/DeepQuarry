/obj/modified_constant
    var/amount = 0
/datum/modified_holder
    var/object_type = /obj/modified_constant{amount=20}
var/global/type_reference = /obj/modified_constant{amount=21}
/proc/modified_constant_value()
    var/target_type = /obj/modified_constant{amount=22}
    return target_type