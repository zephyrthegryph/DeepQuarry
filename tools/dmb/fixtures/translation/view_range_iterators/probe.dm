/proc/view_zero(result)
    for(var/obj/A in view())
        result=A
    return result
/proc/view_one(radius,result)
    for(var/obj/A in view(radius))
        result=A
    return result
/proc/view_two(radius,atom/center,result)
    for(var/obj/A in view(radius,center))
        result=A
    return result
/proc/range_zero(result)
    for(var/obj/A in range())
        result=A
    return result
/proc/range_one(radius,result)
    for(var/obj/A in range(radius))
        result=A
    return result
/proc/range_two(radius,atom/center,result)
    for(var/obj/A in range(radius,center))
        result=A
    return result
/proc/view_any(radius,atom/center,result)
    for(var/obj/A as anything in view(radius,center))
        result=A
    return result
/proc/range_untyped(radius,atom/center,result)
    for(var/A in range(radius,center))
        result=A
    return result
/proc/view_mob(radius,atom/center,result)
    for(var/mob/A in view(radius,center))
        result=A
    return result
/proc/range_turf(radius,atom/center,result)
    for(var/turf/A in range(radius,center))
        result=A
    return result
/proc/view_conditional(radius,other,atom/center,v,result)
    for(var/obj/A in view(v ? radius : other,center))
        result=A
    return result
/proc/range_conditional(radius,atom/center,atom/other,v,result)
    for(var/obj/A in range(radius,v ? center : other))
        result=A
    return result
/proc/view_whole_conditional(radius,atom/center,list/L,v,result)
    for(var/obj/A in (v ? view(radius,center) : L))
        result=A
    return result
/proc/range_whole_conditional(radius,atom/center,list/L,v,result)
    for(var/obj/A in (v ? range(radius,center) : L))
        result=A
    return result

/proc/mark(v)
    world.log << v
    return v
/proc/view_effectful(radius,atom/center,result)
    for(var/obj/A in view(mark(radius),mark(center)))
        result=A
    return result
/proc/range_effectful(radius,atom/center,result)
    for(var/obj/A in range(mark(radius),mark(center)))
        result=A
    return result
/proc/oview_zero(radius,atom/center,result,v,other,list/L)
    for(var/obj/A in oview())
        result=A
    return result
/proc/oview_one(radius,atom/center,result,v,other,list/L)
    for(var/obj/A in oview(radius))
        result=A
    return result
/proc/oview_two(radius,atom/center,result,v,other,list/L)
    for(var/obj/A in oview(radius,center))
        result=A
    return result
/proc/oview_any(radius,atom/center,result,v,other,list/L)
    for(var/obj/A as anything in oview(radius,center))
        result=A
    return result
/proc/oview_untyped(radius,atom/center,result,v,other,list/L)
    for(var/A in oview(radius,center))
        result=A
    return result
/proc/oview_conditional(radius,atom/center,result,v,other,list/L)
    for(var/obj/A in oview(v ? radius : other,center))
        result=A
    return result
/proc/oview_whole_conditional(radius,atom/center,result,v,other,list/L)
    for(var/obj/A in (v ? oview(radius,center) : L))
        result=A
    return result
/proc/oview_list_0(radius)
    return oview()
/proc/oview_list_1(radius)
    return oview(radius)
/proc/viewers_zero(radius,atom/center,result,v,other,list/L)
    for(var/mob/A in viewers())
        result=A
    return result
/proc/viewers_one(radius,atom/center,result,v,other,list/L)
    for(var/mob/A in viewers(radius))
        result=A
    return result
/proc/viewers_two(radius,atom/center,result,v,other,list/L)
    for(var/mob/A in viewers(radius,center))
        result=A
    return result
/proc/viewers_any(radius,atom/center,result,v,other,list/L)
    for(var/mob/A as anything in viewers(radius,center))
        result=A
    return result
/proc/viewers_untyped(radius,atom/center,result,v,other,list/L)
    for(var/A in viewers(radius,center))
        result=A
    return result
/proc/viewers_conditional(radius,atom/center,result,v,other,list/L)
    for(var/mob/A in viewers(v ? radius : other,center))
        result=A
    return result
/proc/viewers_whole_conditional(radius,atom/center,result,v,other,list/L)
    for(var/mob/A in (v ? viewers(radius,center) : L))
        result=A
    return result
/proc/viewers_list_0(radius)
    return viewers()
/proc/viewers_list_1(radius)
    return viewers(radius)
/proc/oviewers_zero(radius,atom/center,result,v,other,list/L)
    for(var/mob/A in oviewers())
        result=A
    return result
/proc/oviewers_one(radius,atom/center,result,v,other,list/L)
    for(var/mob/A in oviewers(radius))
        result=A
    return result
/proc/oviewers_two(radius,atom/center,result,v,other,list/L)
    for(var/mob/A in oviewers(radius,center))
        result=A
    return result
/proc/oviewers_any(radius,atom/center,result,v,other,list/L)
    for(var/mob/A as anything in oviewers(radius,center))
        result=A
    return result
/proc/oviewers_untyped(radius,atom/center,result,v,other,list/L)
    for(var/A in oviewers(radius,center))
        result=A
    return result
/proc/oviewers_conditional(radius,atom/center,result,v,other,list/L)
    for(var/mob/A in oviewers(v ? radius : other,center))
        result=A
    return result
/proc/oviewers_whole_conditional(radius,atom/center,result,v,other,list/L)
    for(var/mob/A in (v ? oviewers(radius,center) : L))
        result=A
    return result
/proc/oviewers_list_0(radius)
    return oviewers()
/proc/oviewers_list_1(radius)
    return oviewers(radius)
/proc/hearers_zero(radius,atom/center,result,v,other,list/L)
    for(var/mob/A in hearers())
        result=A
    return result
/proc/hearers_one(radius,atom/center,result,v,other,list/L)
    for(var/mob/A in hearers(radius))
        result=A
    return result
/proc/hearers_two(radius,atom/center,result,v,other,list/L)
    for(var/mob/A in hearers(radius,center))
        result=A
    return result
/proc/hearers_any(radius,atom/center,result,v,other,list/L)
    for(var/mob/A as anything in hearers(radius,center))
        result=A
    return result
/proc/hearers_untyped(radius,atom/center,result,v,other,list/L)
    for(var/A in hearers(radius,center))
        result=A
    return result
/proc/hearers_conditional(radius,atom/center,result,v,other,list/L)
    for(var/mob/A in hearers(v ? radius : other,center))
        result=A
    return result
/proc/hearers_whole_conditional(radius,atom/center,result,v,other,list/L)
    for(var/mob/A in (v ? hearers(radius,center) : L))
        result=A
    return result
/proc/hearers_list_0(radius)
    return hearers()
/proc/hearers_list_1(radius)
    return hearers(radius)
/proc/ohearers_zero(radius,atom/center,result,v,other,list/L)
    for(var/mob/A in ohearers())
        result=A
    return result
/proc/ohearers_one(radius,atom/center,result,v,other,list/L)
    for(var/mob/A in ohearers(radius))
        result=A
    return result
/proc/ohearers_two(radius,atom/center,result,v,other,list/L)
    for(var/mob/A in ohearers(radius,center))
        result=A
    return result
/proc/ohearers_any(radius,atom/center,result,v,other,list/L)
    for(var/mob/A as anything in ohearers(radius,center))
        result=A
    return result
/proc/ohearers_untyped(radius,atom/center,result,v,other,list/L)
    for(var/A in ohearers(radius,center))
        result=A
    return result
/proc/ohearers_conditional(radius,atom/center,result,v,other,list/L)
    for(var/mob/A in ohearers(v ? radius : other,center))
        result=A
    return result
/proc/ohearers_whole_conditional(radius,atom/center,result,v,other,list/L)
    for(var/mob/A in (v ? ohearers(radius,center) : L))
        result=A
    return result
/proc/ohearers_list_0(radius)
    return ohearers()
/proc/ohearers_list_1(radius)
    return ohearers(radius)
