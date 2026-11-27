/proc/test()
    var/alist/A = alist()
    for (var/k = 5, v in A)
        world.log << k
