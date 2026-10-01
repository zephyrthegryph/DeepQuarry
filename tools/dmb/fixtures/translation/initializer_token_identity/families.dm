/datum/family_target
/datum/family_target/verb/act()
    return 1
/obj/token_families
    var/alist/a = alist(x=1)
    var/alist/b = alist("x"=1)
    var/alist/c = alist(x=2)
    var/list/d[2]
    var/list/e[2]
    var/list/f[3]
    var/list/empty_a = newlist()
    var/list/empty_b = list()
    var/list/new_a = newlist(/datum/family_target)
    var/list/new_b = newlist(/datum/family_target)
    var/list/new_c = list(new /datum/family_target())
    var/verb_a = new /datum/family_target/verb/act()
    var/verb_b = new /datum/family_target/verb/act()
/particles/token_families
    position = generator("box", list(0,0,0), list(1,1,1))
    velocity = generator("box", list(0,0,0), list(1,1,1))
    drift = generator("box", list(0,0,0), list(2,2,2))

