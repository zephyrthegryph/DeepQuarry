/proc/controls(a, b, c)
    if   (   !a & b)
        a = 1
    else if ( !b | c)
        a = 2
    if (
        !a & b
    )
        a = 3
    do
        a = a + 1
    while    (  !c ^ a)
    if (( !a & b))
        a = 4
