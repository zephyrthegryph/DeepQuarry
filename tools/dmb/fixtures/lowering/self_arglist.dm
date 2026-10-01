/world
/proc/self_arglist(a,b,list/L)
    return .(arglist(a ? L : list(b)))
/datum/self_base/proc/parent_arglist(a,b,list/L)
    return b
/datum/self_base/child/parent_arglist(a,b,list/L)
    return ..(arglist(a ? L : list(b)))
/proc/sound_arglist(a,b,list/L)
    return sound(arglist(a ? L : list(b)))
/proc/image_arglist(a,b,list/L)
    return image(arglist(a ? L : list(b)))
