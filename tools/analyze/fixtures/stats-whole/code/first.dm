#if 0
/obj/base
    var/inherited = 1
/datum/actual
    var/remote = 1
/obj/lexical
    parent_type = /datum/actual
STAT(/obj/base/child, inherited, ALL)
STAT(/obj/lexical, remote, MAX)
STAT(/atom, density, TOP)
STAT(/obj/a, hidden, ALL, virtual = TRUE)
STAT(/obj/a, explicit, SUM, base = 7, id = 9, reads = list("a  b"), formula = PROC_REF(compute))
STAT(/obj/a, product, PRODUCT)
STAT(/obj/a, unknown, UNKNOWN)
STAT(/obj/a, missingprev, ANY)
STAT(/obj/a, éß, ALL)
STAT(/obj/a, badargs)
STAT(/obj/a, badopt, SUM, not_an_option)
#endif
