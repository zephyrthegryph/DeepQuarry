/var/list/force_516=alist()
/var/value=7
/proc/delete_local()
    var/number=7
    del(number)
    return number
/proc/delete_global()
    del(value)
    return value
/proc/delete_index(list/values,key)
    del(values[key])
    return values[key]
/datum/holder
    var/value=7
/datum/holder/proc/delete_field()
    del(value)
    return value
/proc/delete_temporary()
    del(7)
    return 1
/var/list/events=list()
/proc/get_holder(datum/holder/H)
    events += "owner"
    return H
/proc/get_values(list/L)
    events += "list"
    return L
/proc/get_key()
    events += "key"
    return "value"
/proc/delete_effectful_field(datum/holder/H)
    del(get_holder(H).value)
    return H.value
/proc/delete_effectful_index(list/L)
    del(get_values(L)[get_key()])
    return L["value"]
/proc/delete_safe(datum/holder/H)
    del(H?.value)
    return H
/proc/delete_conditional(flag,datum/holder/A,datum/holder/B)
    del((flag ? A : B).value)
    return list(A.value,B.value)

/var/const/null_global=null
/datum/holder
    var/const/null_field=null
/proc/delete_const_global()
    del(null_global)
    return null_global
/proc/delete_const_field(datum/holder/H)
    del(H.null_field)
    return H.null_field
/proc/delete_safe_index(list/L,key)
    del(L?[key])
    return L


/proc/delete_argument(value)
    del(value)
    return value
/proc/delete_list_storage()
    var/list/L=list(1,2)
    del(L)
    return L
/proc/delete_text_storage()
    var/text="text"
    del(text)
    return text
/proc/delete_conditional_value(flag,a,b)
    del(flag ? a : b)
    return list(a,b)
/datum/holder/proc/delete_src()
    del(src)
    return src
/proc/delete_dynamic_field(H)
    del(H:value)
    return H:value
/proc/delete_safe_dynamic_field(H)
    del(H?:value)
    return H
/proc/delete_effectful_const(datum/holder/H)
    del(get_holder(H).null_field)
    return H
/proc/delete_safe_const(datum/holder/H)
    del(H?.null_field)
    return H
/datum/holder/var/other=9
/datum/holder/proc/read_other()
    return other
/datum/holder/proc/delete_mixed_src_fields()
    var/before=other
    del(value)
    return list(before,other,value)
/datum/holder/proc/delete_mixed_src_call_branch(flag)
    var/before=other
    if(flag)
        del(value)
    read_other()
    return list(before,other,value)
