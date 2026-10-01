/proc/positive_modulo()
    return 5.5 % 2
/proc/negative_modulo()
    return -5.5 % 2
/proc/fractional_divisor_modulo()
    return 5.5 % 2.75
/world/New()
    ..()
    world.log << "INTEGER_MODULO [positive_modulo()] [negative_modulo()] [fractional_divisor_modulo()]"
    del(world)
