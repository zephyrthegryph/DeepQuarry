/datum/proc_first/proc/choose_face()
    set SpacemanDMM_return_type = /image
    return null
/datum/proc_first/verb/choose_face()
    set SpacemanDMM_return_type = /turf
    return null
/datum/verb_first/verb/choose_face()
    set SpacemanDMM_return_type = /turf
    return null
/datum/verb_first/proc/choose_face()
    set SpacemanDMM_return_type = /image
    return null
/datum/implicit_last/proc/choose_face()
    set SpacemanDMM_return_type = /turf
    return null
/datum/implicit_last/verb/choose_face()
    set SpacemanDMM_return_type = /turf
    return null
/datum/implicit_last/choose_face()
    set SpacemanDMM_return_type = /image
    return null
/datum/first_annotation/proc/choose_face() as /image
    return null
/datum/first_annotation/verb/choose_face() as /turf
    return null
/datum/first_annotation/choose_face()
    set SpacemanDMM_return_type = /turf
    return null
/datum/bodyless_first/proc/choose_face()
/datum/bodyless_first/verb/choose_face()
    set SpacemanDMM_return_type = /image
    return null
/proc/probe_mixed(datum/proc_first/P, datum/verb_first/V, datum/implicit_last/I, datum/first_annotation/A, datum/bodyless_first/B)
    P.choose_face().dir = 2
    V.choose_face().dir = 2
    I.choose_face().dir = 2
    A.choose_face().dir = 2
    B.choose_face().dir = 2
/datum/losing_body/proc/choose_face()
    return null
/datum/losing_body/verb/choose_face()
    var/image/I
    I.dir = 2
    return null
/datum/inherited_mixed/proc/choose_face() as /image
    return null
/datum/inherited_mixed/child/verb/choose_face() as /turf
    return null
/proc/probe_inherited_mixed(datum/inherited_mixed/P, datum/inherited_mixed/child/C)
    P.choose_face().dir = 2
    C.choose_face().dir = 2
