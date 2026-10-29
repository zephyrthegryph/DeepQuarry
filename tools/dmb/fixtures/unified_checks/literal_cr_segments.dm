/proc/cr_only(a)
    if("")
        return
/proc/crlf_continuation(a)
    if("\
")
        return
/proc/crlf_second_lf(a)
    if("\

")
        return
/proc/lf_second_lf(a)
    if("\

")
        return
/proc/interpolation_cr(a)
    if("[a]")
        return
/proc/raw_cr(a)
    if(@{""})
        return
