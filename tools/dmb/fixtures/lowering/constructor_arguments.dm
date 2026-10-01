/obj/item
    var/a
    var/b
    New(x,y)
        ..()
        a = x
        b = y
/proc/newit(a,b)
    return new /obj/item(a,b)

/proc/newcalc(a,b)
    return new /obj/item(a + 1, b * 2)

