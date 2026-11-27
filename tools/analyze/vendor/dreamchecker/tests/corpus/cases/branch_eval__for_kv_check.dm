/proc/test()
    var/alist/A = alist()
    for (var/k, v in A)
        world.log << k
        world.log << v
