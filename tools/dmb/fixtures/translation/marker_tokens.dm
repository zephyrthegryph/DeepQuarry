/datum/token_a
/datum/token_b
/var/global/a = new /datum/token_a(1)
/var/global/b = new /datum/token_a(2)
/var/global/c = new /datum/token_b(1)
/var/global/d = list(1)
/var/global/e = list(1)
/datum/holder
    var/x = new /datum/token_a(1)
    var/y = new /datum/token_a(2)
    var/list/z = list(1)
    var/static/s = new /datum/token_a(1)
    var/static/t = new /datum/token_a(2)
/proc/token_static()
    var/static/p = new /datum/token_b(1)
    var/static/q = new /datum/token_b(2)
    return list(p,q,a,b,c,d,e)