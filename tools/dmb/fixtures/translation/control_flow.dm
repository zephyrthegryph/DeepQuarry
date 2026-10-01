/world/New()
    ..()
    var/total = 0
    for(var/i = 1, i <= 4, i++)
        if(i == 2)
            continue
        total += i
    var/status = total == 8 ? "yes" : "no"
    world.log << "CONTROL [total] [status]"
