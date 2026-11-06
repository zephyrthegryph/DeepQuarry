/length(E)
    set SpacemanDMM_return_type = /image
    return null
/proc/length(E) as /turf
    return null
/proc/abs(A) as /image
    return null
/mob/Login()
    set SpacemanDMM_return_type = /image
    return null
/mob/image_dir_child/proc/Login() as /turf
    return null
/proc/probe_builtin_image_dir(mob/M, mob/image_dir_child/C)
    length(null).dir = 2
    ::length(null).dir = 2
    abs(2).dir = 2
    sqrt(2).dir = 2
    M.Login().dir = 2
    C.Login().dir = 2
    image().dir = 2
/icon/proc/New() as /image
    return null
/proc/probe_fixed_implicit(icon/I, matrix/M)
    I.New().dir = 2
    M.New().dir = 2
