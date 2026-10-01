/datum/null_scratch
    proc/managed()
        return list(1)
/proc/equal_null(datum/null_scratch/O)
    O.managed()
    return rand(1,2)==null
/proc/builtin_null(datum/null_scratch/O)
    O.managed()
    return isnull(rand(1,2))

/var/null_probe_value
/datum/null_scratch/var/value
/proc/global_managed()
    return list(1)
/proc/global_equal_null()
    global_managed()
    return rand(1,2)==null
/proc/global_not_equal_null()
    global_managed()
    return rand(1,2)!=null
/proc/field_equal_null(datum/null_scratch/O)
    O.managed()
    return O.value==null
/proc/variable_equal_null(datum/null_scratch/O)
    O.managed()
    return null_probe_value==null
/proc/negated_equal_null(datum/null_scratch/O)
    O.managed()
    return !(rand(1,2)==null)
/proc/branch_equal_null(datum/null_scratch/O)
    O.managed()
    if(rand(1,2)==null)
        return 1
    return 0
/proc/literal_null(datum/null_scratch/O)
    O.managed()
    return null==null
/proc/literal_not_null(datum/null_scratch/O)
    O.managed()
    return 1!=null
/proc/reversed_equal_null(datum/null_scratch/O)
    O.managed()
    return null==rand(1,2)
/proc/reversed_not_equal_null(datum/null_scratch/O)
    O.managed()
    return null!=rand(1,2)
/proc/conditional_equal_null(datum/null_scratch/O,a)
    O.managed()
    return rand(1,2)==(a ? null : 1)
/proc/conditional_left_null(datum/null_scratch/O,a)
    O.managed()
    return (a ? null : 1)==rand(1,2)
/proc/ordinary_null_return(datum/null_scratch/O)
    O.managed()
    return null
/proc/parenthesized_equal_null(datum/null_scratch/O)
    O.managed()
    return rand(1,2)==(null)
/proc/assigned_null(datum/null_scratch/O)
    O.managed()
    null_probe_value=null
/proc/list_null(datum/null_scratch/O)
    O.managed()
    return list(null)
/proc/argument_null(datum/null_scratch/O)
    O.managed()
    return global_managed(null)
/proc/interpolation_null(datum/null_scratch/O)
    O.managed()
    return "[null]"
/proc/switched_null(datum/null_scratch/O,a)
    O.managed()
    switch(a)
        if(null) return 1
    return 0
/proc/local_assigned_null(datum/null_scratch/O,a)
    O.managed()
    a=null
/proc/field_assigned_null(datum/null_scratch/O)
    O.managed()
    O.value=null

/var/const/NULL_ALIAS=null
/proc/const_alias_equal_null(datum/null_scratch/O)
    O.managed()
    return NULL_ALIAS==null
/proc/parenthesized_literal_null(datum/null_scratch/O)
    O.managed()
    return (null)==(null)
/proc/local_const_alias_equal_null(datum/null_scratch/O)
    var/const/ALIAS=null
    O.managed()
    return ALIAS==null
/proc/null_sound(datum/null_scratch/O)
    O.managed()
    return sound(null)
/proc/null_image(datum/null_scratch/O)
    O.managed()
    return image(null)
/proc/null_icon(datum/null_scratch/O)
    O.managed()
    return icon(null)
/proc/null_new(datum/null_scratch/O)
    O.managed()
    return new /datum/null_scratch(null)
