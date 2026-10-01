/proc/switch_constant(var/x)
    switch(x)
        if(1) return 10
        if(2) return 20
        else return 30
/world/New()
    ..()
    world.log << switch_constant(1)
    world.log << switch_constant(2)
    world.log << switch_constant(3)
