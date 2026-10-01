/proc/test(n)
    var/i=0
    do
        i += 1
    while(i < n)
    return i
/proc/spawn_test(n)
    spawn(2)
        n = n + 1
    return n
