/proc/test()
    var/alist/A = alist()
    for (k, v in A)
        world.log << k
        world.log << v
