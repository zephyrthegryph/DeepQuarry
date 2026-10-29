/proc/escaped_space()
    if("\ ")
        return
/proc/empty_interpolation()
    if("[]")
        return
/proc/escaped_interpolation_prefix()
    if("\ []")
        return
/proc/one_lf_continuation()
    if("\
")
        return
/proc/two_lf_continuation()
    if("\

")
        return
/proc/three_lf_continuation()
    if("\


")
        return
