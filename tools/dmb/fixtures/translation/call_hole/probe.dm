/proc/call_hole_target(a,b,c)
    return b
/proc/call_hole()
    return call_hole_target(1,,3)
