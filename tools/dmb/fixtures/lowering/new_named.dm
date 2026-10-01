/obj/sample
    New(var/foo,var/bar)
        ..()
/proc/new_named()
    return new /obj/sample(bar=2,foo=1)
/proc/new_named_dynamic(var/T)
    return new T(bar=2,foo=1)
