/datum/box
    var/specific
    var/wild
    var/ctor_only
    var/shadow
/datum/box/child
/datum/unrelated
    var/specific
/datum/box/New()
    ctor_only = 1
/datum/box/proc/write_typed(datum/box/child/B)
    B.specific += 1
/datum/box/proc/write_unknown(B)
    B.wild++
/datum/box/proc/local_shadow()
    var/shadow
    shadow = 1
/datum/unrelated/proc/read_only()
    return specific
/datum/singleton
    var/list/booted
    var/list/dynamic
/datum/singleton/proc/fill()
    booted = list()
/datum/singleton/proc/poke()
    dynamic.Add(1)
/datum/system/boot/proc/initialize_more()
    var/datum/singleton/S
    S.fill()
