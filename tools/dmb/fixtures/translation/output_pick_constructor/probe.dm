/proc/simple(mob/M)
    M << sound(pick('p1.ogg','p2.ogg','p3.ogg','p4.ogg'))
/proc/conditional(mob/M,v)
    if(v)
        v--
    else if(prob(15))
        M << sound(pick('p1.ogg','p2.ogg','p3.ogg','p4.ogg'))
    return v
/proc/conditional_file(mob/M,v)
    if(v)
        v--
    else if(prob(15))
        M << file(pick('p1.ogg','p2.ogg','p3.ogg','p4.ogg'))
    return v
/proc/constant_weighted(mob/M)
    M << sound(pick(1;'p1.ogg',2;'p2.ogg'))
/proc/dynamic_weighted(mob/M,w)
    M << sound(pick(w;'p1.ogg',2;'p2.ogg'))
