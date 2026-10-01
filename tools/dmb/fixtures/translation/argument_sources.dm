/proc/in_view(mob/M in view())
    return M

/proc/in_oview(mob/M in oview())
    return M

/proc/in_range(mob/M in range(5))
    return M

/proc/in_usr_contents(obj/O in usr.contents)
    return O

/proc/in_world(atom/A in world)
    return A
