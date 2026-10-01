/proc/resource_switch(x)
    switch(x)
        if(1)
            return 'A.txt'
        else
            return 'B.txt'
/proc/resource_pick()
    return pick(1;'C.txt', 2;'B.txt')
/datum/resource_container
    var/asset='D.txt'
