/datum/fa_owner
    var/value
    var/datum/fa_owner/child
/proc/fa_identity(a)
    return a
/proc/fa_direct(var/datum/fa_owner/a, var/datum/fa_owner/b)
    return a.value += (a=b)
/proc/fa_computed(var/datum/fa_owner/a, var/datum/fa_owner/b)
    return fa_identity(a).value += (a=b)
/proc/fa_nested(var/datum/fa_owner/a, var/datum/fa_owner/b)
    return a.child.value += (a.child=b)
/proc/fa_pre(var/datum/fa_owner/a)
    return ++a.value
/proc/fa_post(var/datum/fa_owner/a)
    return a.value++
/proc/fa_add_expr(var/datum/fa_owner/a,v)
    return a.value += v
/proc/fa_add_stmt(var/datum/fa_owner/a,v)
    a.value += v
/proc/fa_sub_expr(var/datum/fa_owner/a,v)
    return a.value -= v
/proc/fa_sub_stmt(var/datum/fa_owner/a,v)
    a.value -= v
/proc/fa_mul_expr(var/datum/fa_owner/a,v)
    return a.value *= v
/proc/fa_mul_stmt(var/datum/fa_owner/a,v)
    a.value *= v
/proc/fa_div_expr(var/datum/fa_owner/a,v)
    return a.value /= v
/proc/fa_div_stmt(var/datum/fa_owner/a,v)
    a.value /= v
/proc/fa_mod_expr(var/datum/fa_owner/a,v)
    return a.value %= v
/proc/fa_mod_stmt(var/datum/fa_owner/a,v)
    a.value %= v
/proc/fa_and_expr(var/datum/fa_owner/a,v)
    return a.value &= v
/proc/fa_and_stmt(var/datum/fa_owner/a,v)
    a.value &= v
/proc/fa_or_expr(var/datum/fa_owner/a,v)
    return a.value |= v
/proc/fa_or_stmt(var/datum/fa_owner/a,v)
    a.value |= v
/proc/fa_xor_expr(var/datum/fa_owner/a,v)
    return a.value ^= v
/proc/fa_xor_stmt(var/datum/fa_owner/a,v)
    a.value ^= v
/proc/fa_shl_expr(var/datum/fa_owner/a,v)
    return a.value <<= v
/proc/fa_shl_stmt(var/datum/fa_owner/a,v)
    a.value <<= v
/proc/fa_shr_expr(var/datum/fa_owner/a,v)
    return a.value >>= v
/proc/fa_shr_stmt(var/datum/fa_owner/a,v)
    a.value >>= v
/proc/fa_modulo_expr(var/datum/fa_owner/a,v)
    return a.value %%= v
/proc/fa_modulo_stmt(var/datum/fa_owner/a,v)
    a.value %%= v
/proc/fa_preinc_stmt(var/datum/fa_owner/a)
    ++a.value
/proc/fa_preinc_expr(var/datum/fa_owner/a)
    return ++a.value
/proc/fa_predec_stmt(var/datum/fa_owner/a)
    --a.value
/proc/fa_predec_expr(var/datum/fa_owner/a)
    return --a.value
/proc/fa_postinc_stmt(var/datum/fa_owner/a)
    a.value++
/proc/fa_postinc_expr(var/datum/fa_owner/a)
    return a.value++
/proc/fa_postdec_stmt(var/datum/fa_owner/a)
    a.value--
/proc/fa_postdec_expr(var/datum/fa_owner/a)
    return a.value--
