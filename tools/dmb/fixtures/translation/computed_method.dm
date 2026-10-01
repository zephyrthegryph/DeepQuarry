/datum/cm
    proc/value(x)
        return x
/proc/computed_owner(datum/cm/O)
    return O
/proc/computed_method(datum/cm/O, x)
    return computed_owner(O).value(x)
/proc/conditional_method(choice, datum/cm/O, datum/cm/P, x)
    return (choice ? O : P).value(x)
