/proc/termination(a)
    if(a)
        return
    else
        return
    switch(1)
        if(0)
            a = 1

/proc/false_arm(a)
    if(0)
        switch(1)
            if(0)
                a = 1
    else
        a = 2
    switch(2)
        if(0)
            a = 3

/proc/loop_reset(a)
    while(a)
        return
    switch(3)
        if(0)
            a = 1

/proc/fuzzy_break(a)
    while(a)
        break
        if(4)
            a = 1

/proc/spawn_cleanup(a)
    spawn(0)
        return
    switch(5)
        if(0)
            a = 1

/proc/conditions(a)
    for(var/i=0,1==2,i++)
        a = 1
    switch((1))
        if(0)
            a = 2
    switch(1+2)
        if(0)
            a = 3
    if(1==2)
        a = 4
    else if(a)
        a = 5
    switch("x")
        if(0)
            a = 6
