/datum/safe_target
    var/value=1
/proc/safe_assign(datum/safe_target/a,b)
    a?.value = b
/proc/safe_add(datum/safe_target/a,b)
    a?.value += b
/proc/safe_sub(datum/safe_target/a,b)
    a?.value -= b
/proc/safe_mul(datum/safe_target/a,b)
    a?.value *= b

/proc/safe_div(datum/safe_target/a,b)
    a?.value /= b
/proc/safe_mod(datum/safe_target/a,b)
    a?.value %= b

/proc/safe_and(datum/safe_target/a,b)
    a?.value &= b
/proc/safe_or(datum/safe_target/a,b)
    a?.value |= b
/proc/safe_xor(datum/safe_target/a,b)
    a?.value ^= b
/proc/safe_shift(datum/safe_target/a,b)
    a?.value <<= b

/proc/safe_expression(datum/safe_target/a,b)
    return (a?.value = b)
/proc/safe_postincrement(datum/safe_target/a)
    return a?.value++

/proc/safe_preincrement(datum/safe_target/a)
    return ++a?.value
/proc/safe_predecrement(datum/safe_target/a)
    return --a?.value
/proc/safe_postdecrement(datum/safe_target/a)
    return a?.value--
/proc/safe_rshift(datum/safe_target/a,b)
    a?.value >>= b

/datum/safe_target
    var/datum/safe_target/child
/proc/safe_nested(datum/safe_target/a,b)
    a?.child?.value = b

/proc/safe_expression_add(datum/safe_target/a,b)
    return (a?.value += b)
/proc/safe_expression_sub(datum/safe_target/a,b)
    return (a?.value -= b)
