/obj/safe_target
    var/foo
/proc/safe_loop_assign(var/obj/safe_target/a)
    for(a?.foo in list(1,2))
        world.log << a.foo
