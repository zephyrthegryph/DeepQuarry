/datum/color_holder
    var/color
/proc/method_arglist_field(var/icon/I,var/datum/color_holder/a)
    I.MapColors(arglist(a.color))
